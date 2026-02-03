defmodule Hal.Habits do
  @moduledoc """
  Habit tracking system for building positive routines.

  HAL helps you build and maintain habits by:
  - Tracking daily/weekly/custom frequency habits
  - Sending smart reminders at your preferred times
  - Calculating streaks to keep you motivated
  - Providing insights on your habit performance

  ## Usage

      # Create a habit
      {:ok, habit} = Habits.create(user_id, %{
        name: "Morning meditation",
        frequency: "daily",
        reminder_time: ~T[07:00:00],
        category: "mindfulness"
      })

      # Complete a habit
      {:ok, completion} = Habits.complete(habit.id)

      # Check today's progress
      progress = Habits.today_progress(user_id)

  ## Frequencies

  - `daily` - Track every day
  - `weekly` - Track once per week (defaults to Monday)
  - `custom` - Specify target_days as day numbers (1=Monday, 7=Sunday)
  """

  require Logger

  alias Hal.Habits.{Habit, Completion}

  @doc """
  Creates a new habit for a user.

  ## Options

    * `:name` - Habit name (required)
    * `:description` - Longer description
    * `:frequency` - "daily", "weekly", or "custom" (default: "daily")
    * `:target_count` - Times per frequency (default: 1)
    * `:target_days` - For custom frequency, list of day numbers [1-7]
    * `:reminder_time` - Time to send reminders
    * `:reminder_enabled` - Whether to send reminders (default: true)
    * `:category` - Category for organization
  """
  @spec create(binary(), map()) :: {:ok, Habit.t()} | {:error, term()}
  def create(user_id, attrs) do
    Habit.create(user_id, attrs)
  end

  @doc """
  Marks a habit as completed for today.

  ## Options

    * `:notes` - Optional notes about the completion
    * `:quality` - Self-rating 1-5
    * `:date` - Override date (default: today)
  """
  @spec complete(binary(), map()) :: {:ok, Completion.t()} | {:error, term()}
  def complete(habit_id, attrs \\ %{}) do
    Completion.create(habit_id, attrs)
  end

  @doc """
  Checks if a habit is completed for today.
  """
  @spec completed_today?(binary()) :: boolean()
  def completed_today?(habit_id) do
    Completion.completed_today?(habit_id)
  end

  @doc """
  Gets today's progress for all active habits.

  Returns a map with completion status for each habit.
  """
  @spec today_progress(binary()) :: map()
  def today_progress(user_id) do
    habits = Habit.list_for_user(user_id, status: "active")
    today = Date.utc_today()
    day_of_week = Date.day_of_week(today)

    # Only include habits due today
    due_habits =
      Enum.filter(habits, fn habit ->
        case habit.frequency do
          "daily" -> true
          "weekly" -> day_of_week == 1
          "custom" -> day_of_week in habit.target_days
        end
      end)

    habit_ids = Enum.map(due_habits, & &1.id)
    completions = Completion.list_for_habits_on_date(habit_ids, today)
    completed_ids = MapSet.new(completions, & &1.habit_id)

    completed_count = MapSet.size(completed_ids)
    total_count = length(due_habits)

    %{
      date: today,
      total_due: total_count,
      completed: completed_count,
      pending: total_count - completed_count,
      completion_rate: if(total_count > 0, do: completed_count / total_count * 100, else: 100.0),
      habits:
        Enum.map(due_habits, fn habit ->
          %{
            id: habit.id,
            name: habit.name,
            category: habit.category,
            completed: habit.id in completed_ids,
            current_streak: habit.current_streak
          }
        end)
    }
  end

  @doc """
  Gets detailed stats for a habit.
  """
  @spec stats(binary(), keyword()) :: map()
  def stats(habit_id, opts \\ []) do
    days = Keyword.get(opts, :days, 30)

    case Habit.get(habit_id) do
      nil ->
        %{error: :not_found}

      habit ->
        completion_stats = Completion.stats(habit_id, days)

        Map.merge(completion_stats, %{
          name: habit.name,
          current_streak: habit.current_streak,
          longest_streak: habit.longest_streak,
          total_completions: habit.total_completions
        })
    end
  end

  @doc """
  Lists all habits for a user.
  """
  @spec list(binary(), keyword()) :: [Habit.t()]
  def list(user_id, opts \\ []) do
    Habit.list_for_user(user_id, opts)
  end

  @doc """
  Gets a habit by ID.
  """
  @spec get(binary()) :: Habit.t() | nil
  def get(habit_id), do: Habit.get(habit_id)

  @doc """
  Updates a habit.
  """
  @spec update(binary(), map()) :: {:ok, Habit.t()} | {:error, term()}
  def update(habit_id, attrs) do
    case Habit.get(habit_id) do
      nil -> {:error, :not_found}
      habit -> Habit.update(habit, attrs)
    end
  end

  @doc """
  Pauses a habit (stops reminders but keeps tracking).
  """
  @spec pause(binary()) :: {:ok, Habit.t()} | {:error, term()}
  def pause(habit_id), do: Habit.pause(habit_id)

  @doc """
  Resumes a paused habit.
  """
  @spec resume(binary()) :: {:ok, Habit.t()} | {:error, term()}
  def resume(habit_id), do: Habit.resume(habit_id)

  @doc """
  Archives a habit (no longer active).
  """
  @spec archive(binary()) :: {:ok, Habit.t()} | {:error, term()}
  def archive(habit_id), do: Habit.archive(habit_id)

  @doc """
  Gets habits due for nudging at the current time.
  """
  @spec due_for_nudge() :: [map()]
  def due_for_nudge do
    time = Time.utc_now()
    habits = Habit.due_for_reminder(time)

    # Filter to incomplete habits only
    today = Date.utc_today()

    habits
    |> Enum.reject(fn habit ->
      Completion.completed_on?(habit.id, today)
    end)
    |> Enum.map(fn habit ->
      %{
        habit: habit,
        user: habit.user,
        streak: habit.current_streak
      }
    end)
  end

  @doc """
  Gets a summary for a user suitable for AI context.
  """
  @spec get_summary(binary()) :: String.t()
  def get_summary(user_id) do
    progress = today_progress(user_id)

    pending =
      progress.habits
      |> Enum.filter(&(!&1.completed))
      |> Enum.map(& &1.name)

    completed =
      progress.habits
      |> Enum.filter(& &1.completed)
      |> Enum.map(& &1.name)

    """
    Habit Progress for Today:
    - Completed: #{length(completed)}/#{progress.total_due}
    - Pending: #{Enum.join(pending, ", ")}
    - Done: #{Enum.join(completed, ", ")}
    - Completion rate: #{Float.round(progress.completion_rate, 1)}%
    """
  end
end
