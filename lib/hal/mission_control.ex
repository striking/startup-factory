defmodule Hal.MissionControl do
  @moduledoc """
  Read model for the Mission Control UI.

  Aggregates runtime state (agents) and persisted state (tasks, approvals)
  into a single snapshot for rendering.
  """

  import Ecto.Query

  alias HAL.AgentRegistry
  alias HAL.Autonomy.Approvals
  alias HAL.Costs.Budget
  alias HAL.EventLog
  alias HAL.SelfImprovement.ChangeRequests
  alias Hal.Accounts.DefaultUser
  alias Hal.Repo
  alias Hal.Tasks.AutoTask

  @doc """
  Returns a Mission Control snapshot.
  """
  @spec snapshot(keyword()) :: map()
  def snapshot(opts \\ []) do
    user = DefaultUser.get()

    %{
      agents: AgentRegistry.list_agents(),
      tasks: list_tasks(limit: Keyword.get(opts, :tasks_limit, 100)),
      approvals: Approvals.list_pending(limit: Keyword.get(opts, :approvals_limit, 25)),
      queue: Approvals.list_queue(limit: Keyword.get(opts, :queue_limit, 25)),
      recent_approvals:
        Approvals.list_recent_executions(limit: Keyword.get(opts, :recent_approvals_limit, 25)),
      changes: ChangeRequests.list_recent(limit: Keyword.get(opts, :changes_limit, 25)),
      events: EventLog.recent(limit: Keyword.get(opts, :events_limit, 50)),
      budget: if(user, do: Budget.get_remaining(user.id), else: nil)
    }
  end

  @doc """
  Lists recent autonomous tasks (preloaded with user).
  """
  @spec list_tasks(keyword()) :: [AutoTask.t()]
  def list_tasks(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    from(t in AutoTask,
      order_by: [desc: t.inserted_at],
      limit: ^limit,
      preload: [:user]
    )
    |> Repo.all()
  end
end
