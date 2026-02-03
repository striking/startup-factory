# Quick Start: Event Sourcing for Autonomous Agents

**Goal:** Get HAL learning and improving autonomously in 5 minutes.

---

## 1. Start HAL

```bash
cd /Users/chrisohalloran/dev/concepts/hal

# Start the application
mix phx.server
```

HAL automatically:
- Creates `workspace/agent-log.jsonl` (event log)
- Initializes ETS cache (`:agent_state` table)
- Rebuilds state from event log (if exists)

---

## 2. Run Demo Examples

Open IEx console:

```bash
iex -S mix
```

### Example 1: Work Session

```elixir
alias HAL.Examples.EventSourcingDemo

# Simulate a complete work session
EventSourcingDemo.simulate_work_session()
```

Output:
```
📝 Simulating work session...

✓ Started: organize inbox
✓ Action: created label
✓ Action: created label
✗ Action failed: IMAP timeout
🧠 Learned: IMAP timeouts at peak hours
🔄 Strategy adjusted: queue for off-peak
✅ Task completed

📊 Current state:
- Current tasks: 0
- Completed tasks: 1
- Learned facts: 1
- Strategies: 1
```

### Example 2: Learning from Failure

```elixir
# See how HAL learns from repeated mistakes
EventSourcingDemo.simulate_learning_from_failure()
```

Output shows:
- Task fails 3 times
- HAL learns "Direct scraping gets blocked"
- HAL adjusts strategy
- New approach succeeds

### Example 3: Resume After Restart

```elixir
# See how HAL resumes interrupted work
EventSourcingDemo.simulate_restart()
```

Shows:
- Task starts
- "Crash" happens
- State rebuilt from event log
- Task resumes and completes

---

## 3. Inspect Event Log

```bash
# View raw event log
tail -f workspace/agent-log.jsonl

# Pretty print recent events
cat workspace/agent-log.jsonl | jq .
```

---

## 4. Query Agent State

```elixir
alias HAL.AgentState

# What is HAL currently working on?
AgentState.get_current_tasks()
# → ["analyze sales data", "research competitors"]

# What has HAL learned?
AgentState.get_learned_facts()
# → ["IMAP timeouts at 10am", "Direct scraping gets blocked", ...]

# What strategies work?
AgentState.get_strategies()
# → %{"organize inbox" => "queue for off-peak hours", ...}

# Get complete context
context = AgentState.get_context()
# → %{current_tasks: [...], learned_facts: [...], strategies: %{...}}
```

---

## 5. Use in Your Code

### Start a Task

```elixir
alias HAL.AgentState

# Log that you're starting work
AgentState.task_started("organize inbox", "create labels by sender",
  context: %{time: "morning", user_active: false}
)
```

### Log Actions

```elixir
# Success
AgentState.action_taken("created 5 labels", %{
  success: true,
  labels: ["Work", "Personal", "Newsletter", "Receipts", "Archive"]
})

# Failure
AgentState.action_failed("auto-archive old emails", "IMAP timeout",
  retry_count: 1
)
```

### Learn from Outcome

```elixir
# Extract lesson from failure
AgentState.learned(
  "IMAP operations timeout during peak hours (10am-12pm)",
  confidence: 0.8,
  source: "direct observation"
)
```

### Adjust Strategy

```elixir
# Change approach based on learning
AgentState.strategy_adjusted(
  "organize inbox",
  "process emails immediately",
  "queue for off-peak hours (after 2pm)"
)
```

### Complete Task

```elixir
AgentState.task_completed("organize inbox",
  "5 labels created, 127 emails sorted, 43 archived",
  metadata: %{duration_seconds: 120, emails_processed: 170}
)
```

---

## 6. Query Event History

```elixir
alias HAL.EventLog

# Get recent events
EventLog.recent(limit: 20)

# Get events by type
EventLog.by_type(:learned, days_back: 7)
# → All facts learned in last 7 days

# Search events
EventLog.query(contains: "timeout", days_back: 1)
# → All events mentioning "timeout" today

# Get statistics
EventLog.stats()
# → %{
#   total_events: 1234,
#   by_type: %{"learned" => 45, "task_completed" => 89, ...},
#   date_range: {~U[...], ~U[...]},
#   file_size_kb: 456
# }
```

---

## 7. Autonomous Work Cycle

```elixir
alias HAL.AutonomousAgent

# Let HAL decide what to work on
AutonomousAgent.work_cycle()

# Resume interrupted work
AutonomousAgent.resume_interrupted_work()

# Get activity summary
AutonomousAgent.get_activity_summary(days_back: 1)
```

Output:
```
**HAL Activity Summary (last 1 day(s)):**

- Tasks completed: 12
- Tasks failed: 2
- Facts learned: 5
- Total events: 89

**Current State:**
- Active tasks: 1
- Active goals: 3
- Learned facts: 15
```

---

## 8. Integrate with Heartbeat

Update `HAL.Heartbeat` to use the autonomous agent:

