defmodule HAL.Goals.Supervisor do
  @moduledoc """
  Supervisor for the Goals system.

  Manages:
  - Goals Registry (for tracking goal-related processes)
  - DynamicSupervisor for goal workers

  Note: The per-user GoalPursuer was removed as redundant with HAL.Heartbeat's
  goal processing. Goals are now managed via HAL.Goals.Manager and processed
  during heartbeat cycles.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Registry for goal-related processes
      {Registry, keys: :unique, name: HAL.Goals.Registry},

      # DynamicSupervisor for dynamic goal workers
      {DynamicSupervisor, name: HAL.Goals.DynamicSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
