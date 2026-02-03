defmodule Hal.Tasks do
  @moduledoc """
  Main interface for HAL's multi-step autonomous task system.

  Enables HAL to execute complex tasks that span multiple steps and time.
  "Research X and email me a summary" - HAL works while you sleep.

  ## Usage

      # Create a task from natural language
      {:ok, task} = Tasks.create(user_id, "Research Elixir frameworks and email me a summary")

      # Check task status
      Tasks.get_status(task_id)

      # List user's tasks
      Tasks.list(user_id)

      # Pause/resume
      Tasks.pause(task_id)
      Tasks.resume(task_id)

  ## How It Works

  1. User makes a request ("Research X and email me a summary")
  2. Claude decomposes it into discrete steps
  3. Each step is executed in sequence
  4. Progress persists through restarts
  5. User is notified on completion

  ## Example Task Flow

      Research → Summarize → Email
      Check calendar → Find conflicts → Notify
      Scan emails → Extract action items → Create tasks
  """

  require Logger

  alias Hal.Tasks.AutoTask
  alias Hal.Tasks.TaskExecutorWorker

  @doc """
  Creates a new autonomous task from a natural language request.

  Claude will analyze the request and break it into executable steps.

  ## Options

    * `:priority` - Task priority (:low, :normal, :high, :urgent)
    * `:scheduled_at` - When to start (nil = immediately)
    * `:context` - Additional context map passed to each step

  ## Examples

      Tasks.create(user_id, "Research AI trends and summarize")
      Tasks.create(user_id, "Check my calendar for conflicts tomorrow", priority: :high)
      Tasks.create(user_id, "Draft replies to urgent emails", scheduled_at: ~U[2026-01-31 09:00:00Z])
  """
  @spec create(binary(), String.t(), keyword()) :: {:ok, AutoTask.t()} | {:error, term()}
  def create(user_id, request, opts \\ []) do
    case AutoTask.create_from_request(user_id, request, opts) do
      {:ok, task} ->
        # Schedule execution
        scheduled_at = Keyword.get(opts, :scheduled_at)

        if scheduled_at do
          delay = max(0, DateTime.diff(scheduled_at, DateTime.utc_now(), :second))
          TaskExecutorWorker.schedule(task.id, delay: delay)
        else
          TaskExecutorWorker.schedule(task.id)
        end

        Logger.info("Created autonomous task: #{task.id} - #{task.title}")
        {:ok, task}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a task with explicit steps (no Claude decomposition).

  Useful when you already know the steps needed.

  ## Example

      Tasks.create_with_steps(user_id, %{
        title: "Daily Email Review",
        original_request: "Review my emails",
        steps: [
          %{name: "fetch", prompt: "Get all unread emails from today"},
          %{name: "prioritize", prompt: "Identify urgent emails requiring response"},
          %{name: "summarize", prompt: "Create a summary of important emails"}
        ]
      })
  """
  @spec create_with_steps(binary(), map()) :: {:ok, AutoTask.t()} | {:error, term()}
  def create_with_steps(user_id, attrs) do
    case AutoTask.create(user_id, attrs) do
      {:ok, task} ->
        TaskExecutorWorker.schedule(task.id)
        {:ok, task}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a task by ID.
  """
  @spec get(binary()) :: AutoTask.t() | nil
  def get(task_id), do: AutoTask.get(task_id)

  @doc """
  Gets the status of a task.
  """
  @spec get_status(binary()) :: map() | nil
  def get_status(task_id) do
    case AutoTask.get(task_id) do
      nil ->
        nil

      task ->
        current_step = AutoTask.get_current_step(task)

        %{
          id: task.id,
          title: task.title,
          status: task.status,
          progress: AutoTask.progress(task),
          current_step: task.current_step + 1,
          total_steps: length(task.steps),
          current_step_name: current_step && current_step["name"],
          started_at: task.started_at,
          completed_at: task.completed_at,
          error: task.error_message,
          steps:
            Enum.map(task.steps, fn s ->
              %{name: s["name"], status: s["status"]}
            end)
        }
    end
  end

  @doc """
  Lists tasks for a user.

  ## Options

    * `:status` - Filter by status (pending, running, paused, completed, failed)
    * `:limit` - Maximum number of tasks to return (default: 50)
  """
  @spec list(binary(), keyword()) :: [AutoTask.t()]
  def list(user_id, opts \\ []) do
    AutoTask.list_for_user(user_id, opts)
  end

  @doc """
  Lists active (pending or running) tasks for a user.
  """
  @spec list_active(binary()) :: [AutoTask.t()]
  def list_active(user_id) do
    pending = AutoTask.list_for_user(user_id, status: "pending")
    running = AutoTask.list_for_user(user_id, status: "running")
    paused = AutoTask.list_for_user(user_id, status: "paused")

    (pending ++ running ++ paused)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  @doc """
  Pauses a running task.
  """
  @spec pause(binary()) :: {:ok, AutoTask.t()} | {:error, term()}
  def pause(task_id) do
    AutoTask.pause(task_id)
  end

  @doc """
  Resumes a paused task.
  """
  @spec resume(binary()) :: {:ok, AutoTask.t()} | {:error, term()}
  def resume(task_id) do
    case AutoTask.resume(task_id) do
      {:ok, task} ->
        TaskExecutorWorker.schedule(task.id)
        {:ok, task}

      error ->
        error
    end
  end

  @doc """
  Cancels a task (marks as failed).
  """
  @spec cancel(binary()) :: {:ok, AutoTask.t()} | {:error, term()}
  def cancel(task_id) do
    case AutoTask.get(task_id) do
      nil ->
        {:error, :not_found}

      task ->
        task
        |> AutoTask.changeset(%{
          status: "failed",
          error_message: "Cancelled by user",
          completed_at: DateTime.utc_now()
        })
        |> Hal.Repo.update()
    end
  end

  @doc """
  Retries a failed task from the beginning.
  """
  @spec retry(binary()) :: {:ok, AutoTask.t()} | {:error, term()}
  def retry(task_id) do
    case AutoTask.get(task_id) do
      nil ->
        {:error, :not_found}

      %{status: "failed"} = task ->
        # Reset all steps to pending
        steps =
          Enum.map(task.steps, fn s ->
            Map.merge(s, %{
              "status" => "pending",
              "result" => nil,
              "error" => nil,
              "started_at" => nil,
              "completed_at" => nil
            })
          end)

        case task
             |> AutoTask.changeset(%{
               status: "pending",
               current_step: 0,
               steps: steps,
               error_message: nil,
               retry_count: 0,
               started_at: nil,
               completed_at: nil
             })
             |> Hal.Repo.update() do
          {:ok, updated} ->
            TaskExecutorWorker.schedule(updated.id)
            {:ok, updated}

          error ->
            error
        end

      _ ->
        {:error, :not_failed}
    end
  end

  @doc """
  Processes pending tasks (called by scheduler).

  Picks up any pending tasks that should be running.
  """
  @spec process_pending() :: :ok
  def process_pending do
    tasks = AutoTask.get_pending()

    Enum.each(tasks, fn task ->
      Logger.info("Scheduling pending task: #{task.id}")
      TaskExecutorWorker.schedule(task.id)
    end)

    :ok
  end
end
