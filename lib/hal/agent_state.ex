defmodule HAL.AgentState do
  @moduledoc """
  Agent state management using event sourcing and ETS caching.

  Provides fast in-memory access to agent state while maintaining
  complete event history in JSONL for persistence and learning.

  ## Architecture

  - **ETS** - Fast in-memory cache of current state (rebuilt on boot)
  - **JSONL** - Source of truth, complete event history
  - **Event Sourcing** - Replay events to rebuild state after restart

  ## State Structure

  ETS table `:agent_state` contains:
  - `{:current_tasks, [task_names]}`
  - `{:completed_tasks, [task_data]}`
  - `{:learned_facts, [facts]}`
  - `{:strategies, %{task => strategy}}`
  - `{:goals, [goal_data]}`
  - `{:last_action, timestamp}`
  - `{:stats, %{...}}`

  ## Usage

      # Initialize (called on application start)
      AgentState.init()

      # Log events (automatically updates ETS)
      AgentState.task_started("organize inbox", "create labels by sender")
      AgentState.action_taken("created 5 labels", %{success: true})
      AgentState.learned("IMAP timeouts at 10am", confidence: 0.8)
      AgentState.task_completed("organize inbox", "5 labels created")

      # Query state (fast ETS lookups)
      AgentState.get_current_tasks()
      AgentState.get_learned_facts()
      AgentState.get_strategy("organize inbox")

      # Context for autonomous decisions
      AgentState.get_context()
  """

  use GenServer
  require Logger

  alias HAL.EventLog

  @table_name :agent_state

  # Client API

  @doc """
  Start the AgentState GenServer.

  Rebuilds state from event log on startup.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initialize agent state (called by Application on boot).

  Creates ETS table and schedules async state loading via handle_continue.
  This prevents blocking the supervision tree during boot.
  """
  @impl true
  def init(_opts) do
    # Create ETS table for fast lookups with empty defaults
    # This allows queries to work immediately (returning [])
    :ets.new(@table_name, [:set, :named_table, :public, read_concurrency: true])

    # Insert empty defaults - queries will work but return empty until loaded
    :ets.insert(@table_name, [
      {:current_tasks, []},
      {:completed_tasks, []},
      {:failed_tasks, []},
      {:learned_facts, []},
      {:strategies, %{}},
      {:goals, []},
      {:last_action, nil},
      {:loading, true}
    ])

    # Use handle_continue to load state async after init returns
    # This prevents blocking the supervision tree and avoids OTP timeout
    {:ok, %{}, {:continue, :load_from_event_log}}
  end

  @impl true
  def handle_continue(:load_from_event_log, state) do
    Logger.debug("AgentState: Loading state from event log...")

    # Rebuild state from event log (using snapshot if available for faster startup)
    event_state = EventLog.replay_with_snapshot()

    # Store in ETS (single batch insert for efficiency)
    :ets.insert(@table_name, [
      {:current_tasks, event_state.current_tasks},
      {:completed_tasks, event_state.completed_tasks},
      {:failed_tasks, event_state.failed_tasks},
      {:learned_facts, event_state.learned_facts},
      {:strategies, event_state.strategies},
      {:goals, event_state.goals},
      {:last_action, DateTime.utc_now()},
      {:loading, false}
    ])

    Logger.info("""
    AgentState initialized from event log:
    - Current tasks: #{length(event_state.current_tasks)}
    - Completed tasks: #{length(event_state.completed_tasks)}
    - Learned facts: #{length(event_state.learned_facts)}
    - Strategies: #{map_size(event_state.strategies)}
    - Goals: #{length(event_state.goals)}
    """)

    # Schedule periodic snapshot check (every hour)
    schedule_snapshot_check()

    {:noreply, state}
  end

  # Task Management

  @doc """
  Log that agent started working on a task.

  Automatically updates ETS cache.
  """
  @spec task_started(String.t(), String.t() | nil, keyword()) :: :ok
  def task_started(task, strategy \\ nil, opts \\ []) do
    context = Keyword.get(opts, :context, %{})

    EventLog.log(:task_started, %{
      task: task,
      strategy: strategy,
      context: context
    })

    # Update ETS
    current_tasks = get_current_tasks()
    :ets.insert(@table_name, {:current_tasks, [task | current_tasks]})

    if strategy do
      strategies = get_strategies()
      :ets.insert(@table_name, {:strategies, Map.put(strategies, task, strategy)})
    end

    :ok
  end

  @doc """
  Log that a task completed successfully.
  """
  @spec task_completed(String.t(), String.t(), keyword()) :: :ok
  def task_completed(task, outcome, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, %{})

    task_data = %{
      task: task,
      outcome: outcome,
      completed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      metadata: metadata
    }

    EventLog.log(:task_completed, task_data)

    # Update ETS
    current_tasks = get_current_tasks()
    completed_tasks = get_completed_tasks()

    :ets.insert(@table_name, {:current_tasks, List.delete(current_tasks, task)})
    :ets.insert(@table_name, {:completed_tasks, [task_data | completed_tasks]})

    :ok
  end

  @doc """
  Log that a task failed.
  """
  @spec task_failed(String.t(), String.t(), keyword()) :: :ok
  def task_failed(task, reason, opts \\ []) do
    retry_count = Keyword.get(opts, :retry_count, 0)
    metadata = Keyword.get(opts, :metadata, %{})

    task_data = %{
      task: task,
      reason: reason,
      retry_count: retry_count,
      failed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      metadata: metadata
    }

    EventLog.log(:task_failed, task_data)

    # Update ETS
    current_tasks = get_current_tasks()
    failed_tasks = get_failed_tasks()

    :ets.insert(@table_name, {:current_tasks, List.delete(current_tasks, task)})
    :ets.insert(@table_name, {:failed_tasks, [task_data | failed_tasks]})

    :ok
  end

  # Action Tracking

  @doc """
  Log an action taken by the agent.
  """
  @spec action_taken(String.t(), map()) :: :ok
  def action_taken(action, result) do
    EventLog.log(:action_taken, %{
      action: action,
      result: result,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    :ets.insert(@table_name, {:last_action, DateTime.utc_now()})
    :ok
  end

  @doc """
  Log a failed action.
  """
  @spec action_failed(String.t(), String.t(), keyword()) :: :ok
  def action_failed(action, error, opts \\ []) do
    retry_count = Keyword.get(opts, :retry_count, 0)

    EventLog.log(:action_failed, %{
      action: action,
      error: error,
      retry_count: retry_count
    })

    :ok
  end

  # Learning & Decisions

  @doc """
  Log a fact learned by the agent.

  ## Examples

      AgentState.learned("IMAP timeouts happen at 10am", confidence: 0.8)
      AgentState.learned("User prefers summaries over full text", confidence: 0.9)
  """
  @spec learned(String.t(), keyword()) :: :ok
  def learned(fact, opts \\ []) do
    confidence = Keyword.get(opts, :confidence, 0.7)
    source = Keyword.get(opts, :source, "observation")

    EventLog.log(:learned, %{
      fact: fact,
      confidence: confidence,
      source: source
    })

    # Update ETS
    learned_facts = get_learned_facts()
    :ets.insert(@table_name, {:learned_facts, [fact | learned_facts]})

    :ok
  end

  @doc """
  Log a strategy adjustment based on learning.
  """
  @spec strategy_adjusted(String.t(), String.t(), String.t()) :: :ok
  def strategy_adjusted(task, old_strategy, new_strategy) do
    EventLog.log(:strategy_adjusted, %{
      task: task,
      old: old_strategy,
      new: new_strategy,
      reason: "based on learned facts"
    })

    # Update ETS
    strategies = get_strategies()
    :ets.insert(@table_name, {:strategies, Map.put(strategies, task, new_strategy)})

    :ok
  end

  @doc """
  Log a decision made by the agent.
  """
  @spec decision_made(String.t(), String.t()) :: :ok
  def decision_made(decision, reasoning) do
    EventLog.log(:decision_made, %{
      decision: decision,
      reasoning: reasoning
    })

    :ok
  end

  # Goal Management

  @doc """
  Set a new goal for the agent.
  """
  @spec goal_set(String.t(), keyword()) :: :ok
  def goal_set(goal, opts \\ []) do
    priority = Keyword.get(opts, :priority, 5)
    deadline = Keyword.get(opts, :deadline)

    goal_id = UUID.uuid4()

    goal_data = %{
      id: goal_id,
      goal: goal,
      priority: priority,
      deadline: deadline,
      set_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    EventLog.log(:goal_set, goal_data)

    # Update ETS
    goals = get_goals()
    :ets.insert(@table_name, {:goals, [goal_data | goals]})

    :ok
  end

  @doc """
  Mark a goal as completed.
  """
  @spec goal_completed(String.t(), keyword()) :: :ok
  def goal_completed(goal_id, opts \\ []) do
    outcome = Keyword.get(opts, :outcome, "completed")

    EventLog.log(:goal_completed, %{
      goal_id: goal_id,
      outcome: outcome,
      completed_at: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    # Update ETS
    goals = get_goals()
    updated_goals = Enum.reject(goals, fn g -> g[:id] == goal_id end)
    :ets.insert(@table_name, {:goals, updated_goals})

    :ok
  end

  # Query API (fast ETS lookups)

  @doc """
  Get all current (in-progress) tasks.
  """
  @spec get_current_tasks() :: list(String.t())
  def get_current_tasks do
    ets_get(:current_tasks, [])
  end

  @doc """
  Get completed tasks.
  """
  @spec get_completed_tasks(keyword()) :: list(map())
  def get_completed_tasks(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    ets_get(:completed_tasks, []) |> Enum.take(limit)
  end

  @doc """
  Get failed tasks (for learning from mistakes).
  """
  @spec get_failed_tasks(keyword()) :: list(map())
  def get_failed_tasks(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    ets_get(:failed_tasks, []) |> Enum.take(limit)
  end

  @doc """
  Get all learned facts.
  """
  @spec get_learned_facts() :: list(String.t())
  def get_learned_facts do
    ets_get(:learned_facts, [])
  end

  @doc """
  Get all strategies.
  """
  @spec get_strategies() :: map()
  def get_strategies do
    ets_get(:strategies, %{})
  end

  @doc """
  Get strategy for a specific task.
  """
  @spec get_strategy(String.t()) :: String.t() | nil
  def get_strategy(task) do
    get_strategies()[task]
  end

  @doc """
  Get all active goals.
  """
  @spec get_goals() :: list(map())
  def get_goals do
    ets_get(:goals, [])
  end

  @doc """
  Get complete context for autonomous decision-making.

  Returns all relevant state for agent to make informed decisions.
  """
  @spec get_context() :: map()
  def get_context do
    %{
      current_tasks: get_current_tasks(),
      recent_completions: get_completed_tasks(limit: 5),
      recent_failures: get_failed_tasks(limit: 5),
      learned_facts: get_learned_facts(),
      strategies: get_strategies(),
      goals: get_goals(),
      last_action: get_last_action(),
      stats: EventLog.stats()
    }
  end

  @doc """
  Get timestamp of last action (for checking if agent is idle).
  """
  @spec get_last_action() :: DateTime.t() | nil
  def get_last_action do
    ets_get(:last_action)
  end

  @doc """
  Check if state is still being loaded from event log.

  Returns true during the async loading phase after boot.
  Callers can use this to show loading indicators or wait.
  """
  @spec loading?() :: boolean()
  def loading? do
    ets_get(:loading, false)
  end

  @doc """
  Rebuild state from event log.

  Useful for recovery or testing.
  """
  @spec rebuild_from_log() :: :ok
  def rebuild_from_log do
    GenServer.call(__MODULE__, :rebuild)
  end

  @doc """
  Creates a snapshot of current state if threshold is reached.

  Returns :ok if snapshot created or not needed, error otherwise.
  """
  @spec maybe_snapshot() :: :ok | {:error, term()}
  def maybe_snapshot do
    if EventLog.should_snapshot?() do
      case EventLog.create_snapshot() do
        {:ok, _} -> :ok
        error -> error
      end
    else
      :ok
    end
  end

  @doc """
  Forces creation of a snapshot regardless of threshold.
  """
  @spec force_snapshot() :: {:ok, map()} | {:error, term()}
  def force_snapshot do
    EventLog.create_snapshot()
  end

  # GenServer Callbacks

  @impl true
  def handle_info(:check_snapshot, state) do
    # Check if we should create a snapshot
    case maybe_snapshot() do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Snapshot check failed: #{inspect(reason)}")
    end

    schedule_snapshot_check()
    {:noreply, state}
  end

  @impl true
  def handle_call(:rebuild, _from, state) do
    # Re-replay all events
    new_state = EventLog.replay()

    # Update ETS (single batch insert for efficiency)
    :ets.insert(@table_name, [
      {:current_tasks, new_state.current_tasks},
      {:completed_tasks, new_state.completed_tasks},
      {:failed_tasks, new_state.failed_tasks},
      {:learned_facts, new_state.learned_facts},
      {:strategies, new_state.strategies},
      {:goals, new_state.goals}
    ])

    Logger.info("AgentState rebuilt from event log")

    {:reply, :ok, state}
  end

  # Private helpers

  # Check for snapshot every hour
  @snapshot_check_interval :timer.hours(1)

  defp schedule_snapshot_check do
    Process.send_after(self(), :check_snapshot, @snapshot_check_interval)
  end

  # ETS lookup helper to reduce repeated pattern
  defp ets_get(key, default \\ nil) do
    case :ets.lookup(@table_name, key) do
      [{^key, value}] -> value
      [] -> default
    end
  end
end
