defmodule Hal.Tools.Handlers.Codops do
  @moduledoc """
  Codops tools for safe self-improvement.

  Provides an approval-gated pipeline for code changes:
  - Create a ChangeRequest (runs Codex in a temp git worktree, runs tests)
  - Apply the resulting patch to the main repo (approval required)
  """

  require Logger

  alias HAL.SelfImprovement.ChangeRequests
  alias Hal.Tools.Executor

  @protected_paths [
    "lib/hal/core/prime_directives.ex"
  ]

  @doc """
  Create a ChangeRequest and enqueue generation in a temp worktree.
  """
  def create_change_request(args, opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    task = Map.get(args, "task") || Map.get(args, :task)
    title = Map.get(args, "title") || Map.get(args, :title) || derive_title(task)
    test_command = Map.get(args, "test_command") || Map.get(args, :test_command)

    cond do
      not is_binary(task) or String.trim(task) == "" ->
        Executor.return_error("Missing required arg: task")

      not is_binary(title) or String.trim(title) == "" ->
        Executor.return_error("Missing required arg: title")

      true ->
        attrs =
          %{
            title: String.trim(title),
            request: String.trim(task),
            status: "pending"
          }
          |> maybe_put(:test_command, test_command)

        with {:ok, req} <- ChangeRequests.create(user_id, attrs),
             {:ok, _job} <- ChangeRequests.enqueue_generation(req) do
          Executor.return_success("Created change request", %{
            change_request_id: req.id,
            status: req.status,
            title: req.title
          })
        else
          {:error, %Ecto.Changeset{} = changeset} ->
            Executor.return_error("Failed to create change request", %{
              errors: changeset_errors(changeset)
            })

          {:error, reason} ->
            Executor.return_error("Failed to enqueue change request generation", %{
              reason: inspect(reason)
            })
        end
    end
  end

  @doc """
  Apply a ready ChangeRequest patch to the main repo.
  """
  def apply_change_request(args, _opts) do
    id = Map.get(args, "change_request_id") || Map.get(args, :change_request_id)
    force? = Map.get(args, "force") || Map.get(args, :force) || false

    with true <- (is_binary(id) and id != "") || {:error, :missing_id},
         %{} = req <- ChangeRequests.get(id) || {:error, :not_found},
         :ok <- ensure_ready(req, force?),
         :ok <- ensure_safe_patch(req.diff),
         :ok <- ensure_clean_working_tree(),
         :ok <- git_apply_patch(req.diff),
         {:ok, _} <-
           ChangeRequests.update(req, %{status: "applied", applied_at: DateTime.utc_now()}) do
      cleanup_worktree(req.worktree_path)

      Executor.return_success("Applied change request", %{
        change_request_id: req.id,
        status: "applied"
      })
    else
      {:error, :missing_id} ->
        Executor.return_error("Missing required arg: change_request_id")

      {:error, :not_found} ->
        Executor.return_error("Change request not found", %{change_request_id: id})

      {:error, reason} when is_binary(reason) ->
        Executor.return_error(reason)

      {:error, reason} ->
        Executor.return_error("Failed to apply change request", %{reason: inspect(reason)})

      false ->
        Executor.return_error("Missing required arg: change_request_id")
    end
  end

  defp ensure_ready(%{status: "ready", test_exit_code: 0, diff: diff}, _force?)
       when is_binary(diff) and diff != "" do
    :ok
  end

  defp ensure_ready(%{status: "ready", diff: diff}, true) when is_binary(diff) and diff != "" do
    :ok
  end

  defp ensure_ready(%{status: "failed", test_exit_code: code} = req, true)
       when is_integer(code) and is_binary(req.diff) and req.diff != "" do
    :ok
  end

  defp ensure_ready(%{status: status} = req, _force?) do
    {:error,
     "Change request is not ready to apply (status=#{status}, test_exit_code=#{inspect(req.test_exit_code)})"}
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

  defp ensure_safe_patch(_), do: {:error, "Change request patch is missing"}

  defp ensure_clean_working_tree do
    repo_root = File.cwd!()

    {output, status} =
      System.cmd("git", ["status", "--porcelain"], cd: repo_root, stderr_to_stdout: true)

    if status == 0 and String.trim(output) == "" do
      :ok
    else
      {:error, "Working tree is not clean. Commit/stash changes before applying."}
    end
  end

  defp git_apply_patch(diff) when is_binary(diff) do
    repo_root = File.cwd!()

    {output, status} =
      System.cmd("git", ["apply", "--whitespace=fix", "-"],
        cd: repo_root,
        stderr_to_stdout: true,
        input: diff
      )

    if status == 0 do
      :ok
    else
      {:error, "git apply failed: #{String.trim(output)}"}
    end
  end

  defp cleanup_worktree(nil), do: :ok
  defp cleanup_worktree(""), do: :ok

  defp cleanup_worktree(worktree_path) when is_binary(worktree_path) do
    repo_root = File.cwd!()

    _ =
      System.cmd("git", ["worktree", "remove", "--force", worktree_path],
        cd: repo_root,
        stderr_to_stdout: true
      )

    if File.exists?(worktree_path) do
      _ = File.rm_rf(worktree_path)
    end

    :ok
  rescue
    e ->
      Logger.warning("Failed to cleanup worktree #{worktree_path}: #{Exception.message(e)}")
      :ok
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp derive_title(task) when is_binary(task) do
    task
    |> String.trim()
    |> String.split("\n", parts: 2)
    |> List.first()
    |> case do
      "" -> "Change request"
      title -> String.slice(title, 0, 80)
    end
  end

  defp derive_title(_), do: "Change request"

  defp changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        atom_key =
          try do
            String.to_existing_atom(key)
          rescue
            ArgumentError -> nil
          end

        opts
        |> Keyword.get(atom_key, key)
        |> to_string()
      end)
    end)
  end
end
