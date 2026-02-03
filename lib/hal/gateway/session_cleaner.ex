defmodule Hal.Gateway.SessionCleaner do
  @moduledoc """
  GenServer for cleaning up archived conversation sessions.

  The SessionCleaner periodically scans for sessions that have been explicitly
  archived by the user and removes them after a grace period (default: 7 days).
  When cleaning up an archived session, it:
  1. Looks up any associated SessionServer GenServer via Registry
  2. Stops the GenServer gracefully with `GenServer.stop(pid, :normal)`
  3. Deletes the session from the database

  Sessions are only cleaned up when:
  - Status is "archived" (explicitly closed by user)
  - AND updated_at timestamp is older than the grace period (default: 7 days)

  ## Configuration Options

    * `:name` - GenServer name for registration (required)
    * `:registry_name` - Name of the session Registry for lookups (required)
    * `:grace_period_days` - Days to wait before deleting archived sessions (default: 7)
    * `:cleanup_interval_ms` - Milliseconds between cleanup runs (default: 1 hour)

  ## Usage

      # Start with default 7-day grace period
      {:ok, pid} = SessionCleaner.start_link(
        name: Hal.Gateway.SessionCleaner,
        registry_name: Hal.SessionRegistry
      )

      # Start with custom 3-day grace period
      {:ok, pid} = SessionCleaner.start_link(
        name: Hal.Gateway.SessionCleaner,
        registry_name: Hal.SessionRegistry,
        grace_period_days: 3
      )

      # Manually trigger cleanup
      {:ok, stats} = SessionCleaner.cleanup_now(pid)

      # Get cleanup statistics
      stats = SessionCleaner.get_stats(pid)

  ## Integration

  This module is designed to be added to the Gateway supervision tree
  but is kept separate to allow testing and manual operation.
  """

  use GenServer
  require Logger

  alias Hal.Gateway.Session, as: SessionSchema
  alias Hal.Repo

  import Ecto.Query

  # Default cleanup interval: 1 hour
  @default_cleanup_interval_ms 60 * 60 * 1000

  # Default grace period: 7 days before deleting archived sessions
  @default_grace_period_days 7

  defstruct [
    :registry_name,
    :grace_period_days,
    :cleanup_interval_ms,
    :last_cleanup_at,
    total_deleted: 0,
    total_servers_stopped: 0,
    cleanup_count: 0
  ]

  # Client API

  @doc """
  Starts the SessionCleaner GenServer.

  ## Options

    * `:name` - GenServer name (required)
    * `:registry_name` - Name of the session Registry (required)
    * `:grace_period_days` - Days to wait before deleting archived sessions (default: 7)
    * `:cleanup_interval_ms` - Milliseconds between cleanup runs (default: 1 hour)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Manually triggers a cleanup of archived sessions.

  Returns `{:ok, stats}` with cleanup statistics:
    * `:deleted_count` - Number of archived sessions deleted
    * `:servers_stopped` - Number of SessionServer GenServers stopped
  """
  @spec cleanup_now(GenServer.server()) :: {:ok, map()}
  def cleanup_now(server) do
    GenServer.call(server, :cleanup_now)
  end

  @doc """
  Returns statistics about cleanup operations.

  Returns a map with:
    * `:last_cleanup_at` - DateTime of last cleanup (or nil if never run)
    * `:total_deleted` - Total archived sessions deleted since start
    * `:total_servers_stopped` - Total GenServers stopped since start
    * `:cleanup_count` - Number of cleanup operations performed
  """
  @spec get_stats(GenServer.server()) :: map()
  def get_stats(server) do
    GenServer.call(server, :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    registry_name = Keyword.fetch!(opts, :registry_name)
    grace_period = Keyword.get(opts, :grace_period_days, @default_grace_period_days)
    cleanup_interval = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %__MODULE__{
      registry_name: registry_name,
      grace_period_days: grace_period,
      cleanup_interval_ms: cleanup_interval,
      last_cleanup_at: nil,
      total_deleted: 0,
      total_servers_stopped: 0,
      cleanup_count: 0
    }

    # Schedule the first cleanup
    schedule_cleanup(cleanup_interval)

    Logger.info(
      "SessionCleaner started with #{grace_period} day grace period, cleanup every #{cleanup_interval}ms"
    )

    {:ok, state}
  end

  @impl true
  def handle_call(:cleanup_now, _from, state) do
    {stats, new_state} = do_cleanup(state)
    {:reply, {:ok, stats}, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      last_cleanup_at: state.last_cleanup_at,
      total_deleted: state.total_deleted,
      total_servers_stopped: state.total_servers_stopped,
      cleanup_count: state.cleanup_count
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:cleanup_archived_sessions, state) do
    {_stats, new_state} = do_cleanup(state)

    # Schedule the next cleanup
    schedule_cleanup(state.cleanup_interval_ms)

    {:noreply, new_state}
  end

  # Private Functions

  defp schedule_cleanup(interval_ms) do
    Process.send_after(self(), :cleanup_archived_sessions, interval_ms)
  end

  defp do_cleanup(state) do
    # Calculate cutoff: archived sessions older than grace period
    cutoff = DateTime.add(DateTime.utc_now(), -state.grace_period_days, :day)

    Logger.info("Starting session cleanup for archived sessions older than #{cutoff}")

    # Find all archived sessions with updated_at before the cutoff
    archived_sessions =
      from(s in SessionSchema,
        where: s.status == "archived" and s.updated_at < ^cutoff,
        select: s
      )
      |> Repo.all()

    Logger.info("Found #{length(archived_sessions)} archived sessions to clean up")

    # Process each archived session
    {deleted_count, servers_stopped} =
      Enum.reduce(archived_sessions, {0, 0}, fn session, {del_count, stop_count} ->
        # Try to stop the associated GenServer
        stopped = stop_session_server(state.registry_name, session)

        # Delete the session from the database
        case delete_session(session) do
          {:ok, _} ->
            Logger.debug("Deleted archived session #{session.id}")
            {del_count + 1, stop_count + if(stopped, do: 1, else: 0)}

          {:error, reason} ->
            Logger.warning("Failed to delete session #{session.id}: #{inspect(reason)}")
            {del_count, stop_count}
        end
      end)

    stats = %{
      deleted_count: deleted_count,
      servers_stopped: servers_stopped
    }

    new_state = %{
      state
      | last_cleanup_at: DateTime.utc_now(),
        total_deleted: state.total_deleted + deleted_count,
        total_servers_stopped: state.total_servers_stopped + servers_stopped,
        cleanup_count: state.cleanup_count + 1
    }

    Logger.info("Cleanup complete: #{deleted_count} deleted, #{servers_stopped} servers stopped")

    {stats, new_state}
  end

  defp stop_session_server(registry_name, session) do
    # The SessionServer registers with key {channel_type, channel_id, user_id}
    key = {session.channel_type, session.channel_id, session.user_id}

    case Registry.lookup(registry_name, key) do
      [{pid, _}] when is_pid(pid) ->
        if Process.alive?(pid) do
          Logger.debug("Stopping SessionServer for session #{session.id}")

          try do
            GenServer.stop(pid, :normal, 5000)
            true
          catch
            :exit, reason ->
              Logger.warning("Failed to stop SessionServer #{inspect(pid)}: #{inspect(reason)}")
              false
          end
        else
          false
        end

      [] ->
        # No GenServer running for this session
        false
    end
  end

  defp delete_session(session) do
    Repo.delete(session)
  end
end
