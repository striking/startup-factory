defmodule HAL.Autonomy.Supervisor do
  @moduledoc """
  Supervisor for autonomy components.

  Manages:
  - Registry for autonomy processes
  - DynamicSupervisor for dynamic autonomy workers

  Note: The per-user Orchestrator was removed as redundant with HAL.Heartbeat.
  This supervisor remains for future autonomy extensions.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Registry for autonomy processes
      {Registry, keys: :unique, name: HAL.Autonomy.Registry},

      # DynamicSupervisor for dynamic workers
      {DynamicSupervisor, name: HAL.Autonomy.DynamicSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
