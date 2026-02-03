defmodule Hal.Tasks.TaskExecutorWorker do
  @moduledoc """
  Oban worker that executes autonomous task steps.

  Processes one step at a time, persisting progress between steps.
  Supports pause/resume and graceful failure handling.
  """

  use Oban.Worker,
    queue: :scheduled,
    max_attempts: 3

  require Logger

  alias Hal.Tasks.AutoTask
  alias Hal.Notifications
  alias HAL.Autonomy.Brain

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"check_pending" => true}}) do
    # Cron job to pick up any pending tasks
    Hal.Tasks.process_pending()
    :ok
  end

  def perform(%Oban.Job{args: %{"task_id" => task_id}}) do
    case AutoTask.get_with_user(task_id) do
      nil ->
        {:error, :task_not_found}

      %{status: "paused"} ->
        Logger.info("Task #{task_id} is paused, skipping")
        :ok

      %{status: "completed"} ->
        Logger.info("Task #{task_id} already completed")
        :ok

      %{status: "failed"} ->
        Logger.info("Task #{task_id} has failed, not retrying")
        :ok

      task ->
        execute_next_step(task)
    end
  end

  @doc """
  Schedules a task for execution.
  """
  @spec schedule(binary(), keyword()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def schedule(task_id, opts \\ []) do
    delay = Keyword.get(opts, :delay, 0)

    %{task_id: task_id}
    |> __MODULE__.new(schedule_in: delay)
    |> Oban.insert()
  end

  # Private Functions

  defp execute_next_step(task) do
    # Get current step
    current_step = AutoTask.get_current_step(task)

    if is_nil(current_step) do
      Logger.info("Task #{task.id} has no more steps")
      complete_task(task)
    else
      Logger.info(
        "Executing step #{task.current_step + 1}/#{length(task.steps)}: #{current_step["name"]}"
      )

      # Update step status to running
      AutoTask.start(task.id)

      # Build prompt with context
      prompt = build_step_prompt(task, current_step)

      # Execute via the unified autonomy brain so tool calls have the required
      # user/session/channel context (and routing is forced to Claude).
      brain_opts = [
        user_id: task.user_id,
        hal_session_id: task.id,
        channel_type: "terminal",
        channel_id: "task:#{task.id}",
        timeout: 180_000
      ]

      case Brain.prompt(prompt, brain_opts) do
        {:ok, result} ->
          handle_step_success(task, result)

        {:error, {:budget_exceeded, _remaining}} ->
          Logger.info("Budget exceeded; pausing task #{task.id}")
          _ = AutoTask.pause(task.id)
          :ok

        {:error, reason} ->
          handle_step_failure(task, reason)
      end
    end
  end

  defp build_step_prompt(task, step) do
    # Gather results from previous steps
    previous_results = get_previous_results(task)

    """
    You are HAL, executing step #{task.current_step + 1} of #{length(task.steps)} in an autonomous task.

    ## Original Request
    #{task.original_request}

    ## Current Step: #{step["name"]}
    #{step["prompt"]}

    #{if previous_results != "", do: "## Previous Step Results\n#{previous_results}\n", else: ""}

    #{if task.context != %{}, do: "## Additional Context\n#{inspect(task.context)}\n", else: ""}

    Execute this step thoroughly. Provide a complete result that can be used by subsequent steps.
    """
  end

  defp get_previous_results(task) do
    task.steps
    |> Enum.take(task.current_step)
    |> Enum.filter(fn s -> s["status"] == "completed" end)
    |> Enum.map(fn s -> "**#{s["name"]}:**\n#{s["result"]}" end)
    |> Enum.join("\n\n")
  end

  defp handle_step_success(task, result) do
    Logger.info("Step #{task.current_step + 1} completed for task #{task.id}")

    case AutoTask.complete_step(task.id, result) do
      {:ok, updated_task} ->
        if updated_task.status == "completed" do
          complete_task(updated_task)
        else
          # Schedule next step with small delay to avoid hammering Claude
          schedule(task.id, delay: 5)
        end

        :ok

      {:error, reason} ->
        Logger.error("Failed to update step: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_step_failure(task, reason) do
    Logger.error("Step #{task.current_step + 1} failed: #{inspect(reason)}")

    case AutoTask.fail_step(task.id, inspect(reason)) do
      {:ok, updated_task} ->
        if updated_task.status == "failed" do
          notify_failure(updated_task)
        else
          # Retry after delay
          schedule(task.id, delay: 30)
        end

        :ok

      {:error, err} ->
        {:error, err}
    end
  end

  defp complete_task(task) do
    Logger.info("Task #{task.id} completed: #{task.title}")
    notify_completion(task)
    :ok
  end

  defp notify_completion(task) do
    message = """
    ✅ *Task Completed: #{task.title}*

    Your autonomous task has finished successfully.

    #{if task.final_result, do: "**Result:**\n#{truncate(task.final_result, 500)}", else: ""}
    """

    send_notification(task.user, message)
  end

  defp notify_failure(task) do
    message = """
    ❌ *Task Failed: #{task.title}*

    Your autonomous task encountered an error after #{task.retry_count} retries.

    **Error:** #{task.error_message}

    You can retry this task or check the logs for more details.
    """

    send_notification(task.user, message)
  end

  defp send_notification(user, message) do
    case Notifications.send(user, message, fallback: true) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to send task notification: #{inspect(reason)}")
        :ok
    end
  end

  defp truncate(text, max) when byte_size(text) <= max, do: text
  defp truncate(text, max), do: String.slice(text, 0, max) <> "..."
end
