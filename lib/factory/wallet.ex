defmodule Factory.Wallet do
  @moduledoc """
  Manages experiment budget allocation and tracking.
  
  Budget rules:
  - $10/day initial allocation
  - Max $50 per individual experiment
  - Auto-pauses experiments that exceed daily burn rate
  - Reports P&L daily
  """
  use GenServer
  require Logger

  @daily_budget_cents 1000  # $10.00 in cents
  @max_experiment_cents 5000  # $50.00 per experiment
  
  defstruct [
    :total_allocated_cents,
    :total_spent_cents,
    :daily_spent_cents,
    :experiments,
    :last_reset
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Allocate budget for a new experiment. Returns {:ok, experiment_id} or {:error, reason}"
  def allocate(experiment_id, amount_cents) when amount_cents <= @max_experiment_cents do
    GenServer.call(__MODULE__, {:allocate, experiment_id, amount_cents})
  end

  def allocate(_experiment_id, amount_cents) do
    {:error, "Amount $#{amount_cents / 100} exceeds max per experiment ($#{@max_experiment_cents / 100})"}
  end

  @doc "Record spend against an experiment"
  def spend(experiment_id, amount_cents, description \\ nil) do
    GenServer.call(__MODULE__, {:spend, experiment_id, amount_cents, description})
  end

  @doc "Get current wallet state"
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc "Get remaining daily budget"
  def remaining_today do
    GenServer.call(__MODULE__, :remaining_today)
  end

  @doc "Record revenue from an experiment"
  def revenue(experiment_id, amount_cents, source \\ nil) do
    GenServer.call(__MODULE__, {:revenue, experiment_id, amount_cents, source})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      total_allocated_cents: 0,
      total_spent_cents: 0,
      daily_spent_cents: 0,
      experiments: %{},
      last_reset: Date.utc_today()
    }
    
    # Schedule daily reset
    schedule_daily_reset()
    
    {:ok, state}
  end

  @impl true
  def handle_call({:allocate, experiment_id, amount_cents}, _from, state) do
    remaining = @daily_budget_cents - state.daily_spent_cents
    
    cond do
      Map.has_key?(state.experiments, experiment_id) ->
        {:reply, {:error, "Experiment #{experiment_id} already exists"}, state}
      
      amount_cents > remaining ->
        {:reply, {:error, "Insufficient daily budget. Remaining: $#{remaining / 100}"}, state}
      
      true ->
        experiment = %{
          allocated_cents: amount_cents,
          spent_cents: 0,
          revenue_cents: 0,
          created_at: DateTime.utc_now(),
          transactions: []
        }
        
        new_state = %{state |
          experiments: Map.put(state.experiments, experiment_id, experiment),
          total_allocated_cents: state.total_allocated_cents + amount_cents
        }
        
        Logger.info("[Wallet] Allocated $#{amount_cents / 100} to experiment: #{experiment_id}")
        {:reply, {:ok, experiment_id}, new_state}
    end
  end

  @impl true
  def handle_call({:spend, experiment_id, amount_cents, description}, _from, state) do
    case Map.get(state.experiments, experiment_id) do
      nil ->
        {:reply, {:error, "Unknown experiment: #{experiment_id}"}, state}
      
      experiment ->
        remaining_experiment = experiment.allocated_cents - experiment.spent_cents
        remaining_daily = @daily_budget_cents - state.daily_spent_cents
        
        cond do
          amount_cents > remaining_experiment ->
            {:reply, {:error, "Exceeds experiment budget. Remaining: $#{remaining_experiment / 100}"}, state}
          
          amount_cents > remaining_daily ->
            {:reply, {:error, "Exceeds daily budget. Remaining: $#{remaining_daily / 100}"}, state}
          
          true ->
            transaction = %{
              type: :spend,
              amount_cents: amount_cents,
              description: description,
              timestamp: DateTime.utc_now()
            }
            
            updated_experiment = %{experiment |
              spent_cents: experiment.spent_cents + amount_cents,
              transactions: [transaction | experiment.transactions]
            }
            
            new_state = %{state |
              experiments: Map.put(state.experiments, experiment_id, updated_experiment),
              total_spent_cents: state.total_spent_cents + amount_cents,
              daily_spent_cents: state.daily_spent_cents + amount_cents
            }
            
            Logger.info("[Wallet] Spent $#{amount_cents / 100} on #{experiment_id}: #{description}")
            {:reply, :ok, new_state}
        end
    end
  end

  @impl true
  def handle_call({:revenue, experiment_id, amount_cents, source}, _from, state) do
    case Map.get(state.experiments, experiment_id) do
      nil ->
        {:reply, {:error, "Unknown experiment: #{experiment_id}"}, state}
      
      experiment ->
        transaction = %{
          type: :revenue,
          amount_cents: amount_cents,
          description: source,
          timestamp: DateTime.utc_now()
        }
        
        updated_experiment = %{experiment |
          revenue_cents: experiment.revenue_cents + amount_cents,
          transactions: [transaction | experiment.transactions]
        }
        
        new_state = %{state |
          experiments: Map.put(state.experiments, experiment_id, updated_experiment)
        }
        
        Logger.info("[Wallet] 💰 Revenue $#{amount_cents / 100} from #{experiment_id}: #{source}")
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    summary = %{
      daily_budget_cents: @daily_budget_cents,
      daily_remaining_cents: @daily_budget_cents - state.daily_spent_cents,
      total_allocated_cents: state.total_allocated_cents,
      total_spent_cents: state.total_spent_cents,
      total_revenue_cents: Enum.reduce(state.experiments, 0, fn {_k, v}, acc -> acc + v.revenue_cents end),
      experiment_count: map_size(state.experiments),
      experiments: Enum.map(state.experiments, fn {id, exp} ->
        %{
          id: id,
          allocated: exp.allocated_cents,
          spent: exp.spent_cents,
          revenue: exp.revenue_cents,
          roi_percent: if(exp.spent_cents > 0, do: Float.round(exp.revenue_cents / exp.spent_cents * 100, 1), else: 0)
        }
      end)
    }
    {:reply, summary, state}
  end

  @impl true
  def handle_call(:remaining_today, _from, state) do
    {:reply, @daily_budget_cents - state.daily_spent_cents, state}
  end

  @impl true
  def handle_info(:daily_reset, state) do
    Logger.info("[Wallet] Daily reset. Yesterday's spend: $#{state.daily_spent_cents / 100}")
    
    new_state = %{state |
      daily_spent_cents: 0,
      last_reset: Date.utc_today()
    }
    
    schedule_daily_reset()
    {:noreply, new_state}
  end

  defp schedule_daily_reset do
    # Reset at midnight UTC
    now = DateTime.utc_now()
    tomorrow = Date.add(Date.utc_today(), 1)
    midnight = DateTime.new!(tomorrow, ~T[00:00:00], "Etc/UTC")
    ms_until_midnight = DateTime.diff(midnight, now, :millisecond)
    
    Process.send_after(self(), :daily_reset, ms_until_midnight)
  end
end
