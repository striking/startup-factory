defmodule HAL.Automation.Scheduler do
  @moduledoc """
  API for scheduling tasks in HAL.

  Provides functions for scheduling one-time, recurring, and natural language
  scheduled tasks. All scheduled tasks are persisted via Oban and survive
  application restarts.

  ## Scheduling Types

    * `schedule_once/3` - Schedule a one-time task at a specific datetime
    * `schedule_in/3` - Schedule a one-time task after a duration
    * `schedule_recurring/3` - Schedule a recurring task with a cron expression
    * `schedule_natural/3` - Parse natural language and schedule appropriately

  ## Examples

      # One-time task
      Scheduler.schedule_once(session_id, "Check my email", ~U[2026-01-28 09:00:00Z])

      # Recurring task
      Scheduler.schedule_recurring(session_id, "Daily standup summary", "0 9 * * *")

      # Natural language
      Scheduler.schedule_natural(session_id, "Remind me to check PRs", "every morning at 9am")
      Scheduler.schedule_natural(session_id, "Check stocks", "in 2 hours")

  """

  require Logger

  alias HAL.Automation.Workers.ScheduledTask
  alias HAL.Automation.Workers.ProactiveTask
  alias HAL.Automation.NaturalLanguageParser

  @type schedule_opts :: [
          respond_via: map(),
          metadata: map(),
          priority: integer(),
          tags: [String.t()]
        ]

  @doc """
  Schedules a one-time task at a specific datetime.

  ## Parameters

    * `session_id` - The session context for the task
    * `prompt` - The prompt to execute
    * `scheduled_at` - When to run the task (DateTime in UTC)
    * `opts` - Additional options (respond_via, metadata, priority, tags)

  ## Returns

    * `{:ok, %Oban.Job{}}` - Successfully scheduled
    * `{:error, reason}` - Failed to schedule

  ## Examples

      iex> Scheduler.schedule_once(
      ...>   "session-uuid",
      ...>   "Check my calendar",
      ...>   ~U[2026-01-28 09:00:00Z]
      ...> )
      {:ok, %Oban.Job{}}

  """
  @spec schedule_once(String.t(), String.t(), DateTime.t(), schedule_opts()) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  def schedule_once(session_id, prompt, scheduled_at, opts \\ []) do
    args = build_task_args(session_id, prompt, opts)

    args
    |> ScheduledTask.new(scheduled_at: scheduled_at, tags: opts[:tags] || ["scheduled"])
    |> Oban.insert()
  end

  @doc """
  Schedules a one-time task after a duration.

  ## Parameters

    * `session_id` - The session context for the task
    * `prompt` - The prompt to execute
    * `duration` - Duration tuple like `{2, :hours}` or seconds as integer
    * `opts` - Additional options

  ## Duration Formats

    * `{amount, :seconds}` - e.g., `{30, :seconds}`
    * `{amount, :minutes}` - e.g., `{15, :minutes}`
    * `{amount, :hours}` - e.g., `{2, :hours}`
    * `{amount, :days}` - e.g., `{1, :days}`
    * Integer - interpreted as seconds

  ## Examples

      iex> Scheduler.schedule_in("session-uuid", "Remind me", {2, :hours})
      {:ok, %Oban.Job{}}

      iex> Scheduler.schedule_in("session-uuid", "Quick reminder", {30, :minutes})
      {:ok, %Oban.Job{}}

  """
  @spec schedule_in(String.t(), String.t(), {integer(), atom()} | integer(), schedule_opts()) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  def schedule_in(session_id, prompt, duration, opts \\ [])

  def schedule_in(session_id, prompt, seconds, opts) when is_integer(seconds) do
    scheduled_at = DateTime.utc_now() |> DateTime.add(seconds, :second)
    schedule_once(session_id, prompt, scheduled_at, opts)
  end

  def schedule_in(session_id, prompt, {amount, unit}, opts) do
    seconds = duration_to_seconds(amount, unit)
    schedule_in(session_id, prompt, seconds, opts)
  end

  @doc """
  Schedules a recurring task using a cron expression.

  Recurring tasks are implemented by scheduling the next occurrence and
  having the worker reschedule itself after execution.

  ## Parameters

    * `session_id` - The session context for the task
    * `prompt` - The prompt to execute
    * `cron_expression` - Standard cron expression (5 fields: min hour day month weekday)
    * `opts` - Additional options

  ## Cron Expression Format

      ┌───────────── minute (0 - 59)
      │ ┌───────────── hour (0 - 23)
      │ │ ┌───────────── day of month (1 - 31)
      │ │ │ ┌───────────── month (1 - 12)
      │ │ │ │ ┌───────────── day of week (0 - 6) (Sunday = 0)
      │ │ │ │ │
      * * * * *

  ## Examples

      # Every day at 9am
      Scheduler.schedule_recurring(session_id, "Morning briefing", "0 9 * * *")

      # Every Monday at 10am
      Scheduler.schedule_recurring(session_id, "Weekly summary", "0 10 * * 1")

      # Every 30 minutes
      Scheduler.schedule_recurring(session_id, "Check for updates", "*/30 * * * *")

  """
  @spec schedule_recurring(String.t(), String.t(), String.t(), schedule_opts()) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  def schedule_recurring(session_id, prompt, cron_expression, opts \\ []) do
    # Validate the cron expression
    case NaturalLanguageParser.validate_cron(cron_expression) do
      {:ok, _} ->
        # Calculate the next occurrence
        case NaturalLanguageParser.next_occurrence(cron_expression) do
          {:ok, next_run} ->
            args = build_task_args(session_id, prompt, opts)
            args = Map.put(args, "cron_expression", cron_expression)

            args
            |> ScheduledTask.new(
              scheduled_at: next_run,
              tags: opts[:tags] || ["scheduled", "recurring"]
            )
            |> Oban.insert()

          {:error, reason} ->
            {:error, {:invalid_cron, reason}}
        end

      {:error, reason} ->
        {:error, {:invalid_cron, reason}}
    end
  end

  @doc """
  Schedules a task using natural language time expressions.

  Parses natural language like "every morning at 9am", "in 2 hours",
  "tomorrow at 3pm", etc. and schedules the appropriate task type.

  ## Parameters

    * `session_id` - The session context for the task
    * `prompt` - The prompt to execute
    * `natural_expression` - Natural language time expression
    * `opts` - Additional options

  ## Supported Expressions

  Recurring:
    * "every morning at 9am" -> daily at 9am
    * "every Monday" -> weekly on Mondays at midnight
    * "every weekday at 8am" -> Mon-Fri at 8am
    * "every hour" -> hourly
    * "every 30 minutes" -> every 30 minutes

  One-time:
    * "in 2 hours" -> 2 hours from now
    * "in 30 minutes" -> 30 minutes from now
    * "tomorrow at 3pm" -> next day at 3pm
    * "next Monday" -> upcoming Monday

  ## Examples

      iex> Scheduler.schedule_natural(
      ...>   "session-uuid",
      ...>   "Check GitHub",
      ...>   "every morning at 9am"
      ...> )
      {:ok, %Oban.Job{}}

  """
  @spec schedule_natural(String.t(), String.t(), String.t(), schedule_opts()) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  def schedule_natural(session_id, prompt, natural_expression, opts \\ []) do
    case NaturalLanguageParser.parse(natural_expression) do
      {:recurring, cron_expression} ->
        schedule_recurring(session_id, prompt, cron_expression, opts)

      {:once, datetime} ->
        schedule_once(session_id, prompt, datetime, opts)

      {:in, seconds} ->
        schedule_in(session_id, prompt, seconds, opts)

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  @doc """
  Schedules a proactive task (agent-initiated).

  ## Parameters

    * `task_type` - Type of proactive task (monitor, suggestion, maintenance, reminder)
    * `config` - Task-specific configuration
    * `opts` - Scheduling options including:
      * `:session_id` - Optional session context
      * `:respond_via` - Channel to send notifications
      * `:scheduled_at` - When to run (default: now)
      * `:cron` - Cron expression for recurring

  ## Examples

      # One-time reminder
      Scheduler.schedule_proactive("reminder", %{message: "Time for standup!"}, [
        respond_via: %{"channel_type" => "slack", "channel_id" => "C123"},
        scheduled_at: ~U[2026-01-28 09:00:00Z]
      ])

      # Recurring monitor
      Scheduler.schedule_proactive("monitor", %{
        prompt: "Check if the deployment completed",
        trigger_words: ["completed", "failed"]
      }, [
        session_id: "session-uuid",
        cron: "*/5 * * * *"
      ])

  """
  @spec schedule_proactive(String.t(), map(), keyword()) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  def schedule_proactive(task_type, config, opts \\ []) do
    args = %{
      "task_type" => task_type,
      "config" => config
    }

    args = if opts[:session_id], do: Map.put(args, "session_id", opts[:session_id]), else: args
    args = if opts[:respond_via], do: Map.put(args, "respond_via", opts[:respond_via]), else: args

    job_opts = []

    job_opts =
      if opts[:scheduled_at],
        do: Keyword.put(job_opts, :scheduled_at, opts[:scheduled_at]),
        else: job_opts

    job_opts = if opts[:tags], do: Keyword.put(job_opts, :tags, opts[:tags]), else: job_opts

    args
    |> ProactiveTask.new(job_opts)
    |> Oban.insert()
  end

  @doc """
  Lists all scheduled jobs for a session.

  ## Parameters

    * `session_id` - The session to query

  ## Returns

    * List of scheduled jobs with their details

  """
  @spec list_scheduled(String.t()) :: [map()]
  def list_scheduled(session_id) do
    import Ecto.Query

    query =
      from j in Oban.Job,
        where: j.state in ["available", "scheduled"],
        where: fragment("?->>'session_id' = ?", j.args, ^session_id),
        order_by: [asc: j.scheduled_at],
        select: %{
          id: j.id,
          queue: j.queue,
          state: j.state,
          scheduled_at: j.scheduled_at,
          args: j.args,
          tags: j.tags
        }

    Hal.Repo.all(query)
  end

  @doc """
  Cancels a scheduled job.

  ## Parameters

    * `job_id` - The Oban job ID to cancel

  ## Returns

    * `:ok` - Job cancelled
    * `{:error, reason}` - Failed to cancel

  """
  @spec cancel(integer()) :: :ok | {:error, term()}
  def cancel(job_id) do
    case Oban.cancel_job(job_id) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Cancels all scheduled jobs for a session.

  ## Parameters

    * `session_id` - The session whose jobs should be cancelled

  ## Returns

    * `{:ok, count}` - Number of jobs cancelled

  """
  @spec cancel_all(String.t()) :: {:ok, integer()}
  def cancel_all(session_id) do
    jobs = list_scheduled(session_id)

    cancelled =
      Enum.reduce(jobs, 0, fn job, acc ->
        case cancel(job.id) do
          :ok -> acc + 1
          _ -> acc
        end
      end)

    {:ok, cancelled}
  end

  # Private functions

  defp build_task_args(session_id, prompt, opts) do
    args = %{
      "session_id" => session_id,
      "prompt" => prompt
    }

    args = if opts[:respond_via], do: Map.put(args, "respond_via", opts[:respond_via]), else: args
    args = if opts[:metadata], do: Map.put(args, "metadata", opts[:metadata]), else: args

    args
  end

  defp duration_to_seconds(amount, :seconds), do: amount
  defp duration_to_seconds(amount, :minutes), do: amount * 60
  defp duration_to_seconds(amount, :hours), do: amount * 60 * 60
  defp duration_to_seconds(amount, :days), do: amount * 60 * 60 * 24
end
