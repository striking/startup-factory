defmodule HAL.Goals.Manager do
  @moduledoc """
  CRUD and business logic for goal management.

  Provides functions for creating, updating, and querying goals,
  as well as progress tracking and goal decomposition.
  """

  import Ecto.Query
  alias Hal.Repo
  alias HAL.Goals.Goal

  # CRUD Operations

  @doc """
  Create a new goal for a user.
  """
  @spec create_goal(Ecto.UUID.t(), map()) :: {:ok, Goal.t()} | {:error, Ecto.Changeset.t()}
  def create_goal(user_id, attrs) do
    %Goal{}
    |> Goal.create_changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert()
  end

  @doc """
  Get a goal by ID.
  """
  @spec get_goal(Ecto.UUID.t()) :: Goal.t() | nil
  def get_goal(id) do
    Goal
    |> Repo.get(id)
    |> Repo.preload(:children)
  end

  @doc """
  Get a goal by ID, raising if not found.
  """
  @spec get_goal!(Ecto.UUID.t()) :: Goal.t()
  def get_goal!(id) do
    Goal
    |> Repo.get!(id)
    |> Repo.preload(:children)
  end

  @doc """
  Update a goal.
  """
  @spec update_goal(Goal.t(), map()) :: {:ok, Goal.t()} | {:error, Ecto.Changeset.t()}
  def update_goal(goal, attrs) do
    goal
    |> Goal.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a goal (and its children via cascade).
  """
  @spec delete_goal(Goal.t()) :: {:ok, Goal.t()} | {:error, Ecto.Changeset.t()}
  def delete_goal(goal) do
    Repo.delete(goal)
  end

  # Query Operations

  @doc """
  Get all active goals for a user.
  """
  @spec get_active_goals(Ecto.UUID.t()) :: {:ok, [Goal.t()]} | {:error, term()}
  def get_active_goals(user_id) do
    goals =
      Goal
      |> where([g], g.user_id == ^user_id and g.status == :active)
      |> order_by([g], desc: g.priority, asc: g.type)
      |> Repo.all()
      |> Repo.preload(:children)

    {:ok, goals}
  end

  @doc """
  Get goals by type for a user.
  """
  @spec get_goals_by_type(Ecto.UUID.t(), atom()) :: [Goal.t()]
  def get_goals_by_type(user_id, type) when type in [:long_term, :medium_term, :short_term] do
    Goal
    |> where([g], g.user_id == ^user_id and g.type == ^type and g.status == :active)
    |> order_by([g], desc: g.priority)
    |> Repo.all()
  end

  @doc """
  Get the next actionable goal (highest priority active goal with no incomplete children).
  """
  @spec get_next_actionable(Ecto.UUID.t()) :: {:ok, Goal.t()} | :no_actionable
  def get_next_actionable(user_id) do
    # Get all active short-term goals first, then medium, then long
    goal =
      Goal
      |> where([g], g.user_id == ^user_id and g.status == :active)
      |> order_by([g], asc: g.type, desc: g.priority)
      |> Repo.all()
      |> Repo.preload(:children)
      |> Enum.find(&Goal.actionable?/1)

    case goal do
      nil -> :no_actionable
      goal -> {:ok, goal}
    end
  end

  @doc """
  Get child goals (sub-goals) of a parent goal.
  """
  @spec get_children(Ecto.UUID.t()) :: [Goal.t()]
  def get_children(parent_id) do
    Goal
    |> where([g], g.parent_id == ^parent_id)
    |> order_by([g], desc: g.priority)
    |> Repo.all()
  end

  # Progress Tracking

  @doc """
  Update goal progress and log the change.
  """
  @spec update_progress(Goal.t(), float(), String.t(), keyword()) ::
          {:ok, Goal.t()} | {:error, term()}
  def update_progress(goal, new_progress, summary, opts \\ []) do
    session_id = Keyword.get(opts, :session_id)

    Repo.transaction(fn ->
      # Update the goal
      {:ok, updated_goal} =
        goal
        |> Goal.progress_changeset(%{
          progress: clamp_progress(new_progress),
          last_worked_at: DateTime.utc_now(),
          work_sessions_count: goal.work_sessions_count + 1
        })
        |> Repo.update()

      # Log the progress entry
      Repo.insert!(%{
        __struct__: HAL.Goals.ProgressEntry,
        goal_id: goal.id,
        previous_progress: goal.progress,
        new_progress: new_progress,
        summary: summary,
        session_id: session_id
      })

      # Auto-complete if progress = 1.0
      if new_progress >= 1.0 do
        complete_goal(updated_goal)
      else
        updated_goal
      end
    end)
  end

  @doc """
  Mark a goal as completed.
  """
  @spec complete_goal(Goal.t()) :: {:ok, Goal.t()} | {:error, term()}
  def complete_goal(goal) do
    goal
    |> Goal.status_changeset(%{status: :completed, progress: 1.0})
    |> Repo.update()
    |> case do
      {:ok, completed_goal} ->
        # Update parent progress if exists
        maybe_update_parent_progress(completed_goal)
        {:ok, completed_goal}

      error ->
        error
    end
  end

  @doc """
  Pause a goal.
  """
  @spec pause_goal(Goal.t()) :: {:ok, Goal.t()} | {:error, term()}
  def pause_goal(goal) do
    goal
    |> Goal.status_changeset(%{status: :paused})
    |> Repo.update()
  end

  @doc """
  Abandon a goal.
  """
  @spec abandon_goal(Goal.t(), String.t()) :: {:ok, Goal.t()} | {:error, term()}
  def abandon_goal(goal, reason \\ "") do
    metadata = Map.put(goal.metadata, "abandonment_reason", reason)

    goal
    |> Goal.update_changeset(%{status: :abandoned, metadata: metadata})
    |> Repo.update()
  end

  # Goal Decomposition

  @doc """
  Create a sub-goal under a parent goal.
  """
  @spec create_subgoal(Goal.t(), map()) :: {:ok, Goal.t()} | {:error, Ecto.Changeset.t()}
  def create_subgoal(parent, attrs) do
    # Sub-goals inherit user_id from parent
    # Type is automatically one level down
    child_type = child_goal_type(parent.type)

    %Goal{}
    |> Goal.create_changeset(
      attrs
      |> Map.put(:user_id, parent.user_id)
      |> Map.put(:parent_id, parent.id)
      |> Map.put(:type, child_type)
    )
    |> Repo.insert()
  end

  # Context Generation

  @doc """
  Format goals as context for system prompts.
  """
  @spec as_context([Goal.t()]) :: String.t()
  def as_context([]), do: ""

  def as_context(goals) do
    by_type = Enum.group_by(goals, & &1.type)

    sections =
      [:long_term, :medium_term, :short_term]
      |> Enum.map(fn type ->
        goals_of_type = Map.get(by_type, type, [])

        if Enum.any?(goals_of_type) do
          format_goal_section(type, goals_of_type)
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    """
    # Your Active Goals

    Work toward these goals during autonomous operation. Prioritize short-term
    goals that contribute to medium and long-term objectives.

    #{sections}
    """
  end

  # Private Functions

  defp clamp_progress(value) do
    value
    |> max(0.0)
    |> min(1.0)
  end

  defp child_goal_type(:long_term), do: :medium_term
  defp child_goal_type(:medium_term), do: :short_term
  defp child_goal_type(:short_term), do: :short_term

  defp maybe_update_parent_progress(%Goal{parent_id: nil}), do: :ok

  defp maybe_update_parent_progress(%Goal{parent_id: parent_id}) do
    parent = get_goal(parent_id)

    if parent do
      children = get_children(parent_id)

      if Enum.any?(children) do
        # Calculate parent progress as average of children
        total_progress = Enum.sum(Enum.map(children, & &1.progress))
        avg_progress = total_progress / length(children)

        parent
        |> Goal.progress_changeset(%{progress: avg_progress})
        |> Repo.update()
      end
    end
  end

  defp format_goal_section(type, goals) do
    type_label = type |> to_string() |> String.replace("_", " ") |> String.capitalize()

    goal_lines =
      goals
      |> Enum.map(fn goal ->
        progress_pct = round(goal.progress * 100)
        target = if goal.target_date, do: " (due: #{Date.to_string(goal.target_date)})", else: ""
        "- [#{progress_pct}%] #{goal.title}#{target}"
      end)
      |> Enum.join("\n")

    """
    ## #{type_label} Goals

    #{goal_lines}
    """
  end
end

# Progress entry schema (simple, no need for separate file)
defmodule HAL.Goals.ProgressEntry do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "goal_progress_entries" do
    belongs_to :goal, HAL.Goals.Goal

    field :previous_progress, :float
    field :new_progress, :float
    field :summary, :string
    field :session_id, :binary_id

    timestamps(type: :utc_datetime)
  end
end
