defmodule Hal.Tools.Handlers.Delegation do
  @moduledoc """
  Handler for multi-agent delegation tools.

  Allows Claude (the brain) to delegate tasks to specialist agents:
  - Codex: Complex coding tasks
  - Jules: Async background tasks
  - Gemini: Fast summarization/completion

  ## Architecture

  Claude decides → calls delegation tool → HAL.Agents.* executes

  The brain makes all decisions. HAL just executes.
  """

  require Logger
  alias HAL.AgentState
  alias Hal.Tools.Executor

  @doc """
  Delegate a coding task to OpenAI Codex.
  """
  def delegate_to_codex(args, _opts) do
    task = Map.get(args, "task")
    project_path = Map.get(args, "project_path", File.cwd!())

    Logger.info("Delegating to Codex: #{String.slice(task, 0, 50)}...")

    # Start the session quickly, then run the task asynchronously to avoid
    # blocking the calling tool (MCP tool calls have tight timeouts).
    case HAL.Agents.Codex.start_session(task, project_path: project_path, run_initial_task: false) do
      {:ok, session} ->
        tracking_task = codex_tracking_task(task, session.id)

        AgentState.task_started(tracking_task, nil,
          context: %{agent: "codex", session_id: session.id}
        )

        Task.start(fn ->
          case HAL.Agents.Codex.run(session.id, task) do
            {:ok, result} ->
              AgentState.task_completed(tracking_task, "Codex completed",
                metadata: %{
                  agent: "codex",
                  session_id: session.id,
                  result_preview: truncate(result, 200)
                }
              )

            {:error, reason} ->
              AgentState.task_failed(tracking_task, inspect(reason),
                metadata: %{
                  agent: "codex",
                  session_id: session.id
                }
              )
          end
        end)

        Executor.return_success(
          "Started Codex session for coding task",
          %{
            session_id: session.id,
            status: :running,
            task: task,
            agent: "codex"
          }
        )

      {:error, :codex_not_installed} ->
        Executor.return_error(
          "Codex CLI not installed. Install with: npm install -g @openai/codex",
          %{agent: "codex"}
        )

      {:error, reason} ->
        Executor.return_error("Failed to start Codex session: #{inspect(reason)}")
    end
  end

  @doc """
  Delegate a background task to Jules.
  """
  def delegate_to_jules(args, _opts) do
    task = Map.get(args, "task")
    repo = Map.get(args, "repo")
    priority = Map.get(args, "priority", "normal") |> String.to_atom()

    Logger.info("Delegating to Jules: #{String.slice(task, 0, 50)}...")

    opts = []
    opts = if repo, do: Keyword.put(opts, :repo, repo), else: opts
    opts = Keyword.put(opts, :priority, priority)

    case HAL.Agents.Jules.start_task(task, opts) do
      {:ok, task_info} ->
        Executor.return_success(
          "Started Jules background task",
          %{
            task_id: task_info.id,
            status: task_info.status,
            description: task,
            agent: "jules"
          }
        )

      {:error, :api_key_not_configured} ->
        Executor.return_error(
          "Jules API key not configured. Set OPENAI_API_KEY environment variable.",
          %{agent: "jules"}
        )

      {:error, reason} ->
        Executor.return_error("Failed to start Jules task: #{inspect(reason)}")
    end
  end

  @doc """
  Delegate a summarization or completion task to Gemini.
  """
  def delegate_to_gemini(args, _opts) do
    text = Map.get(args, "text")
    operation = Map.get(args, "operation", "delegate")

    Logger.info("Delegating to Gemini: #{operation}")

    result =
      case operation do
        "summarize" ->
          max_length = Map.get(args, "max_length", 200)
          style = Map.get(args, "style", "paragraph") |> String.to_atom()
          HAL.Agents.Gemini.summarize(text, max_length: max_length, style: style)

        "complete" ->
          tone = Map.get(args, "tone", "natural")
          HAL.Agents.Gemini.complete(text, tone: tone)

        "delegate" ->
          HAL.Agents.Gemini.delegate(text)

        _ ->
          {:error, :unknown_operation}
      end

    case result do
      {:ok, task} ->
        Executor.return_success(
          "Gemini #{operation} completed",
          %{
            task_id: task.id,
            status: task.status,
            result: task.result,
            agent: "gemini"
          }
        )

      {:error, reason} when is_binary(reason) ->
        Executor.return_error(reason, %{agent: "gemini"})

      {:error, reason} ->
        Executor.return_error("Gemini task failed: #{inspect(reason)}")
    end
  end

  @doc """
  Check the status of a delegated task.
  """
  def check_status(args, _opts) do
    task_id = Map.get(args, "task_id")
    agent = Map.get(args, "agent")

    result =
      case agent do
        "codex" ->
          HAL.Agents.Codex.check_status(task_id)

        "jules" ->
          HAL.Agents.Jules.check_status(task_id)

        "gemini" ->
          HAL.Agents.Gemini.check_status(task_id)

        _ ->
          {:error, :unknown_agent}
      end

    case result do
      {:ok, task_info} ->
        Executor.return_success(
          "Task status: #{task_info.status}",
          %{
            task_id: task_id,
            status: task_info.status,
            agent: agent,
            result: Map.get(task_info, :result),
            error: Map.get(task_info, :error)
          }
        )

      {:error, :not_found} ->
        Executor.return_error("Task not found: #{task_id}", %{agent: agent})

      {:error, :unknown_agent} ->
        Executor.return_error("Unknown agent: #{agent}")

      {:error, reason} ->
        Executor.return_error("Failed to check status: #{inspect(reason)}")
    end
  end

  defp codex_tracking_task(task, session_id) do
    "codex:#{session_id} " <> truncate(task, 80)
  end

  defp truncate(string, length) when is_binary(string) and byte_size(string) > length do
    String.slice(string, 0, length) <> "…"
  end

  defp truncate(string, _length), do: string
end
