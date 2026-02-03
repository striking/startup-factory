defmodule Hal.Watchdog do
  @moduledoc """
  GenServer for detecting and handling hung processes.

  The Watchdog monitors registered processes and expects them to send
  periodic heartbeats. If a process fails to send a heartbeat within
  its configured timeout period, the Watchdog will kill it.

  ## Usage

      # Start the watchdog (typically in supervision tree)
      {:ok, watchdog} = Hal.Watchdog.start_link([])

      # Register a process to be monitored with a 30-second timeout
      Hal.Watchdog.monitor(watchdog, some_pid, 30_000)

      # Process sends heartbeats periodically
      Hal.Watchdog.heartbeat(watchdog, self())

      # Optionally unmonitor a process
      Hal.Watchdog.unmonitor(watchdog, some_pid)

  ## State Structure

      %{
        monitored_processes: %{pid => timeout_ms},
        last_seen: %{pid => timestamp_ms}
      }
  """

  use GenServer
  require Logger

  # 10 seconds
  @default_check_interval 10_000

  # Client API

  @doc """
  Starts the Watchdog GenServer.

  ## Options

    * `:name` - Optional name to register the process
    * `:check_interval` - Interval in ms between heartbeat checks (default: 10_000)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Registers a process for monitoring with a specified timeout.

  The process must send heartbeats within the timeout period or it will be killed.

  ## Parameters

    * `server` - The Watchdog pid or registered name
    * `pid` - The process to monitor
    * `timeout_ms` - Maximum time in milliseconds between heartbeats
  """
  @spec monitor(GenServer.server(), pid(), pos_integer()) :: :ok
  def monitor(server, pid, timeout_ms)
      when is_pid(pid) and is_integer(timeout_ms) and timeout_ms > 0 do
    GenServer.call(server, {:monitor, pid, timeout_ms})
  end

  @doc """
  Sends a heartbeat from a monitored process.

  Updates the last_seen timestamp for the process.

  ## Parameters

    * `server` - The Watchdog pid or registered name
    * `pid` - The process sending the heartbeat
  """
  @spec heartbeat(GenServer.server(), pid()) :: :ok | {:error, :not_monitored}
  def heartbeat(server, pid) when is_pid(pid) do
    GenServer.call(server, {:heartbeat, pid})
  end

  @doc """
  Removes a process from monitoring.

  ## Parameters

    * `server` - The Watchdog pid or registered name
    * `pid` - The process to stop monitoring
  """
  @spec unmonitor(GenServer.server(), pid()) :: :ok
  def unmonitor(server, pid) when is_pid(pid) do
    GenServer.call(server, {:unmonitor, pid})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    check_interval = Keyword.get(opts, :check_interval, @default_check_interval)

    state = %{
      monitored_processes: %{},
      last_seen: %{},
      check_interval: check_interval,
      monitors: %{}
    }

    # Schedule first heartbeat check
    schedule_check(check_interval)

    {:ok, state}
  end

  @impl true
  def handle_call({:monitor, pid, timeout_ms}, _from, state) do
    # Set up process monitor to detect normal exits
    ref = Process.monitor(pid)
    now = System.monotonic_time(:millisecond)

    new_state = %{
      state
      | monitored_processes: Map.put(state.monitored_processes, pid, timeout_ms),
        last_seen: Map.put(state.last_seen, pid, now),
        monitors: Map.put(state.monitors, pid, ref)
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:heartbeat, pid}, _from, state) do
    if Map.has_key?(state.monitored_processes, pid) do
      now = System.monotonic_time(:millisecond)
      new_state = %{state | last_seen: Map.put(state.last_seen, pid, now)}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_monitored}, state}
    end
  end

  @impl true
  def handle_call({:unmonitor, pid}, _from, state) do
    new_state = cleanup_process(state, pid)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:check_heartbeats, state) do
    now = System.monotonic_time(:millisecond)
    new_state = check_and_kill_hung_processes(state, now)

    # Schedule next check
    schedule_check(state.check_interval)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Process exited - clean up monitoring state
    new_state = cleanup_process(state, pid)
    {:noreply, new_state}
  end

  # Private Functions

  defp schedule_check(interval) do
    Process.send_after(self(), :check_heartbeats, interval)
  end

  defp check_and_kill_hung_processes(state, now) do
    hung_pids =
      Enum.filter(state.monitored_processes, fn {pid, timeout_ms} ->
        last_seen = Map.get(state.last_seen, pid, 0)
        elapsed = now - last_seen
        elapsed > timeout_ms
      end)
      |> Enum.map(fn {pid, _timeout} -> pid end)

    # Kill hung processes
    Enum.each(hung_pids, fn pid ->
      Logger.warning("Watchdog killing hung process: #{inspect(pid)}")
      Process.exit(pid, :kill)
    end)

    # Note: cleanup will happen when we receive :DOWN messages
    state
  end

  defp cleanup_process(state, pid) do
    # Demonitor if we have a reference
    case Map.get(state.monitors, pid) do
      nil -> :ok
      ref -> Process.demonitor(ref, [:flush])
    end

    %{
      state
      | monitored_processes: Map.delete(state.monitored_processes, pid),
        last_seen: Map.delete(state.last_seen, pid),
        monitors: Map.delete(state.monitors, pid)
    }
  end
end
