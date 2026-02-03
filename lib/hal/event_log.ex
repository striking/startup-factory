defmodule HAL.EventLog do
  @moduledoc """
  Append-only event log for HAL's autonomous agent state.

  Every action, decision, and outcome is logged to JSONL files.
  Provides complete audit trail and enables event sourcing.

  ## Event Types

  - `task_started` - Agent begins working on a task
  - `task_completed` - Task finished successfully
  - `task_failed` - Task failed after retries
  - `approval_requested` - Human approval requested for an action
  - `approval_approved` - Human approved a pending action
  - `approval_denied` - Human denied a pending action
  - `action_taken` - Agent performed an action
  - `action_failed` - Action failed (will retry or give up)
  - `decision_made` - Agent made a strategic decision
  - `learned` - Agent learned a fact or pattern
  - `strategy_adjusted` - Agent changed approach based on learning
  - `memory_stored` - Important fact saved to memory
  - `goal_set` - New goal established
  - `goal_completed` - Goal achieved

  ## Usage

      # Log an event
      EventLog.log(:task_started, %{
        task: "organize inbox",
        strategy: "create labels by sender",
        context: %{time: "morning", load: "high"}
      })

      # Query recent events
      EventLog.recent(limit: 50)

      # Query by type
      EventLog.by_type(:learned, days_back: 7)

      # Replay all events to rebuild state
      EventLog.replay()
  """

  require Logger

  alias HAL.EventLog.Writer

  @workspace_dir Application.compile_env(:hal, :workspace_dir, "workspace")
  @log_file Path.join([@workspace_dir, "agent-log.jsonl"])
  @snapshot_file Path.join([@workspace_dir, "agent-state-snapshot.json"])
  @snapshot_backup_file Path.join([@workspace_dir, "agent-state-snapshot.backup.json"])

  # Snapshot configuration
  # Create snapshot every N events
  @snapshot_threshold 1000

  @type event_type ::
          :task_started
          | :task_completed
          | :task_failed
          | :approval_requested
          | :approval_approved
          | :approval_denied
          | :action_taken
          | :action_failed
          | :decision_made
          | :learned
          | :strategy_adjusted
          | :memory_stored
          | :goal_set
          | :goal_completed

  @type event :: %{
          timestamp: DateTime.t(),
          event: event_type(),
          data: map(),
          metadata: map()
        }

  @doc """
  Log an event to the append-only log.

  ## Examples

      iex> EventLog.log(:task_started, %{task: "research", strategy: "web search"})
      :ok

      iex> EventLog.log(:learned, %{fact: "IMAP timeouts at 10am", confidence: 0.8})
      :ok
  """
  @spec log(event_type(), map(), keyword()) :: :ok | {:error, term()}
  def log(event_type, data, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, %{})

    event = %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      event: to_string(event_type),
      data: data,
      metadata: metadata
    }

    ensure_log_exists()

    case Jason.encode(event) do
      {:ok, json} ->
        # Use async buffered writer (non-blocking)
        Writer.write(json)
        Logger.debug("Event logged: #{event_type}")
        :ok

      {:error, reason} = error ->
        Logger.error("Failed to encode event: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Get recent events from the log.

  ## Options

  - `:limit` - Max number of events (default: 100)
  - `:days_back` - Only return events from last N days (default: all)

  ## Examples

      iex> EventLog.recent(limit: 50)
      [%{timestamp: ~U[...], event: "task_started", ...}, ...]
  """
  @spec recent(keyword()) :: list(event())
  def recent(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    days_back = Keyword.get(opts, :days_back)

    cutoff =
      if days_back do
        DateTime.utc_now() |> DateTime.add(-days_back * 24 * 3600, :second)
      else
        nil
      end

    read_events()
    |> filter_by_date(cutoff)
    |> Enum.take(-limit)
    |> Enum.reverse()
  end

  @doc """
  Get events by type.

  ## Examples

      iex> EventLog.by_type(:learned, days_back: 7)
      [%{event: "learned", data: %{fact: "..."}, ...}]
  """
  @spec by_type(event_type(), keyword()) :: list(event())
  def by_type(event_type, opts \\ []) do
    days_back = Keyword.get(opts, :days_back)
    limit = Keyword.get(opts, :limit)

    cutoff =
      if days_back do
        DateTime.utc_now() |> DateTime.add(-days_back * 24 * 3600, :second)
      else
        nil
      end

    events =
      read_events()
      |> filter_by_date(cutoff)
      |> Enum.filter(fn event ->
        event["event"] == to_string(event_type)
      end)

    if limit do
      Enum.take(events, -limit) |> Enum.reverse()
    else
      Enum.reverse(events)
    end
  end

  @doc """
  Replay all events to rebuild agent state.

  Returns a map with categorized events:
  - `current_tasks` - Tasks that were started but not completed
  - `completed_tasks` - Successfully completed tasks
  - `failed_tasks` - Tasks that failed
  - `learned_facts` - Facts learned over time
  - `strategies` - Current strategies for different task types
  - `goals` - Active goals

  ## Examples

      iex> EventLog.replay()
      %{
        current_tasks: ["organize inbox"],
        completed_tasks: [%{task: "research competitors", ...}],
        learned_facts: ["IMAP timeouts at 10am", ...],
        strategies: %{"organize inbox" => "create labels by sender"},
        goals: [%{goal: "improve productivity", progress: 0.6}]
      }
  """
  @spec replay() :: map()
  def replay do
    events = read_events()

    Enum.reduce(events, initial_state(), fn event, state ->
      apply_event(event, state)
    end)
  end

  @doc """
  Query events with flexible filtering.

  ## Examples

      iex> EventLog.query(event: "learned", limit: 10)
      [...]

      iex> EventLog.query(contains: "inbox", days_back: 7)
      [...]
  """
  @spec query(keyword()) :: list(event())
  def query(filters) do
    event_type = Keyword.get(filters, :event)
    contains = Keyword.get(filters, :contains)
    days_back = Keyword.get(filters, :days_back)
    limit = Keyword.get(filters, :limit)

    cutoff =
      if days_back do
        DateTime.utc_now() |> DateTime.add(-days_back * 24 * 3600, :second)
      else
        nil
      end

    events =
      read_events()
      |> filter_by_date(cutoff)
      |> filter_by_type(event_type)
      |> filter_by_content(contains)

    if limit do
      Enum.take(events, -limit) |> Enum.reverse()
    else
      Enum.reverse(events)
    end
  end

  # Snapshot Functions

  @doc """
  Creates a snapshot of the current state with the event count.

  The snapshot stores:
  - Full agent state (tasks, facts, strategies, goals)
  - Event count at snapshot time
  - Timestamp

  After snapshotting, only events after this point need to be replayed.

  ## Examples

      iex> EventLog.create_snapshot()
      {:ok, %{event_count: 1000, timestamp: ~U[...]}}
  """
  @spec create_snapshot() :: {:ok, map()} | {:error, term()}
  def create_snapshot do
    events = read_events()
    event_count = length(events)
    state = Enum.reduce(events, initial_state(), &apply_event/2)

    snapshot = %{
      version: 1,
      event_count: event_count,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      state: state
    }

    case Jason.encode(snapshot, pretty: true) do
      {:ok, json} ->
        # Backup existing snapshot before overwriting
        backup_existing_snapshot()

        case File.write(@snapshot_file, json) do
          :ok ->
            Logger.info("Created snapshot at event #{event_count}")
            {:ok, %{event_count: event_count, timestamp: snapshot.timestamp}}

          {:error, reason} = error ->
            Logger.error("Failed to write snapshot: #{inspect(reason)}")
            error
        end

      {:error, reason} = error ->
        Logger.error("Failed to encode snapshot: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Loads state from snapshot and replays only delta events.

  This is much faster than replaying all events when the log is large.

  ## Returns

    * `{:ok, state, stats}` - Success with state and load stats
    * `{:error, reason}` - Error loading snapshot

  Stats include:
    * `:snapshot_events` - Events in snapshot
    * `:delta_events` - Events replayed after snapshot
    * `:total_events` - Total events processed

  ## Examples

      iex> EventLog.load_from_snapshot()
      {:ok, %{current_tasks: [...], ...}, %{snapshot_events: 1000, delta_events: 50}}
  """
  @spec load_from_snapshot() :: {:ok, map(), map()} | {:error, term()}
  def load_from_snapshot do
    case read_snapshot() do
      {:ok, %{"version" => 1, "event_count" => snapshot_count, "state" => snapshot_state}} ->
        # Read all events and replay only those after the snapshot
        all_events = read_events()
        total_count = length(all_events)

        if snapshot_count <= total_count do
          # Replay delta events only
          delta_events = Enum.drop(all_events, snapshot_count)
          delta_count = length(delta_events)

          state = convert_snapshot_state(snapshot_state)
          final_state = Enum.reduce(delta_events, state, &apply_event/2)

          stats = %{
            snapshot_events: snapshot_count,
            delta_events: delta_count,
            total_events: total_count
          }

          Logger.info("Loaded from snapshot: #{snapshot_count} cached + #{delta_count} replayed")
          {:ok, final_state, stats}
        else
          # Snapshot is ahead of log - corrupted, fall back to full replay
          Logger.warning(
            "Snapshot ahead of log (#{snapshot_count} > #{total_count}), doing full replay"
          )

          {:error, :snapshot_ahead_of_log}
        end

      {:ok, %{"version" => version}} ->
        Logger.warning("Unknown snapshot version: #{version}")
        {:error, {:unknown_version, version}}

      {:error, :enoent} ->
        # No snapshot exists, return error so caller can do full replay
        {:error, :no_snapshot}

      {:error, reason} ->
        Logger.warning("Failed to load snapshot: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Replays events using snapshot if available, falling back to full replay.

  This is the preferred way to rebuild state - it automatically uses
  the most efficient method.

  ## Examples

      iex> EventLog.replay_with_snapshot()
      %{current_tasks: [...], learned_facts: [...], ...}
  """
  @spec replay_with_snapshot() :: map()
  def replay_with_snapshot do
    case load_from_snapshot() do
      {:ok, state, _stats} ->
        state

      {:error, _reason} ->
        # Fall back to full replay
        replay()
    end
  end

  @doc """
  Checks if a snapshot should be created based on event count.

  Returns true if events since last snapshot >= threshold.
  """
  @spec should_snapshot?() :: boolean()
  def should_snapshot? do
    total_events = length(read_events())

    case read_snapshot() do
      {:ok, %{"event_count" => snapshot_count}} ->
        total_events - snapshot_count >= @snapshot_threshold

      {:error, _} ->
        # No snapshot exists, create one if we have enough events
        total_events >= @snapshot_threshold
    end
  end

  @doc """
  Returns snapshot threshold (events between snapshots).
  """
  @spec snapshot_threshold() :: pos_integer()
  def snapshot_threshold, do: @snapshot_threshold

  @doc """
  Returns the log file path.
  """
  @spec log_file() :: String.t()
  def log_file, do: @log_file

  @doc """
  Get stats about the event log.

  Returns:
  - Total events
  - Events by type
  - Date range
  - File size

  ## Examples

      iex> EventLog.stats()
      %{
        total_events: 1234,
        by_type: %{"learned" => 45, "task_completed" => 89, ...},
        date_range: {~U[2026-01-01 00:00:00Z], ~U[2026-01-29 10:00:00Z]},
        file_size_kb: 456
      }
  """
  @spec stats() :: map()
  def stats do
    events = read_events()

    by_type =
      events
      |> Enum.group_by(fn e -> e["event"] end)
      |> Map.new(fn {type, events} -> {type, length(events)} end)

    dates =
      events
      |> Enum.map(fn e -> parse_timestamp(e["timestamp"]) end)
      |> Enum.reject(&is_nil/1)

    date_range =
      if Enum.empty?(dates) do
        nil
      else
        {Enum.min(dates), Enum.max(dates)}
      end

    file_size =
      case File.stat(@log_file) do
        {:ok, %{size: size}} -> div(size, 1024)
        _ -> 0
      end

    %{
      total_events: length(events),
      by_type: by_type,
      date_range: date_range,
      file_size_kb: file_size
    }
  end

  # Private Functions

  defp initial_state do
    %{
      current_tasks: [],
      completed_tasks: [],
      failed_tasks: [],
      learned_facts: [],
      strategies: %{},
      goals: [],
      action_history: []
    }
  end

  defp apply_event(%{"event" => "task_started", "data" => data}, state) do
    task = Map.get(data, "task")
    strategy = Map.get(data, "strategy")

    state
    |> Map.update!(:current_tasks, fn tasks -> [task | tasks] end)
    |> maybe_update_strategy(task, strategy)
  end

  defp apply_event(%{"event" => "task_completed", "data" => data}, state) do
    task = Map.get(data, "task")

    state
    |> Map.update!(:current_tasks, fn tasks -> List.delete(tasks, task) end)
    |> Map.update!(:completed_tasks, fn tasks -> [data | tasks] end)
  end

  defp apply_event(%{"event" => "task_failed", "data" => data}, state) do
    task = Map.get(data, "task")

    state
    |> Map.update!(:current_tasks, fn tasks -> List.delete(tasks, task) end)
    |> Map.update!(:failed_tasks, fn tasks -> [data | tasks] end)
  end

  defp apply_event(%{"event" => "learned", "data" => data}, state) do
    fact = Map.get(data, "fact")

    Map.update!(state, :learned_facts, fn facts -> [fact | facts] end)
  end

  defp apply_event(%{"event" => "strategy_adjusted", "data" => data}, state) do
    task = Map.get(data, "task")
    new_strategy = Map.get(data, "new")

    if task && new_strategy do
      Map.update!(state, :strategies, fn strats -> Map.put(strats, task, new_strategy) end)
    else
      state
    end
  end

  defp apply_event(%{"event" => "goal_set", "data" => data}, state) do
    Map.update!(state, :goals, fn goals -> [data | goals] end)
  end

  defp apply_event(%{"event" => "goal_completed", "data" => data}, state) do
    goal_id = Map.get(data, "goal_id")

    Map.update!(state, :goals, fn goals ->
      Enum.reject(goals, fn g -> Map.get(g, "id") == goal_id end)
    end)
  end

  defp apply_event(%{"event" => event_type, "data" => data}, state)
       when event_type in ["action_taken", "action_failed"] do
    Map.update!(state, :action_history, fn history -> [data | history] end)
  end

  defp apply_event(_event, state), do: state

  defp maybe_update_strategy(state, _task, nil), do: state

  defp maybe_update_strategy(state, task, strategy) do
    Map.update!(state, :strategies, fn strats -> Map.put(strats, task, strategy) end)
  end

  defp read_events do
    case File.read(@log_file) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.map(&parse_json/1)
        |> Enum.reject(&is_nil/1)

      {:error, :enoent} ->
        []

      {:error, reason} ->
        Logger.warning("Failed to read event log: #{inspect(reason)}")
        []
    end
  end

  defp parse_json(line) do
    case Jason.decode(line) do
      {:ok, event} -> event
      {:error, _} -> nil
    end
  end

  defp filter_by_date(events, nil), do: events

  defp filter_by_date(events, cutoff) do
    Enum.filter(events, fn event ->
      case parse_timestamp(event["timestamp"]) do
        nil -> false
        timestamp -> DateTime.compare(timestamp, cutoff) == :gt
      end
    end)
  end

  defp filter_by_type(events, nil), do: events

  defp filter_by_type(events, event_type) do
    Enum.filter(events, fn event ->
      event["event"] == to_string(event_type)
    end)
  end

  defp filter_by_content(events, nil), do: events

  defp filter_by_content(events, search_term) do
    Enum.filter(events, fn event ->
      json = Jason.encode!(event)
      String.contains?(String.downcase(json), String.downcase(search_term))
    end)
  end

  defp parse_timestamp(nil), do: nil

  defp parse_timestamp(timestamp_str) do
    case DateTime.from_iso8601(timestamp_str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp ensure_log_exists do
    dir = Path.dirname(@log_file)
    File.mkdir_p!(dir)

    unless File.exists?(@log_file) do
      File.write!(@log_file, "")
    end
  end

  # Snapshot helpers

  defp read_snapshot do
    case File.read(@snapshot_file) do
      {:ok, content} ->
        Jason.decode(content)

      {:error, :enoent} ->
        {:error, :enoent}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp backup_existing_snapshot do
    if File.exists?(@snapshot_file) do
      case File.copy(@snapshot_file, @snapshot_backup_file) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to backup snapshot: #{inspect(reason)}")
          :ok
      end
    end
  end

  # Convert snapshot state (string keys) back to the expected format
  defp convert_snapshot_state(state) when is_map(state) do
    %{
      current_tasks: Map.get(state, "current_tasks", []),
      completed_tasks: Map.get(state, "completed_tasks", []),
      failed_tasks: Map.get(state, "failed_tasks", []),
      learned_facts: Map.get(state, "learned_facts", []),
      strategies: Map.get(state, "strategies", %{}),
      goals: Map.get(state, "goals", []),
      action_history: Map.get(state, "action_history", [])
    }
  end
end
