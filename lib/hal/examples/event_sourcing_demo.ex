defmodule HAL.Examples.EventSourcingDemo do
  @moduledoc """
  Demonstrates HAL's event sourcing system for autonomous agents.

  Run these examples to see how the agent learns and improves over time.

  ## Examples

      # Simulate a work session
      EventSourcingDemo.simulate_work_session()

      # Simulate learning from failure
      EventSourcingDemo.simulate_learning_from_failure()

      # Show how state persists across restart
      EventSourcingDemo.simulate_restart()

      # Query what the agent has done
      EventSourcingDemo.show_agent_history()
  """

  alias HAL.AgentState
  alias HAL.EventLog

  @doc """
  Simulate a complete work session with tasks, successes, and learning.
  """
  def simulate_work_session do
    IO.puts("\n📝 Simulating work session...\n")

    # Start a task
    AgentState.task_started("organize inbox", "create labels by sender")
    IO.puts("✓ Started: organize inbox")

    # Take some actions
    AgentState.action_taken("created label: Newsletter", %{success: true})
    IO.puts("✓ Action: created label")

    AgentState.action_taken("created label: Work", %{success: true})
    IO.puts("✓ Action: created label")

    # Action fails
    AgentState.action_failed("auto-archive old emails", "IMAP timeout", retry_count: 1)
    IO.puts("✗ Action failed: IMAP timeout")

    # Learn from failure
    AgentState.learned("IMAP timeouts occur during peak hours (10am-12pm)", confidence: 0.8)
    IO.puts("🧠 Learned: IMAP timeouts at peak hours")

    # Adjust strategy
    AgentState.strategy_adjusted(
      "organize inbox",
      "process immediately",
      "queue for off-peak hours"
    )

    IO.puts("🔄 Strategy adjusted: queue for off-peak")

    # Complete the task
    AgentState.task_completed("organize inbox", "2 labels created, emails queued for later")
    IO.puts("✅ Task completed")

    IO.puts("\n📊 Current state:")
    print_state()
  end

  @doc """
  Simulate learning from repeated failures.
  """
  def simulate_learning_from_failure do
    IO.puts("\n📝 Simulating learning from failures...\n")

    # Try something that keeps failing
    task = "scrape competitor website"
    AgentState.task_started(task, "direct HTTP requests")

    Enum.each(1..3, fn attempt ->
      AgentState.action_failed("scrape competitor website", "403 Forbidden", retry_count: attempt)

      IO.puts("✗ Attempt #{attempt} failed: 403 Forbidden")
      Process.sleep(100)
    end)

    # Learn that this approach doesn't work
    AgentState.learned("Direct scraping gets blocked - need different approach", confidence: 0.95)
    IO.puts("🧠 Learned: Direct scraping blocked")

    # Adjust strategy
    AgentState.strategy_adjusted(
      task,
      "direct HTTP requests",
      "use headless browser with delays"
    )

    IO.puts("🔄 Strategy adjusted: use headless browser")

    # Give up on this task for now
    AgentState.task_failed(task, "Blocked after 3 attempts", retry_count: 3)
    IO.puts("⛔ Task failed")

    # Start new task with better strategy
    AgentState.task_started("research competitors", "use public APIs and search")
    IO.puts("\n✓ Started new task with better strategy")

    AgentState.task_completed("research competitors", "Found 5 competitors via API")
    IO.puts("✅ Task completed with new approach")

    IO.puts("\n📊 What did we learn?")
    print_learned_facts()
  end

  @doc """
  Simulate HAL restarting and resuming work.

  This demonstrates event sourcing - state is rebuilt from event log.
  """
  def simulate_restart do
    IO.puts("\n📝 Simulating restart and resume...\n")

    # Start a long-running task
    AgentState.task_started("analyze sales data", "aggregate by month")
    IO.puts("✓ Started: analyze sales data")

    AgentState.action_taken("loaded data from CSV", %{rows: 1000})
    IO.puts("✓ Loaded 1000 rows")

    IO.puts("\n💥 SIMULATING CRASH/RESTART\n")

    # Rebuild state from event log (simulates restart)
    AgentState.rebuild_from_log()
    IO.puts("♻️  State rebuilt from event log")

    IO.puts("\n📊 After restart:")
    current_tasks = AgentState.get_current_tasks()
    IO.puts("Current tasks: #{inspect(current_tasks)}")

    if "analyze sales data" in current_tasks do
      IO.puts("\n✅ Successfully resumed interrupted task!")
      strategy = AgentState.get_strategy("analyze sales data")
      IO.puts("Strategy: #{strategy}")

      # Complete the task
      AgentState.action_taken("aggregated by month", %{months: 12})
      AgentState.task_completed("analyze sales data", "12 months aggregated")
      IO.puts("✅ Task completed after resume")
    end

    IO.puts("\n📊 Final state:")
    print_state()
  end

  @doc """
  Show complete history of what the agent has done.
  """
  def show_agent_history do
    IO.puts("\n📜 Agent History\n")

    # Get recent events
    events = EventLog.recent(limit: 20)

    IO.puts("Last 20 events:\n")

    Enum.each(events, fn event ->
      timestamp = event["timestamp"] |> String.slice(11, 8)
      event_type = event["event"]
      data = format_event_data(event["data"])

      IO.puts("#{timestamp} | #{pad_event_type(event_type)} | #{data}")
    end)

    IO.puts("\n📊 Statistics:")
    stats = EventLog.stats()
    IO.inspect(stats, label: "Event Log Stats")
  end

  @doc """
  Show how learned facts help avoid past mistakes.
  """
  def demonstrate_learning do
    IO.puts("\n📝 Demonstrating learning from history...\n")

    # Simulate scenario where agent remembers what it learned
    learned_facts = AgentState.get_learned_facts()

    if "IMAP timeouts occur during peak hours (10am-12pm)" in learned_facts do
      current_hour = DateTime.utc_now().hour

      if current_hour >= 10 and current_hour < 12 do
        IO.puts("⏰ Current time: #{current_hour}:00")
        IO.puts("🧠 I learned: IMAP timeouts at this time")
        IO.puts("💡 Decision: Skip IMAP operations, will retry later")

        AgentState.decision_made(
          "Skip IMAP operations during peak hours",
          "Learned from past failures"
        )
      else
        IO.puts("⏰ Current time: #{current_hour}:00")
        IO.puts("✅ Safe time for IMAP operations")
        IO.puts("💡 Decision: Proceed with IMAP operations")
      end
    else
      IO.puts("ℹ️  No relevant learned facts yet")
      IO.puts("💡 Will learn from experience over time")
    end
  end

  # Helper Functions

  defp print_state do
    context = AgentState.get_context()

    IO.puts("- Current tasks: #{length(context.current_tasks)}")
    IO.puts("- Completed tasks: #{length(context.recent_completions)}")
    IO.puts("- Learned facts: #{length(context.learned_facts)}")
    IO.puts("- Strategies: #{map_size(context.strategies)}")
    IO.puts("- Goals: #{length(context.goals)}")
  end

  defp print_learned_facts do
    facts = AgentState.get_learned_facts()

    if Enum.empty?(facts) do
      IO.puts("No learned facts yet")
    else
      Enum.each(facts, fn fact ->
        IO.puts("🧠 #{fact}")
      end)
    end
  end

  defp format_event_data(data) when is_map(data) do
    cond do
      Map.has_key?(data, "task") ->
        "#{data["task"]}"

      Map.has_key?(data, "action") ->
        "#{data["action"]}"

      Map.has_key?(data, "fact") ->
        "#{data["fact"]}"

      Map.has_key?(data, "decision") ->
        "#{data["decision"]}"

      true ->
        inspect(data)
    end
  end

  defp format_event_data(data), do: inspect(data)

  defp pad_event_type(event_type) do
    String.pad_trailing(event_type, 20)
  end
end