```elixir
defmodule HAL.Heartbeat do
  alias HAL.AutonomousAgent

  def check_for_work do
    if can_work_autonomously?() do
      case AutonomousAgent.work_cycle() do
        {:ok, action} ->
          Logger.info("Heartbeat: Completed #{action}")
          :ok

        {:skip, reason} ->
          Logger.debug("Heartbeat: Skipped - #{reason}")
          :ok

        {:error, reason} ->
          Logger.error("Heartbeat: Error - #{inspect(reason)}")
          :error
      end
    else
      :skip
    end
  end

  defp can_work_autonomously? do
    # Only work when user is not actively using HAL
    active_sessions = count_active_sessions()
    active_sessions == 0
  end
end
```

---

## 9. View Complete History

```elixir
alias HAL.Examples.EventSourcingDemo

# Show formatted history
EventSourcingDemo.show_agent_history()
```

Output:
```
📜 Agent History

Last 20 events:

10:00:00 | task_started         | organize inbox
10:05:00 | action_taken         | created label: Newsletter
10:10:00 | action_failed        | auto-archive
10:12:00 | learned              | IMAP timeouts at 10am
10:15:00 | strategy_adjusted    | organize inbox
10:20:00 | task_completed       | organize inbox

📊 Statistics:
Event Log Stats: %{
  total_events: 1234,
  by_type: %{
    "learned" => 45,
    "task_completed" => 89,
    "task_failed" => 12,
    ...
  }
}
```

---

## 10. Real-World Example

```elixir
defmodule HAL.Tasks.InboxOrganizer do
  alias HAL.AgentState

  def organize_inbox(user_id) do
    # Check what we learned before
    learned_facts = AgentState.get_learned_facts()
    current_hour = DateTime.utc_now().hour

    # Avoid peak hours if we learned they cause problems
    if peak_hours?(current_hour) and learned_timeout_at_peak?(learned_facts) do
      AgentState.decision_made(
        "Skip inbox organization",
        "Learned: IMAP timeouts at peak hours"
      )

      schedule_for_later()
    else
      # Start task with learned strategy
      strategy = AgentState.get_strategy("organize inbox") || "default"
      AgentState.task_started("organize inbox", strategy)

      # Perform the work
      case create_labels_and_sort(user_id, strategy) do
        {:ok, result} ->
          AgentState.action_taken("organized inbox", result)
          AgentState.task_completed("organize inbox", result.summary)
          {:ok, result}

        {:error, "timeout" = reason} ->
          AgentState.action_failed("organize inbox", reason, retry_count: 1)

          # Learn from failure
          if current_hour >= 10 and current_hour < 12 do
            AgentState.learned(
              "IMAP timeouts occur at #{current_hour}:00",
              confidence: 0.8
            )
          end

          {:error, reason}
      end
    end
  end

  defp peak_hours?(hour), do: hour >= 10 and hour < 12

  defp learned_timeout_at_peak?(facts) do
    Enum.any?(facts, fn fact ->
      String.contains?(String.downcase(fact), "timeout") and
        String.contains?(String.downcase(fact), "peak")
    end)
  end
end
```

---

## Key Concepts

### 1. Events Are Immutable
- Never delete or modify events
- Always append to log
- State = replay all events

### 2. ETS is a Cache
- Rebuilt from event log on boot
- Updated automatically when logging events
- Fast reads (microseconds)

### 3. Learn from Everything
- Log every action outcome
- Extract patterns from failures
- Adjust strategies over time

### 4. Context-Aware Decisions
```elixir
context = AgentState.get_context()
# Use context to make informed decisions
# - What failed before?
# - What strategies work?
# - What did I learn?
```

---

## Troubleshooting

### "No events in log"
```bash
# Check if log file exists
ls workspace/agent-log.jsonl

# If not, run a demo
iex -S mix
iex> HAL.Examples.EventSourcingDemo.simulate_work_session()
```

### "ETS table not found"
```elixir
# Rebuild state
HAL.AgentState.rebuild_from_log()
```

### "Can't read event log"
```bash
# Check permissions
ls -la workspace/agent-log.jsonl

# Check JSON format
cat workspace/agent-log.jsonl | jq . | head
```

---

## Next Steps

1. **Integrate with your workflows** - Add event logging to existing code
2. **Let HAL learn** - Run for a few days, see what it learns
3. **Query patterns** - Use EventLog to find optimization opportunities
4. **Build custom analysis** - Write functions to extract insights from events

---

## Resources

- [EVENT_SOURCING_ARCHITECTURE.md](EVENT_SOURCING_ARCHITECTURE.md) - Full architecture docs
- [lib/hal/event_log.ex](lib/hal/event_log.ex) - Event log implementation
- [lib/hal/agent_state.ex](lib/hal/agent_state.ex) - Agent state management
- [lib/hal/autonomous_agent.ex](lib/hal/autonomous_agent.ex) - Autonomous decision making

---

**You're ready!** Start logging events and watch HAL learn and improve over time. 🚀
