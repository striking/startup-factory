defmodule Hal.Habits.Habit do
  @moduledoc """
  Schema for user habits to track and build routines.

  Supports daily, weekly, and custom frequency tracking with
  streak calculation and reminder configuration.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, except: [update: 2]

  alias Hal.Accounts.User
  alias Hal.Habits.Completion
  alias Hal.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @frequencies ~w(daily weekly custom)
  @statuses ~w(active paused archived)
  @categories ~w(health productivity learning mindfulness social finance other)

  schema "habits" do
    belongs_to :user, User
    has_many :completions, Completion

    field :name, :string
    field :description, :string
    field :frequency, :string, default: "daily"
    field :target_count, :integer, default: 1
    field :target_days, {:array, :integer}, default: []

    field :reminder_time, :time
    field :reminder_enabled, :boolean, default: true

    field :current_streak, :integer, default: 0
    field :longest_streak, :integer, default: 0
    field :total_completions, :integer, default: 0

    field :status, :string, default: "active"
    field :category, :string
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a habit.
  """
  def changeset(habit, attrs) do
    habit
    |> cast(attrs, [
      :user_id,
      :name,
      :description,
      :frequency,
      :target_count,
      :target_days,
      :reminder_time,
      :reminder_enabled,
      :current_streak,
      :longest_streak,
      :total_completions,
      :status,
      :category,
      :metadata
    ])
    |> validate_required([:user_id, :name, :frequency])
    |> validate_inclusion(:frequency, @frequencies)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:category, @categories ++ [nil])
    |> validate_number(:target_count, greater_than: 0)
    |> validate_target_days()
  end

  defp validate_target_days(changeset) do
    case get_field(changeset, :frequency) do
      "custom" ->
        validate_required(changeset, [:target_days])

      _ ->
        changeset
    end
  end

  @doc """
  Creates a new habit.
  """
  @spec create(binary(), map()) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def create(user_id, attrs) do
    %__MODULE__{}
    |> changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert()
  end

  @doc """
  Gets a habit by ID.
  """
  @spec get(binary()) :: %__MODULE__{} | nil
  def get(id), do: Repo.get(__MODULE__, id)

  @doc """
  Gets a habit with completions preloaded.
  """
  @spec get_with_completions(binary(), keyword()) :: %__MODULE__{} | nil
  def get_with_completions(id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 30)

    __MODULE__
    |> Repo.get(id)
    |> Repo.preload(completions: from(c in Completion, order_by: [desc: c.date], limit: ^limit))
  end

  @doc """
  Lists habits for a user.
  """
  @spec list_for_user(binary(), keyword()) :: [%__MODULE__{}]
  def list_for_user(user_id, opts \\ []) do
    status = Keyword.get(opts, :status, "active")
    category = Keyword.get(opts, :category)

    query =
      from(h in __MODULE__,
        where: h.user_id == ^user_id,
        order_by: [asc: h.name]
      )

    query = if status, do: where(query, [h], h.status == ^status), else: query
    query = if category, do: where(query, [h], h.category == ^category), else: query

    Repo.all(query)
  end

  @doc """
  Lists habits due for reminder at a given time.
  """
  @spec due_for_reminder(Time.t(), integer()) :: [%__MODULE__{}]
  def due_for_reminder(time, tolerance_minutes \\ 5) do
    # Find habits with reminder_time within tolerance window
    time_min = Time.add(time, -tolerance_minutes * 60, :second)
    time_max = Time.add(time, tolerance_minutes * 60, :second)

    today = Date.utc_today()
    day_of_week = Date.day_of_week(today)

    from(h in __MODULE__,
      where: h.status == "active",
      where: h.reminder_enabled == true,
      where: not is_nil(h.reminder_time),
      where: h.reminder_time >= ^time_min and h.reminder_time <= ^time_max,
      preload: [:user]
    )
    |> Repo.all()
    |> Enum.filter(&should_run_today?(&1, day_of_week))
  end

  defp should_run_today?(habit, day_of_week) do
    case habit.frequency do
      "daily" -> true
      # Monday only for weekly
      "weekly" -> day_of_week == 1
      "custom" -> day_of_week in habit.target_days
    end
  end

  @doc """
  Updates a habit.
  """
  @spec update(%__MODULE__{}, map()) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def update(habit, attrs) do
    habit
    |> changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates streak counters for a habit.
  """
  @spec update_streaks(binary()) :: {:ok, %__MODULE__{}} | {:error, term()}
  def update_streaks(habit_id) do
    case get(habit_id) do
      nil ->
        {:error, :not_found}

      habit ->
        streak = calculate_current_streak(habit_id)
        total = count_completions(habit_id)
        longest = max(habit.longest_streak, streak)

        update(habit, %{
          current_streak: streak,
          longest_streak: longest,
          total_completions: total
        })
    end
  end

  defp calculate_current_streak(habit_id) do
    # Count consecutive days from today going backwards
    today = Date.utc_today()

    completions =
      from(c in Completion,
        where: c.habit_id == ^habit_id,
        where: c.date <= ^today,
        order_by: [desc: c.date],
        select: c.date
      )
      |> Repo.all()

    count_consecutive_days(completions, today, 0)
  end

  defp count_consecutive_days([], _expected_date, count), do: count

  defp count_consecutive_days([date | rest], expected_date, count) do
    cond do
      Date.compare(date, expected_date) == :eq ->
        count_consecutive_days(rest, Date.add(expected_date, -1), count + 1)

      Date.compare(date, expected_date) == :lt and count == 0 ->
        # Started streak from a past date
        count_consecutive_days(rest, Date.add(date, -1), 1)

      true ->
        count
    end
  end

  defp count_completions(habit_id) do
    from(c in Completion, where: c.habit_id == ^habit_id, select: count())
    |> Repo.one()
  end

  @doc """
  Archives a habit.
  """
  @spec archive(binary()) :: {:ok, %__MODULE__{}} | {:error, term()}
  def archive(habit_id) do
    case get(habit_id) do
      nil -> {:error, :not_found}
      habit -> update(habit, %{status: "archived"})
    end
  end

  @doc """
  Pauses a habit (stops reminders).
  """
  @spec pause(binary()) :: {:ok, %__MODULE__{}} | {:error, term()}
  def pause(habit_id) do
    case get(habit_id) do
      nil -> {:error, :not_found}
      habit -> update(habit, %{status: "paused"})
    end
  end

  @doc """
  Resumes a paused habit.
  """
  @spec resume(binary()) :: {:ok, %__MODULE__{}} | {:error, term()}
  def resume(habit_id) do
    case get(habit_id) do
      nil -> {:error, :not_found}
      habit -> update(habit, %{status: "active"})
    end
  end
end
