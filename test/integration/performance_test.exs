defmodule HAL.Integration.PerformanceTest do
  @moduledoc """
  Performance and load tests for HAL.

  Tests:
  - 50 concurrent conversations
  - Memory usage under load
  - Response latency metrics
  - Database connection pooling

  These tests may take several minutes to complete.

  Run with: mix test test/integration/performance_test.exs --include integration --include slow
  """

  use Hal.DataCase, async: false

  alias Hal.Accounts.User
  alias Hal.Gateway.{Session, SessionServer}

  @moduletag :integration
  @moduletag :slow
  @moduletag timeout: 600_000

  describe "concurrent conversations" do
    @tag :performance
    test "handles 50 concurrent conversations without degradation" do
      # Create 50 users and sessions
      sessions = create_test_sessions(50)

      # Track metrics
      metrics = %{
        start_time: System.monotonic_time(:millisecond),
        response_times: :ets.new(:response_times, [:bag, :public]),
        errors: :counters.new(1, [:atomics])
      }

      # Mock AI with slight delay to simulate real behavior
      mock_ai = fn _session_id, content, _opts ->
        # Simulate varying response times (50-200ms)
        Process.sleep(50 + :rand.uniform(150))
        {:ok, %{result: "Response to: #{content}"}, "session_#{System.unique_integer()}"}
      end

      # Start all sessions concurrently
      tasks =
        Enum.map(sessions, fn session ->
          Task.async(fn ->
            start_time = System.monotonic_time(:millisecond)

            result =
              with {:ok, pid} <- start_session_server(session),
                   {:ok, response} <-
                     SessionServer.handle_message(pid, "Test message", ai_client: mock_ai) do
                end_time = System.monotonic_time(:millisecond)
                :ets.insert(metrics.response_times, {:time, end_time - start_time})
                {:ok, response}
              else
                error ->
                  :counters.add(metrics.errors, 1, 1)
                  error
              end

            result
          end)
        end)

      # Wait for all tasks (with generous timeout)
      results = Task.await_many(tasks, 120_000)

      # Calculate metrics
      total_time = System.monotonic_time(:millisecond) - metrics.start_time
      error_count = :counters.get(metrics.errors, 1)

      times = :ets.tab2list(metrics.response_times) |> Enum.map(&elem(&1, 1))
      avg_response_time = if length(times) > 0, do: Enum.sum(times) / length(times), else: 0
      max_response_time = if length(times) > 0, do: Enum.max(times), else: 0
      min_response_time = if length(times) > 0, do: Enum.min(times), else: 0

      # Cleanup
      :ets.delete(metrics.response_times)

      # Report metrics
      IO.puts("""

      === Performance Test Results ===
      Total sessions: 50
      Total time: #{total_time}ms
      Successful: #{length(results) - error_count}
      Errors: #{error_count}
      Avg response time: #{Float.round(avg_response_time, 2)}ms
      Min response time: #{min_response_time}ms
      Max response time: #{max_response_time}ms
      ================================
      """)

      # Assertions
      # At least 90% success rate
      success_rate = (length(results) - error_count) / length(results) * 100
      assert success_rate >= 90, "Success rate too low: #{success_rate}%"

      # Average response time should be reasonable (< 5 seconds per PRD)
      assert avg_response_time < 5_000, "Average response time too high: #{avg_response_time}ms"
    end
  end

  describe "memory usage" do
    @tag :performance
    test "memory usage stays within bounds under load" do
      # Get baseline memory
      :erlang.garbage_collect()
      baseline_memory = :erlang.memory(:total)

      # Create many sessions
      sessions = create_test_sessions(20)

      # Start all session servers
      pids =
        Enum.map(sessions, fn session ->
          {:ok, pid} = start_session_server(session)
          pid
        end)

      # Add messages to each session
      mock_ai = fn _session_id, _content, _opts ->
        {:ok, %{result: String.duplicate("x", 1000)}, "session_123"}
      end

      for pid <- pids do
        for i <- 1..10 do
          SessionServer.handle_message(pid, "Message #{i}", ai_client: mock_ai)
        end
      end

      # Force garbage collection
      :erlang.garbage_collect()

      # Measure memory after load
      loaded_memory = :erlang.memory(:total)
      memory_increase = loaded_memory - baseline_memory

      # Report
      IO.puts("""

      === Memory Usage Test ===
      Baseline: #{div(baseline_memory, 1024 * 1024)}MB
      After load: #{div(loaded_memory, 1024 * 1024)}MB
      Increase: #{div(memory_increase, 1024 * 1024)}MB
      =========================
      """)

      # Memory increase should be < 500MB per PRD (for 10 active sessions)
      # We're testing 20 sessions with 10 messages each
      assert memory_increase < 500 * 1024 * 1024,
             "Memory increase too high: #{div(memory_increase, 1024 * 1024)}MB"
    end
  end

  describe "response latency" do
    @tag :performance
    test "response latency is within acceptable bounds" do
      # Create a single session for latency testing
      [session] = create_test_sessions(1)
      {:ok, pid} = start_session_server(session)

      # Measure latency for multiple requests
      latencies =
        for _i <- 1..20 do
          mock_ai = fn _session_id, _content, _opts ->
            # Minimal mock delay
            {:ok, %{result: "Response"}, "session_123"}
          end

          start = System.monotonic_time(:microsecond)
          {:ok, _} = SessionServer.handle_message(pid, "Test", ai_client: mock_ai)
          finish = System.monotonic_time(:microsecond)

          (finish - start) / 1000
        end

      avg_latency = Enum.sum(latencies) / length(latencies)
      p95_latency = latencies |> Enum.sort() |> Enum.at(round(length(latencies) * 0.95))
      p99_latency = latencies |> Enum.sort() |> Enum.at(round(length(latencies) * 0.99))

      IO.puts("""

      === Latency Test Results ===
      Samples: #{length(latencies)}
      Average: #{Float.round(avg_latency, 2)}ms
      P95: #{Float.round(p95_latency, 2)}ms
      P99: #{Float.round(p99_latency, 2)}ms
      ============================
      """)

      # Gateway processing latency (without AI) should be < 100ms
      assert avg_latency < 100, "Average latency too high: #{avg_latency}ms"
    end
  end

  describe "database connection pooling" do
    @tag :performance
    test "database handles concurrent queries without exhausting pool" do
      # Create sessions and perform concurrent database operations
      sessions = create_test_sessions(30)

      # Concurrent database operations
      tasks =
        Enum.map(sessions, fn session ->
          Task.async(fn ->
            # Perform multiple DB operations
            for _i <- 1..5 do
              # Read session
              Repo.get(Session, session.id)

              # Read user
              Repo.get(User, session.user_id)

              # Query messages
              import Ecto.Query

              Hal.Gateway.Message
              |> where(session_id: ^session.id)
              |> Repo.all()
            end

            :ok
          end)
        end)

      # Should complete without timeout (pool exhaustion)
      results = Task.await_many(tasks, 30_000)

      assert Enum.all?(results, &(&1 == :ok)),
             "Some database operations failed"
    end
  end

  # Helper functions

  defp create_test_sessions(count) do
    for i <- 1..count do
      {:ok, user} =
        %User{}
        |> User.changeset(%{
          external_id: "perf_user_#{i}_#{System.unique_integer([:positive])}",
          platform: "telegram",
          username: "perf_test_#{i}"
        })
        |> Repo.insert()

      {:ok, session} =
        %Session{}
        |> Session.changeset(%{
          channel_type: "telegram",
          channel_id: "perf_chat_#{i}_#{System.unique_integer([:positive])}",
          user_id: user.id,
          last_activity: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      session
    end
  end

  defp start_session_server(session) do
    test_id = System.unique_integer([:positive])
    registry_name = :"PerfRegistry_#{test_id}"

    {:ok, _} = Registry.start_link(keys: :unique, name: registry_name)

    SessionServer.start_link(
      session_id: session.id,
      channel_type: session.channel_type,
      channel_id: session.channel_id,
      user_id: session.user_id,
      registry_name: registry_name
    )
  end
end
