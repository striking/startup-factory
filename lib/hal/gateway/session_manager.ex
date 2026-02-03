defmodule Hal.Gateway.SessionManager do
  @moduledoc """
  GenServer managing all active conversation sessions.

  The SessionManager is responsible for:
  - Creating new sessions (spawning SessionServer GenServers on-demand)
  - Retrieving existing sessions (via Registry lookup)
  - Tracking all active sessions

  ## Session Lifecycle

  Sessions use a spawn-on-demand pattern:
  - Sessions start when first message arrives via DynamicSupervisor
  - Sessions auto-terminate after 30 minutes of inactivity
  - Session state is persisted to database before termination
  - Session state is loaded from database on spawn

  ## Session Lookup

  Sessions are uniquely identified by the tuple `{channel_type, channel_id, user_id}`.
  The SessionManager uses a Registry for O(1) lookups.

  ## Usage

      # Get or create a session
      {:ok, session_pid} = SessionManager.get_or_create_session(
        Hal.Gateway.SessionManager,
        "telegram",
        "chat_123",
        user_id
      )

      # List all active sessions
      sessions = SessionManager.list_sessions(Hal.Gateway.SessionManager)

      # Get a specific session
      session_pid = SessionManager.get_session(
        Hal.Gateway.SessionManager,
        "telegram",
        "chat_123",
        user_id
      )
  """

  use GenServer
  require Logger

  alias Hal.Gateway.Session, as: SessionSchema
  alias Hal.Gateway.SessionServer
  alias Hal.Repo

  import Ecto.Query

  @type session_key :: {String.t(), String.t(), String.t()}

  # LRU cache configuration
  # Maximum idle sessions to keep in memory
  @max_idle_sessions 100
  # Check for eviction every 5 minutes
  @lru_check_interval :timer.minutes(5)

  defstruct [:registry_name, :dynamic_supervisor_name, :lru_table, sessions: %{}]

  # Client API

  @doc """
  Starts the SessionManager.

  ## Options

    * `:name` - The name to register the GenServer under
    * `:registry_name` - Name of the Registry for session lookups
    * `:dynamic_supervisor_name` - Name of the DynamicSupervisor for spawning sessions
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets an existing session or creates a new one.

  Returns `{:ok, pid}` where `pid` is the SessionServer process for the session.
  """
  @spec get_or_create_session(GenServer.server(), String.t(), String.t(), String.t()) ::
          {:ok, pid()} | {:error, term()}
  def get_or_create_session(server, channel_type, channel_id, user_id) do
    GenServer.call(server, {:get_or_create_session, channel_type, channel_id, user_id})
  end

  @doc """
  Gets an existing session if it exists.

  Returns the session PID or `nil` if not found.
  """
  @spec get_session(GenServer.server(), String.t(), String.t(), String.t()) :: pid() | nil
  def get_session(server, channel_type, channel_id, user_id) do
    GenServer.call(server, {:get_session, channel_type, channel_id, user_id})
  end

  @doc """
  Lists all active session PIDs.
  """
  @spec list_sessions(GenServer.server()) :: [pid()]
  def list_sessions(server) do
    GenServer.call(server, :list_sessions)
  end

  @doc """
  Returns count of currently active sessions.
  Used by Heartbeat to determine if user is active.
  """
  @spec count_active_sessions() :: non_neg_integer()
  def count_active_sessions do
    # Use the DynamicSupervisor directly to avoid needing GenServer call
    # Handle case where supervisor isn't started (e.g., in tests)
    try do
      DynamicSupervisor.count_children(Hal.Gateway.SessionSupervisor)
      |> Map.get(:active, 0)
    catch
      :exit, _ -> 0
    end
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    registry_name = Keyword.fetch!(opts, :registry_name)
    supervisor_name = Keyword.fetch!(opts, :dynamic_supervisor_name)

    # Create ETS table for LRU tracking
    # Stores {session_key, last_access_time, pid}
    lru_table = :ets.new(:session_lru, [:set, :public])

    state = %__MODULE__{
      registry_name: registry_name,
      dynamic_supervisor_name: supervisor_name,
      lru_table: lru_table,
      sessions: %{}
    }

    # Schedule periodic LRU eviction check
    schedule_lru_check()

    Logger.info(
      "SessionManager started with spawn-on-demand + LRU caching (max #{@max_idle_sessions} idle)"
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:get_or_create_session, channel_type, channel_id, user_id}, _from, state) do
    key = {channel_type, channel_id, user_id}

    case lookup_session(state.registry_name, key) do
      {:ok, pid} ->
        # Update LRU access time
        touch_lru(state.lru_table, key, pid)
        {:reply, {:ok, pid}, state}

      :not_found ->
        case create_session(state, channel_type, channel_id, user_id) do
          {:ok, pid} ->
            # Track in LRU
            touch_lru(state.lru_table, key, pid)
            {:reply, {:ok, pid}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:get_session, channel_type, channel_id, user_id}, _from, state) do
    key = {channel_type, channel_id, user_id}

    result =
      case lookup_session(state.registry_name, key) do
        {:ok, pid} -> pid
        :not_found -> nil
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_sessions, _from, state) do
    sessions =
      Registry.select(state.registry_name, [{{:"$1", :"$2", :"$3"}, [], [:"$2"]}])

    {:reply, sessions, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Session process died - remove from LRU and it will be recreated on next request
    Logger.debug("Session process #{inspect(pid)} terminated, reason: #{inspect(reason)}")
    remove_from_lru_by_pid(state.lru_table, pid)
    {:noreply, state}
  end

  @impl true
  def handle_info(:lru_check, state) do
    # Evict least recently used idle sessions if over limit
    evict_lru_sessions(state)
    schedule_lru_check()
    {:noreply, state}
  end

  # Private Functions

  defp lookup_session(registry_name, key) do
    case Registry.lookup(registry_name, key) do
      [{pid, _}] when is_pid(pid) ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          :not_found
        end

      [] ->
        :not_found
    end
  end

  defp create_session(state, channel_type, channel_id, user_id) do
    # First, ensure the session exists in the database
    session_record = get_or_create_session_record(channel_type, channel_id, user_id)

    case session_record do
      {:ok, session} ->
        start_session_server(state, session)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_or_create_session_record(channel_type, channel_id, user_id) do
    # Try to find existing session
    query =
      from s in SessionSchema,
        where:
          s.channel_type == ^channel_type and
            s.channel_id == ^channel_id and
            s.user_id == ^user_id and
            s.status == "active"

    case Repo.one(query) do
      nil ->
        # Create new session
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        %SessionSchema{}
        |> SessionSchema.changeset(%{
          channel_type: channel_type,
          channel_id: channel_id,
          user_id: user_id,
          last_activity: now,
          status: "active"
        })
        |> Repo.insert()

      session ->
        {:ok, session}
    end
  end

  defp start_session_server(state, session) do
    child_spec = {
      SessionServer,
      session_id: session.id,
      channel_type: session.channel_type,
      channel_id: session.channel_id,
      user_id: session.user_id,
      claude_session_id: session.claude_session_id,
      registry_name: state.registry_name
    }

    case DynamicSupervisor.start_child(state.dynamic_supervisor_name, child_spec) do
      {:ok, pid} ->
        # Monitor the session process
        Process.monitor(pid)
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start session server: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # LRU Cache Management

  defp schedule_lru_check do
    Process.send_after(self(), :lru_check, @lru_check_interval)
  end

  defp touch_lru(table, key, pid) do
    now = System.monotonic_time(:millisecond)
    :ets.insert(table, {key, now, pid})
  end

  defp remove_from_lru_by_pid(table, pid) do
    # Find and remove entries with this pid
    :ets.match_delete(table, {:_, :_, pid})
  end

  defp evict_lru_sessions(state) do
    # Get all idle sessions
    idle_sessions =
      :ets.tab2list(state.lru_table)
      |> Enum.filter(fn {_key, _time, pid} ->
        # Check if session is idle
        try do
          SessionServer.is_idle?(pid)
        catch
          :exit, _ -> false
        end
      end)
      |> Enum.sort_by(fn {_key, time, _pid} -> time end)

    # If over limit, evict oldest idle sessions
    count_to_evict = length(idle_sessions) - @max_idle_sessions

    if count_to_evict > 0 do
      sessions_to_evict = Enum.take(idle_sessions, count_to_evict)

      Enum.each(sessions_to_evict, fn {key, _time, pid} ->
        Logger.info("Evicting idle session: #{inspect(key)}")
        # Stop the session (it will flush to DB before terminating)
        try do
          DynamicSupervisor.terminate_child(state.dynamic_supervisor_name, pid)
        catch
          :exit, _ -> :ok
        end

        :ets.delete(state.lru_table, key)
      end)

      Logger.info(
        "Evicted #{count_to_evict} idle sessions, #{length(idle_sessions) - count_to_evict} remaining"
      )
    end
  end
end
