defmodule Hal.Habits.Completion do
  @moduledoc """
  Schema for habit completion records.

  Tracks when a habit was completed, with optional notes and quality rating.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Hal.Habits.Habit
  alias Hal.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "habit_completions" do
    belongs_to :habit, Habit

    field :completed_at, :utc_datetime
    field :date, :date
    field :notes, :string
    # 1-5
    field :quality, :integer

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a completion.
  """
  def changeset(completion, attrs) do
    completion
    |> cast(attrs, [:habit_id, :completed_at, :date, :notes, :quality])
    |> validate_required([:habit_id, :completed_at, :date])
    |> validate_inclusion(:quality, 1..5, allow_nil: true)
    |> unique_constraint([:habit_id, :date], name: :habit_completions_habit_date_unique)
    |> foreign_key_constraint(:habit_id)
  end

  @doc """
  Records a completion for a habit.
  """
  @spec create(binary(), map()) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def create(habit_id, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    today = Date.utc_today()

    %__MODULE__{}
    |> changeset(
      Map.merge(attrs, %{
        habit_id: habit_id,
        completed_at: Map.get(attrs, :completed_at, now),
        date: Map.get(attrs, :date, today)
      })
    )
    |> Repo.insert()
    |> case do
      {:ok, completion} ->
        # Update habit streaks
        Habit.update_streaks(habit_id)
        {:ok, completion}

      error ->
        error
    end
  end

  @doc """
  Checks if a habit is completed for a given date.
  """
  @spec completed_today?(binary()) :: boolean()
  def completed_today?(habit_id) do
    completed_on?(habit_id, Date.utc_today())
  end

  @doc """
  Checks if a habit was completed on a specific date.
  """
  @spec completed_on?(binary(), Date.t()) :: boolean()
  def completed_on?(habit_id, date) do
    from(c in __MODULE__,
      where: c.habit_id == ^habit_id,
      where: c.date == ^date,
      select: count()
    )
    |> Repo.one()
    |> Kernel.>(0)
  end

  @doc """
  Lists completions for a habit within a date range.
  """
  @spec list_for_habit(binary(), Date.t(), Date.t()) :: [%__MODULE__{}]
  def list_for_habit(habit_id, start_date, end_date) do
    from(c in __MODULE__,
      where: c.habit_id == ^habit_id,
      where: c.date >= ^start_date and c.date <= ^end_date,
      order_by: [desc: c.date]
    )
    |> Repo.all()
  end

  @doc """
  Gets completions for multiple habits on a date.
  """
  @spec list_for_habits_on_date([binary()], Date.t()) :: [%__MODULE__{}]
  def list_for_habits_on_date(habit_ids, date) do
    from(c in __MODULE__,
      where: c.habit_id in ^habit_ids,
      where: c.date == ^date
    )
    |> Repo.all()
  end

  @doc """
  Gets completion statistics for a habit.
  """
  @spec stats(binary(), integer()) :: map()
  def stats(habit_id, days \\ 30) do
    end_date = Date.utc_today()
    start_date = Date.add(end_date, -days)

    completions = list_for_habit(habit_id, start_date, end_date)
    completed_dates = MapSet.new(completions, & &1.date)

    total_days = Date.diff(end_date, start_date) + 1
    completed_count = length(completions)

    avg_quality =
      completions
      |> Enum.filter(& &1.quality)
      |> case do
        [] -> nil
        with_quality -> Enum.sum(Enum.map(with_quality, & &1.quality)) / length(with_quality)
      end

    %{
      period_days: total_days,
      completed_count: completed_count,
      completion_rate: completed_count / total_days * 100,
      average_quality: avg_quality,
      completed_dates: MapSet.to_list(completed_dates) |> Enum.sort()
    }
  end

  @doc """
  Deletes a completion (undo).
  """
  @spec delete(binary()) :: {:ok, %__MODULE__{}} | {:error, term()}
  def delete(completion_id) do
    case Repo.get(__MODULE__, completion_id) do
      nil ->
        {:error, :not_found}

      completion ->
        habit_id = completion.habit_id

        case Repo.delete(completion) do
          {:ok, deleted} ->
            Habit.update_streaks(habit_id)
            {:ok, deleted}

          error ->
            error
        end
    end
  end
end
