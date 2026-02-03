defmodule Hal.Tools.Handlers.Tasks do
  @moduledoc """
  Handler for HAL task/todo tool operations.

  Uses Linear API for task management via HAL.Integrations.Tasks.
  Falls back gracefully when LINEAR_API_KEY is not configured.
  """

  require Logger
  alias Hal.Tools.Executor
  alias HAL.Integrations.Tasks, as: LinearTasks

  @doc """
  List user's tasks from Linear.

  ## Arguments

    * `args` - Map containing:
      * `"status"` - Optional status filter (maps to Linear state)
      * `"limit"` - Optional result limit (default: 20)
      * `"project"` - Optional project/team filter
    * `opts` - Context options with `:user_id`
  """
  @spec list(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def list(args, opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    limit = Map.get(args, "limit", 20)
    status_filter = Map.get(args, "status")

    Logger.info("Tasks list called for user #{user_id}")

    case LinearTasks.list_tasks(limit: limit, state: linear_state(status_filter)) do
      {:ok, tasks} ->
        formatted = Enum.map(tasks, &format_for_response/1)
        count = length(formatted)

        Executor.return_success(
          "Found #{count} #{pluralize("task", count)}",
          %{
            tasks: formatted,
            filters: %{status: status_filter},
            source: "linear"
          }
        )

      {:error, "LINEAR_API_KEY not configured"} ->
        Executor.return_error(
          "Tasks not available",
          "LINEAR_API_KEY not configured. Set the environment variable to enable task management."
        )

      {:error, reason} ->
        Logger.error("Tasks list failed: #{reason}")
        Executor.return_error("Tasks list failed", reason)
    end
  rescue
    e ->
      Logger.error("Tasks list failed: #{Exception.message(e)}")
      Executor.return_error("Tasks list failed", Exception.message(e))
  end

  @doc """
  Create a new task in Linear.

  ## Arguments

    * `args` - Map containing:
      * `"title"` - Task title (required)
      * `"description"` - Optional description
      * `"priority"` - Optional priority (low, medium, high, urgent)
      * `"team_id"` - Required for Linear
    * `opts` - Context options with `:user_id`
  """
  @spec create(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def create(args, opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    title = Map.get(args, "title")
    team_id = Map.get(args, "team_id")

    cond do
      is_nil(title) ->
        Executor.return_error("Missing required argument: title")

      is_nil(team_id) ->
        Executor.return_error(
          "Missing required argument: team_id",
          "Linear requires a team_id to create tasks. Use 'list teams' to find available teams."
        )

      true ->
        Logger.info("Tasks create called for user #{user_id}")

        linear_opts =
          [
            team_id: team_id,
            title: title,
            description: Map.get(args, "description"),
            priority: linear_priority(Map.get(args, "priority"))
          ]
          |> Enum.reject(fn {_, v} -> is_nil(v) end)

        case LinearTasks.create_task(linear_opts) do
          {:ok, task} ->
            Executor.return_success(
              "Task created successfully",
              format_for_response(task)
            )

          {:error, "LINEAR_API_KEY not configured"} ->
            Executor.return_error(
              "Tasks not available",
              "LINEAR_API_KEY not configured"
            )

          {:error, reason} ->
            Logger.error("Tasks create failed: #{reason}")
            Executor.return_error("Tasks create failed", reason)
        end
    end
  rescue
    e ->
      Logger.error("Tasks create failed: #{Exception.message(e)}")
      Executor.return_error("Tasks create failed", Exception.message(e))
  end

  @doc """
  Mark a task as completed in Linear.

  ## Arguments

    * `args` - Map containing:
      * `"task_id"` - ID of task to complete
    * `opts` - Context options
  """
  @spec complete(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def complete(args, opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    task_id = Map.get(args, "task_id")

    if is_nil(task_id) do
      Executor.return_error("Missing required argument: task_id")
    else
      Logger.info("Tasks complete called for user #{user_id}")

      case LinearTasks.complete_task(task_id) do
        {:ok, task} ->
          Executor.return_success(
            "Task marked as completed",
            format_for_response(task)
          )

        {:error, "LINEAR_API_KEY not configured"} ->
          Executor.return_error(
            "Tasks not available",
            "LINEAR_API_KEY not configured"
          )

        {:error, reason} ->
          Logger.error("Tasks complete failed: #{reason}")
          Executor.return_error("Tasks complete failed", reason)
      end
    end
  rescue
    e ->
      Logger.error("Tasks complete failed: #{Exception.message(e)}")
      Executor.return_error("Tasks complete failed", Exception.message(e))
  end

  # Private helpers

  defp format_for_response(task) do
    %{
      id: task.id,
      title: task.title,
      description: task.description,
      status: task.state.name,
      priority: priority_name(task.priority),
      url: task.url,
      assignee: if(task.assignee, do: task.assignee.name, else: nil),
      created_at: task.created_at,
      updated_at: task.updated_at
    }
  end

  # Map status filter to Linear state name
  defp linear_state(nil), do: nil
  defp linear_state("pending"), do: "Todo"
  defp linear_state("in_progress"), do: "In Progress"
  defp linear_state("completed"), do: "Done"
  defp linear_state("all"), do: nil
  defp linear_state(other), do: other

  # Map priority to Linear priority number (0=none, 1=urgent, 2=high, 3=medium, 4=low)
  defp linear_priority(nil), do: nil
  defp linear_priority("urgent"), do: 1
  defp linear_priority("high"), do: 2
  defp linear_priority("medium"), do: 3
  defp linear_priority("low"), do: 4
  defp linear_priority(_), do: nil

  # Map Linear priority number to name
  defp priority_name(0), do: "none"
  defp priority_name(1), do: "urgent"
  defp priority_name(2), do: "high"
  defp priority_name(3), do: "medium"
  defp priority_name(4), do: "low"
  defp priority_name(_), do: "unknown"

  defp pluralize(word, 1), do: word
  defp pluralize(word, _), do: "#{word}s"
end
