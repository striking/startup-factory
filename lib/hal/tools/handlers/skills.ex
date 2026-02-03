defmodule Hal.Tools.Handlers.Skills do
  @moduledoc """
  Skills-first execution handler.

  This tool provides a single, generic execution boundary for skills defined in
  `.claude/skills/*/SKILL.md`.

  The "brain" decides *which* skill to use and provides the input. HAL validates
  and executes according to the skill's frontmatter (or fallback metadata).

  Supported runners:
  - `cli`: runs a configured CLI command (approval-gated by policy)
  - `hal_tool`: dispatches to an existing HAL tool (so directives/approvals apply)
  """

  require Logger

  alias HAL.Skills.Registry, as: SkillsRegistry
  alias Hal.Tools.Executor

  @default_timeout_ms 300_000

  @doc """
  Run a skill by id (directory name under `.claude/skills/`).

  Args:
  - `skill` (required): skill id (directory name)
  - `input` (required): freeform input for the skill
  - `vars` (optional): template variables for skill runners
  - `working_dir` (optional): override working dir for CLI runner
  - `timeout_ms` (optional): override timeout for CLI runner
  """
  def run(args, opts) when is_map(args) and is_list(opts) do
    skill_id =
      (Map.get(args, "skill") || Map.get(args, :skill) || "") |> to_string() |> String.trim()

    input = Map.get(args, "input") || Map.get(args, :input)

    vars =
      Map.get(args, "vars") || Map.get(args, :vars) || Map.get(args, "params") ||
        Map.get(args, :params) || %{}

    vars = if is_map(vars), do: vars, else: %{}

    cond do
      skill_id == "" ->
        Executor.return_error("Missing required arg: skill")

      not is_binary(input) ->
        Executor.return_error("Missing required arg: input")

      true ->
        case SkillsRegistry.get_skill(skill_id) do
          nil ->
            Executor.return_error("Unknown skill: #{skill_id}", %{skill: skill_id})

          skill ->
            dispatch_skill(skill, input, vars, args, opts)
        end
    end
  end

  def run(_args, _opts), do: Executor.return_error("Invalid args (expected object)")

  defp dispatch_skill(skill, input, vars, original_args, opts) do
    runner = determine_runner(skill)

    case runner do
      :cli ->
        run_cli(skill, input, vars, original_args)

      :hal_tool ->
        run_hal_tool(skill, input, vars, original_args, opts)

      :unknown ->
        Executor.return_error("Skill is missing a runner configuration", %{
          skill: skill.name,
          hint:
            "Add frontmatter like runner: cli (command+args) or runner: hal_tool (tool+tool_args)."
        })
    end
  end

  defp determine_runner(skill) do
    runner =
      case Map.get(skill, :runner) do
        value when is_binary(value) -> value |> String.trim() |> String.downcase()
        _ -> nil
      end

    cond do
      runner in ["cli", "shell", "bash", "command"] ->
        :cli

      runner in ["hal_tool", "tool"] ->
        :hal_tool

      is_binary(Map.get(skill, :tool)) and Map.get(skill, :tool) != "" ->
        :hal_tool

      is_binary(Map.get(skill, :command)) and Map.get(skill, :command) != "" ->
        :cli

      true ->
        :unknown
    end
  end

  defp run_hal_tool(skill, input, vars, original_args, opts) do
    tool_name = Map.get(skill, :tool) || ""

    if tool_name == "" do
      Executor.return_error("Skill is missing tool configuration", %{skill: skill.name})
    else
      if tool_name == "hal_skill_run" do
        Executor.return_error("Skill cannot dispatch to hal_skill_run (recursive)", %{
          skill: skill.name
        })
      else
        template_vars = build_template_vars(input, vars, original_args)
        base_args = Map.get(skill, :tool_args) || %{}
        base_args = render_map(base_args, template_vars)

        override_args =
          case Map.get(original_args, "tool_args") || Map.get(original_args, :tool_args) do
            m when is_map(m) -> render_map(m, template_vars)
            _ -> %{}
          end

        tool_args = Map.merge(base_args, override_args)

        Executor.execute(tool_name, tool_args, opts)
      end
    end
  end

  defp run_cli(skill, input, vars, original_args) do
    command = Map.get(skill, :command)
    args = Map.get(skill, :args)

    cond do
      not is_binary(command) or String.trim(command) == "" ->
        Executor.return_error("Skill is missing CLI command configuration", %{skill: skill.name})

      is_nil(args) or not is_list(args) ->
        Executor.return_error("Skill is missing CLI args configuration", %{skill: skill.name})

      true ->
        template_vars = build_template_vars(input, vars, original_args)

        working_dir =
          Map.get(original_args, "working_dir") || Map.get(original_args, :working_dir) ||
            Map.get(original_args, "workdir") || Map.get(original_args, :workdir) ||
            Map.get(skill, :working_dir)

        working_dir =
          if is_binary(working_dir) do
            render_template(working_dir, template_vars)
          else
            File.cwd!()
          end

        timeout_ms =
          Map.get(original_args, "timeout_ms") || Map.get(original_args, :timeout_ms) ||
            Map.get(skill, :timeout_ms) || @default_timeout_ms

        timeout_ms = normalize_timeout(timeout_ms)

        rendered_args =
          args
          |> Enum.map(&to_string/1)
          |> Enum.map(&render_template(&1, template_vars))

        with {:ok, executable} <- resolve_executable(command) do
          Logger.info("Running skill #{skill.name} via CLI: #{command}")

          task =
            Task.async(fn ->
              System.cmd(executable, rendered_args,
                cd: working_dir,
                stderr_to_stdout: true
              )
            end)

          case Task.yield(task, timeout_ms) || Task.shutdown(task) do
            {:ok, {output, 0}} ->
              Executor.return_success("Skill executed", %{
                skill: skill.name,
                runner: "cli",
                command: command,
                output: String.trim(output)
              })

            {:ok, {output, exit_code}} ->
              Executor.return_error("Skill CLI exited non-zero", %{
                skill: skill.name,
                runner: "cli",
                command: command,
                exit_code: exit_code,
                output: String.trim(to_string(output))
              })

            nil ->
              Executor.return_error("Skill CLI timed out", %{
                skill: skill.name,
                runner: "cli",
                command: command,
                timeout_ms: timeout_ms
              })
          end
        else
          {:error, error} -> Executor.return_error(error, %{skill: skill.name, runner: "cli"})
        end
    end
  end

  defp resolve_executable(command) when is_binary(command) do
    command = String.trim(command)

    cond do
      command == "" ->
        {:error, "Missing command"}

      File.exists?(command) ->
        {:ok, command}

      executable = System.find_executable(command) ->
        {:ok, executable}

      true ->
        {:error, "Command not found on PATH: #{command}"}
    end
  end

  defp build_template_vars(input, vars, original_args) do
    # Normalize keys to strings.
    base =
      vars
      |> Enum.reduce(%{}, fn {k, v}, acc ->
        Map.put(acc, to_string(k), v)
      end)

    base =
      base
      |> Map.put("input", input)

    project_path = Map.get(original_args, "project_path") || Map.get(original_args, :project_path)

    if is_binary(project_path) and String.trim(project_path) != "" do
      Map.put(base, "project_path", project_path)
    else
      base
    end
  end

  defp normalize_timeout(value) when is_integer(value) and value > 0, do: value

  defp normalize_timeout(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int > 0 -> int
      _ -> @default_timeout_ms
    end
  end

  defp normalize_timeout(_), do: @default_timeout_ms

  defp render_map(map, vars) when is_map(map) do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      Map.put(acc, to_string(k), render_value(v, vars))
    end)
  end

  defp render_value(value, vars) when is_binary(value), do: render_template(value, vars)
  defp render_value(value, _vars), do: value

  defp render_template(template, vars) when is_binary(template) and is_map(vars) do
    Enum.reduce(vars, template, fn {k, v}, acc ->
      if is_nil(v) do
        acc
      else
        placeholder = "{{" <> to_string(k) <> "}}"
        String.replace(acc, placeholder, to_string(v))
      end
    end)
  end
end
