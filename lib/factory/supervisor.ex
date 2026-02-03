defmodule Factory.Supervisor do
  @moduledoc """
  Root supervisor for the Startup Factory system.
  
  Manages:
  - Wallet (budget tracking)
  - Experiment Registry (process lookup)
  - Experiment Supervisor (dynamic experiment processes)
  - Pipeline Orchestrator (automated experiment runs)
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Registry for looking up experiments by ID
      {Registry, keys: :unique, name: Factory.ExperimentRegistry},
      
      # Wallet for budget management
      Factory.Wallet,
      
      # DynamicSupervisor for experiment processes
      {DynamicSupervisor, strategy: :one_for_one, name: Factory.ExperimentSupervisor},
      
      # Pipeline orchestrator for automated runs
      Factory.Pipeline
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
