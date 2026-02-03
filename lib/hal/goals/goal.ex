defmodule HAL.Goals.Goal do
  @moduledoc """
  Goal schema for HAL's autonomous goal pursuit system.

  Goals are hierarchical:
  - Long-term (months): "Become proficient in Elixir"
  - Medium-term (weeks): "Complete HAL's core features"
  - Short-term (days/hours): "Implement the personality system"

  Each goal can have child goals (sub-goals) and success criteria
  that must be met for completion.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @goal_types [:long_term, :medium_term, :short_term]
  @goal_statuses [:active, :paused, :completed, :abandoned]

  schema "goals" do
    belongs_to :user, Hal.Accounts.User
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id

    field :title, :string
    field :description, :string

    field :type, Ecto.Enum, values: @goal_types, default: :short_term
    field :status, Ecto.Enum, values: @goal_statuses, default: :active

    field :progress, :float, default: 0.0
    field :success_criteria, {:array, :string}, default: []
    field :target_date, :utc_datetime
    field :priority, :integer, default: 50
    field :metadata, :map, default: %{}

    field :last_worked_at, :utc_datetime
    field :work_sessions_count, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new goal.
  """
  def create_changeset(goal, attrs) do
    goal
    |> cast(attrs, [
      :user_id,
      :parent_id,
      :title,
      :description,
      :type,
      :success_criteria,
      :target_date,
      :priority,
      :metadata
    ])
    |> validate_required([:user_id, :title])
    |> validate_length(:title, min: 1, max: 255)
    |> validate_number(:priority, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end

  @doc """
  Changeset for updating goal progress.
  """
  def progress_changeset(goal, attrs) do
    goal
    |> cast(attrs, [:progress, :last_worked_at, :work_sessions_count])
    |> validate_number(:progress, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end

  @doc """
  Changeset for updating goal status.
  """
  def status_changeset(goal, attrs) do
    goal
    |> cast(attrs, [:status, :progress])
    |> validate_inclusion(:status, @goal_statuses)
  end

  @doc """
  Changeset for general updates.
  """
  def update_changeset(goal, attrs) do
    goal
    |> cast(attrs, [
      :title,
      :description,
      :type,
      :status,
      :progress,
      :success_criteria,
      :target_date,
      :priority,
      :metadata,
      :last_worked_at,
      :work_sessions_count
    ])
    |> validate_length(:title, min: 1, max: 255)
    |> validate_number(:priority, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:progress, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end

  @doc """
  Get all valid goal types.
  """
  def types, do: @goal_types

  @doc """
  Get all valid goal statuses.
  """
  def statuses, do: @goal_statuses

  @doc """
  Check if goal is actionable (active and not blocked).
  """
  def actionable?(%__MODULE__{status: :active} = goal) do
    # A goal is actionable if it has no incomplete children
    # (leaf goal or all children complete)
    not has_incomplete_children?(goal)
  end

  def actionable?(_), do: false

  defp has_incomplete_children?(%__MODULE__{children: children}) when is_list(children) do
    Enum.any?(children, fn child ->
      child.status != :completed
    end)
  end

  defp has_incomplete_children?(_), do: false
end
