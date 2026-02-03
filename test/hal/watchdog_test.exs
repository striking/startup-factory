defmodule Hal.WatchdogTest do
  use ExUnit.Case, async: true

  alias Hal.Watchdog

  describe "start_link/1" do
    test "starts the watchdog GenServer with default state" do
      {:ok, pid} = Watchdog.start_link(name: :test_watchdog_startup)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "monitor/2" do
    setup do
      {:ok, watchdog} = Watchdog.start_link(name: :test_watchdog_monitor)
      on_exit(fn -> if Process.alive?(watchdog), do: GenServer.stop(watchdog) end)
      %{watchdog: watchdog}
    end

    test "registers a process for monitoring", %{watchdog: watchdog} do
      test_pid = spawn(fn -> Process.sleep(:infinity) end)

      assert :ok = Watchdog.monitor(watchdog, test_pid, 5000)

      # Verify process is being monitored by checking internal state
      state = :sys.get_state(watchdog)
      assert Map.has_key?(state.monitored_processes, test_pid)
      assert state.monitored_processes[test_pid] == 5000

      Process.exit(test_pid, :kill)
    end

    test "sets initial last_seen timestamp when registering", %{watchdog: watchdog} do
      test_pid = spawn(fn -> Process.sleep(:infinity) end)
      before_monitor = System.monotonic_time(:millisecond)

      :ok = Watchdog.monitor(watchdog, test_pid, 5000)

      state = :sys.get_state(watchdog)
      after_monitor = System.monotonic_time(:millisecond)

      last_seen = state.last_seen[test_pid]
      assert last_seen >= before_monitor
      assert last_seen <= after_monitor

      Process.exit(test_pid, :kill)
    end
  end

  describe "heartbeat/1" do
    setup do
      {:ok, watchdog} = Watchdog.start_link(name: :test_watchdog_heartbeat)
      on_exit(fn -> if Process.alive?(watchdog), do: GenServer.stop(watchdog) end)
      %{watchdog: watchdog}
    end

    test "updates last_seen timestamp for monitored process", %{watchdog: watchdog} do
      test_pid = spawn(fn -> Process.sleep(:infinity) end)

      # Register and get initial timestamp
      :ok = Watchdog.monitor(watchdog, test_pid, 5000)
      state_before = :sys.get_state(watchdog)
      initial_last_seen = state_before.last_seen[test_pid]

      # Wait a bit to ensure timestamp difference
      Process.sleep(10)

      # Send heartbeat
      :ok = Watchdog.heartbeat(watchdog, test_pid)

      state_after = :sys.get_state(watchdog)
      new_last_seen = state_after.last_seen[test_pid]

      assert new_last_seen > initial_last_seen

      Process.exit(test_pid, :kill)
    end

    test "returns error for unmonitored process", %{watchdog: watchdog} do
      unmonitored_pid = spawn(fn -> Process.sleep(:infinity) end)

      assert {:error, :not_monitored} = Watchdog.heartbeat(watchdog, unmonitored_pid)

      Process.exit(unmonitored_pid, :kill)
    end
  end

  describe "hung process detection" do
    setup do
      # Use a very short check interval for testing
      {:ok, watchdog} = Watchdog.start_link(name: :test_watchdog_hung, check_interval: 50)
      on_exit(fn -> if Process.alive?(watchdog), do: GenServer.stop(watchdog) end)
      %{watchdog: watchdog}
    end

    test "kills process that hasn't sent heartbeat within timeout", %{watchdog: watchdog} do
      # Create a process that we'll let timeout
      test_pid = spawn(fn -> Process.sleep(:infinity) end)

      # Monitor with a very short timeout (100ms)
      :ok = Watchdog.monitor(watchdog, test_pid, 100)

      # Verify process is alive initially
      assert Process.alive?(test_pid)

      # Wait for the timeout + check interval to pass
      Process.sleep(200)

      # Process should be killed
      refute Process.alive?(test_pid)
    end

    test "does not kill process that sends heartbeats", %{watchdog: watchdog} do
      test_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      # Monitor with short timeout
      :ok = Watchdog.monitor(watchdog, test_pid, 100)

      # Send heartbeats to keep process alive
      Enum.each(1..5, fn _ ->
        Process.sleep(50)
        Watchdog.heartbeat(watchdog, test_pid)
      end)

      # Process should still be alive
      assert Process.alive?(test_pid)

      send(test_pid, :stop)
    end
  end

  describe "process exit cleanup" do
    setup do
      {:ok, watchdog} = Watchdog.start_link(name: :test_watchdog_cleanup)
      on_exit(fn -> if Process.alive?(watchdog), do: GenServer.stop(watchdog) end)
      %{watchdog: watchdog}
    end

    test "cleans up monitoring state when process exits normally", %{watchdog: watchdog} do
      test_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      :ok = Watchdog.monitor(watchdog, test_pid, 5000)

      # Verify process is being monitored
      state_before = :sys.get_state(watchdog)
      assert Map.has_key?(state_before.monitored_processes, test_pid)

      # Stop the process
      send(test_pid, :stop)
      Process.sleep(50)

      # Verify monitoring state is cleaned up
      state_after = :sys.get_state(watchdog)
      refute Map.has_key?(state_after.monitored_processes, test_pid)
      refute Map.has_key?(state_after.last_seen, test_pid)
    end

    test "cleans up monitoring state when process crashes", %{watchdog: watchdog} do
      test_pid = spawn(fn -> Process.sleep(:infinity) end)

      :ok = Watchdog.monitor(watchdog, test_pid, 5000)

      # Verify process is being monitored
      state_before = :sys.get_state(watchdog)
      assert Map.has_key?(state_before.monitored_processes, test_pid)

      # Kill the process
      Process.exit(test_pid, :kill)
      Process.sleep(50)

      # Verify monitoring state is cleaned up
      state_after = :sys.get_state(watchdog)
      refute Map.has_key?(state_after.monitored_processes, test_pid)
      refute Map.has_key?(state_after.last_seen, test_pid)
    end
  end

  describe "multiple processes" do
    setup do
      {:ok, watchdog} = Watchdog.start_link(name: :test_watchdog_multi)
      on_exit(fn -> if Process.alive?(watchdog), do: GenServer.stop(watchdog) end)
      %{watchdog: watchdog}
    end

    test "monitors multiple processes simultaneously", %{watchdog: watchdog} do
      pids = for _ <- 1..5, do: spawn(fn -> Process.sleep(:infinity) end)

      # Register all processes with different timeouts
      Enum.with_index(pids, fn pid, index ->
        timeout = 1000 * (index + 1)
        :ok = Watchdog.monitor(watchdog, pid, timeout)
      end)

      state = :sys.get_state(watchdog)

      # Verify all processes are being monitored
      assert map_size(state.monitored_processes) == 5
      assert map_size(state.last_seen) == 5

      Enum.each(pids, fn pid ->
        assert Map.has_key?(state.monitored_processes, pid)
        assert Map.has_key?(state.last_seen, pid)
      end)

      # Cleanup
      Enum.each(pids, fn pid -> Process.exit(pid, :kill) end)
    end

    test "handles heartbeats from multiple processes independently", %{watchdog: watchdog} do
      pid1 = spawn(fn -> Process.sleep(:infinity) end)
      pid2 = spawn(fn -> Process.sleep(:infinity) end)

      :ok = Watchdog.monitor(watchdog, pid1, 5000)
      :ok = Watchdog.monitor(watchdog, pid2, 5000)

      state1 = :sys.get_state(watchdog)
      initial_last_seen_1 = state1.last_seen[pid1]
      initial_last_seen_2 = state1.last_seen[pid2]

      Process.sleep(10)

      # Only pid1 sends heartbeat
      :ok = Watchdog.heartbeat(watchdog, pid1)

      state2 = :sys.get_state(watchdog)

      # pid1's last_seen should be updated
      assert state2.last_seen[pid1] > initial_last_seen_1

      # pid2's last_seen should remain unchanged
      assert state2.last_seen[pid2] == initial_last_seen_2

      # Cleanup
      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end
  end

  describe "unmonitor/1" do
    setup do
      {:ok, watchdog} = Watchdog.start_link(name: :test_watchdog_unmonitor)
      on_exit(fn -> if Process.alive?(watchdog), do: GenServer.stop(watchdog) end)
      %{watchdog: watchdog}
    end

    test "removes process from monitoring", %{watchdog: watchdog} do
      test_pid = spawn(fn -> Process.sleep(:infinity) end)

      :ok = Watchdog.monitor(watchdog, test_pid, 5000)

      state_before = :sys.get_state(watchdog)
      assert Map.has_key?(state_before.monitored_processes, test_pid)

      :ok = Watchdog.unmonitor(watchdog, test_pid)

      state_after = :sys.get_state(watchdog)
      refute Map.has_key?(state_after.monitored_processes, test_pid)
      refute Map.has_key?(state_after.last_seen, test_pid)

      Process.exit(test_pid, :kill)
    end
  end
end
