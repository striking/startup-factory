defmodule HAL.SelfImprovement.ChangeRequestWorker do
  @moduledoc """
  Generates a code change in an isolated git worktree.

  Flow:
  - Check out a detached git worktree in a temp directory
  - Delegate implementation to Codex in that worktree
  - Run `mix format` + tests
  - Store patch/test output
  - If tests pass, create an approval request to apply the patch
  """

  use Oban.Worker, queue: :scheduled, max_attempts: 1

  require Logger

  alias HAL.Autonomy.Approvals
  alias HAL.SelfImprovement.ChangeRequests

  @protected_paths [
    # Prime Directives are immutable.
    "lib/hal/core/prime_directives.ex"
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"change_request_id" => id}}) when is_binary(id) do
    case ChangeRequests.get(id) do
      nil ->
        Logger.warning("ChangeRequestWorker: change_request not found: #{id}")
        :discard

      %{status: status} when status in ["ready", "applied"] ->
        Logger.info("ChangeRequestWorker: already #{status}: #{id}")
        :ok

      req ->
        do_generate(req)
    end
  end

  def perform(_job), do: :discard

  defp do_generate(req) do
    repo_root = File.cwd!()

    with {:ok, base_sha} <- git_rev_parse(repo_root, "HEAD"),
         {:ok, worktree_path} <- prepare_worktree(repo_root, req.id, base_sha),
         {:ok, _} <-
           ChangeRequests.update(req, %{
             status: "generating",
             base_sha: base_sha,
             worktree_path: worktree_path,
             error_message: nil
           }),
         {:ok, _codex_result} <- run_codex(req, worktree_path),
         :ok <- run_mix_format(worktree_path),
         {:ok, changed_files} <- git_changed_files(worktree_path),
         {:ok, diff} <- git_diff(worktree_path),
         :ok <- ensure_safe_patch(diff),
         {:ok, {test_exit_code, test_output}} <- run_tests(req, worktree_path),
         :ok <- persist_results(req.id, changed_files, diff, test_exit_code, test_output) do
      if test_exit_code == 0 do
        maybe_request_apply_approval(req, test_exit_code)
        :ok
      else
        :ok
      end
    else
      {:error, reason} ->
        mark_failed(req, reason)
        :ok
    end
  end

  defp persist_results(id, changed_files, diff, test_exit_code, test_output) do
    status = if test_exit_code == 0, do: "ready", else: "failed"
    error_message = if test_exit_code == 0, do: nil, else: "Tests failed"

    attrs = %{
      status: status,
      changed_files: changed_files,
      diff: diff,
      test_exit_code: test_exit_code,
      test_output: truncate(test_output, 50_000),
      generated_at: DateTime.utc_now(),
      error_message: error_message
    }

    case ChangeRequests.get(id) do
      nil ->
        {:error, "ChangeRequest disappeared while persisting results"}

      req ->
        case ChangeRequests.update(req, attrs) do
          {:ok, _} ->
            :ok

          {:error, changeset} ->
            {:error, "Failed to persist ChangeRequest results: #{inspect(changeset.errors)}"}
        end
    end
  end

  defp maybe_request_apply_approval(req, _test_exit_code) do
    user_id = req.user_id

    case Approvals.request(
           user_id,
           "hal_codops_apply_change_request",
           %{"change_request_id" => req.id},
           %{
             "source" => "change_request_worker",
             "change_request_id" => req.id
           }
         ) do
      {:ok, approval} ->
        _ = ChangeRequests.update(req, %{approval_token: approval.token})
        Logger.info("ChangeRequest #{req.id} ready; approval requested: #{approval.token}")

      {:error, changeset} ->
        Logger.warning(
          "Failed to create apply approval for ChangeRequest #{req.id}: #{inspect(changeset.errors)}"
        )
    end
  end

  defp run_codex(req, worktree_path) do
    prompt = build_codex_prompt(req)

    case HAL.Agents.Codex.start_session(prompt, project_path: worktree_path) do
      {:ok, session} ->
        _ = ChangeRequests.update(req, %{codex_session_id: session.id})
        {:ok, session}

      {:error, reason} ->
        {:error, "Codex failed to start: #{inspect(reason)}"}
    end
  end

  defp build_codex_prompt(req) do
    """
    You are Codex working inside an Elixir/Phoenix repository.

    Implement the following change request in this repository:

    #{req.request}

    Constraints:
    - Do NOT modify `lib/hal/core/prime_directives.ex`.
    - Keep changes minimal and focused.
    - Prefer OTP-friendly patterns (supervised processes, minimal GenServer state).
    - Ensure the code compiles.

    When done, reply with:
    - Summary of changes
    - Any follow-ups or risks
    """
  end

  defp prepare_worktree(repo_root, change_request_id, base_sha) do
    worktree_path = Path.join(System.tmp_dir!(), "hal-change-" <> change_request_id)

    # If an old worktree exists, try to remove it cleanly first.
    _ =
      System.cmd("git", ["worktree", "remove", "--force", worktree_path],
        cd: repo_root,
        stderr_to_stdout: true
      )

    if File.exists?(worktree_path) do
      File.rm_rf!(worktree_path)
    end

    {output, status} =
      System.cmd("git", ["worktree", "add", "--detach", worktree_path, base_sha],
        cd: repo_root,
        stderr_to_stdout: true
      )

    if status == 0 do
      {:ok, worktree_path}
    else
      {:error, "Failed to create worktree: #{String.trim(output)}"}
    end
  rescue
    e -> {:error, "Failed to prepare worktree: #{Exception.message(e)}"}
  end

  defp run_mix_format(worktree_path) do
    {output, status} = System.cmd("mix", ["format"], cd: worktree_path, stderr_to_stdout: true)
    if status == 0, do: :ok, else: {:error, "mix format failed: #{String.trim(output)}"}
  end

  defp run_tests(req, worktree_path) do
    command = (req.test_command || "mix test") |> String.trim()

    {output, status} =
      System.cmd("sh", ["-lc", command], cd: worktree_path, stderr_to_stdout: true)

    {:ok, {status, output}}
  rescue
    e -> {:error, "Failed to run tests: #{Exception.message(e)}"}
  end

  defp git_rev_parse(repo_root, ref) do
    {output, status} =
      System.cmd("git", ["rev-parse", ref], cd: repo_root, stderr_to_stdout: true)

    if status == 0 do
      {:ok, String.trim(output)}
    else
      {:error, "git rev-parse #{ref} failed: #{String.trim(output)}"}
    end
  rescue
    e -> {:error, "git rev-parse failed: #{Exception.message(e)}"}
  end

  defp git_changed_files(worktree_path) do
    {output, status} =
      System.cmd("git", ["diff", "--name-only"], cd: worktree_path, stderr_to_stdout: true)

    if status == 0 do
      files =
        output
        |> String.split("\n", trim: true)
        |> Enum.reject(&(&1 == ""))

      if Enum.empty?(files) do
        {:error, "Codex produced no changes (git diff empty)"}
      else
        {:ok, files}
      end
    else
      {:error, "git diff --name-only failed: #{String.trim(output)}"}
    end
  end

  defp git_diff(worktree_path) do
    {output, status} =
      System.cmd("git", ["diff", "--patch", "--binary"],
        cd: worktree_path,
        stderr_to_stdout: true
      )

    if status == 0 do
      {:ok, output}
    else
      {:error, "git diff failed: #{String.trim(output)}"}
    end
  end

  defp ensure_safe_patch(diff) when is_binary(diff) do
    touched =
      diff
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "diff --git "))
      |> Enum.map(fn line ->
        case Regex.run(~r/^diff --git a\/(.+?) b\/(.+)$/, line) do
          [_, a_path, _b_path] -> a_path
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    protected = Enum.filter(touched, &(&1 in @protected_paths))

    if Enum.empty?(protected) do
      :ok
    else
      {:error, "Patch touches protected files: #{Enum.join(protected, ", ")}"}
    end
  end

  defp mark_failed(req, reason) do
    Logger.warning("ChangeRequestWorker failed: #{req.id} reason=#{inspect(reason)}")

    _ =
      ChangeRequests.update(req, %{
        status: "failed",
        generated_at: DateTime.utc_now(),
        error_message: truncate(to_string(reason), 5_000)
      })

    :ok
  end

  defp truncate(nil, _max), do: nil

  defp truncate(string, max) when is_binary(string) and byte_size(string) > max do
    String.slice(string, 0, max) <> "\n…(truncated)"
  end

  defp truncate(string, _max), do: string
end
