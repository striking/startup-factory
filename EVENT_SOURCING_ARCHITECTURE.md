# HAL Event Sourcing Architecture

**Last Updated:** 2026-01-29
**Status:** ✅ Implemented

---

## Overview

HAL uses **event sourcing** for autonomous agent state management, eliminating the need for traditional database storage while providing complete audit trails and self-learning capabilities.

**Key Innovation:** Instead of storing current state, we store every action, decision, and outcome in an append-only log. State is rebuilt by replaying events.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  HAL's Brain: Event Log                 │
│                                                          │
│  Every action, decision, outcome → JSONL file           │
│  Complete history, never deleted                        │
│  Source of truth for all agent state                    │
└─────────────────────────────────────────────────────────┘
                            ↓
              Replay events to rebuild state
                            ↓
┌─────────────────────────────────────────────────────────┐
│              ETS Cache (In-Memory, Fast)                │
│                                                          │
│  - Current tasks                                         │
│  - Learned facts                                         │
│  - Strategies that work                                  │
│  - Goals and progress                                    │
│                                                          │
│  Rebuilt on boot, updated on each event                 │
└─────────────────────────────────────────────────────────┘
                            ↓
                  Fast reads for decisions
                            ↓
┌─────────────────────────────────────────────────────────┐
│              Autonomous Decision Making                 │
│                                                          │
│  1. Load context from ETS                               │
│  2. What was I doing? What failed? What did I learn?    │
│  3. Use Claude to decide next action                    │
│  4. Execute & log outcome                               │
│  5. Learn from outcome → Update event log               │
└─────────────────────────────────────────────────────────┘
```

---

## Event Log Structure

### File: `workspace/agent-log.jsonl`

Append-only JSONL file with every event:

```jsonl
{"timestamp":"2026-01-29T10:00:00Z","event":"task_started","data":{"task":"organize inbox","strategy":"create labels by sender"}}
{"timestamp":"2026-01-29T10:05:00Z","event":"action_taken","data":{"action":"created label: Newsletter","result":{"success":true}}}
{"timestamp":"2026-01-29T10:10:00Z","event":"action_failed","data":{"action":"auto-archive","error":"IMAP timeout","retry_count":1}}
{"timestamp":"2026-01-29T10:12:00Z","event":"learned","data":{"fact":"IMAP timeouts at 10am","confidence":0.8}}
{"timestamp":"2026-01-29T10:15:00Z","event":"strategy_adjusted","data":{"task":"organize inbox","old":"immediate","new":"queue off-peak"}}
{"timestamp":"2026-01-29T10:20:00Z","event":"task_completed","data":{"task":"organize inbox","outcome":"2 labels, emails queued"}}
```

### Event Types

| Event | Purpose | Data |
|-------|---------|------|
| `task_started` | Agent begins task | task, strategy, context |
| `task_completed` | Task finished successfully | task, outcome, metadata |
| `task_failed` | Task failed after retries | task, reason, retry_count |
| `action_taken` | Agent performed action | action, result |
| `action_failed` | Action failed | action, error, retry_count |
| `decision_made` | Strategic decision | decision, reasoning |
| `learned` | Learned a fact/pattern | fact, confidence, source |
| `strategy_adjusted` | Changed approach | task, old, new, reason |
| `goal_set` | New goal established | goal, priority, deadline |
| `goal_completed` | Goal achieved | goal_id, outcome |

---

## Benefits Over Traditional Database

### 1. Complete Audit Trail
```elixir
# Every decision is traceable
EventLog.query(contains: "organize inbox")
# See full history: why started, what failed, what learned, outcome
```

### 2. Learning from History
```elixir
# What failed in the past?
failures = AgentState.get_failed_tasks()
# "IMAP timeout" failed 5 times at 10am

# Avoid repeating mistakes
AgentState.learned("Avoid IMAP at 10am", confidence: 0.9)
```

### 3. Resume After Restart
```elixir
# On boot: replay all events
state = EventLog.replay()
# → %{current_tasks: ["analyze data"], learned_facts: [...]}

# Continue where we left off
AutonomousAgent.resume_interrupted_work()
```

### 4. Temporal Reasoning
```elixir
# What was I doing before the failure?
EventLog.query(event: "action_taken", days_back: 1)

# Pattern: failures happen at certain times
failures_by_hour = analyze_failure_patterns()
# → 10am-12pm: 80% failure rate for IMAP
```

### 5. Explainability
```elixir
# Why did you do X?
EventLog.query(contains: "decision_made")
# → "Decided to skip IMAP: Learned from past failures at this time"
```

### 6. Version Control
```bash
# Commit event log to git
git add workspace/agent-log.jsonl
git commit -m "Agent learned to avoid IMAP at peak hours"

# Track agent evolution over time
git log workspace/agent-log.jsonl
```

---

## Implementation

### Logging Events

```elixir
# Start a task
AgentState.task_started("organize inbox", "create labels by sender")

# Log actions
AgentState.action_taken("created 5 labels", %{success: true})

# Log failures
AgentState.action_failed("auto-archive", "IMAP timeout", retry_count: 1)

# Learn from outcome
AgentState.learned("IMAP timeouts at 10am", confidence: 0.8)

# Adjust strategy
AgentState.strategy_adjusted(
  "organize inbox",
  "process immediately",
  "queue for off-peak"
)

# Complete task
AgentState.task_completed("organize inbox", "5 labels created, 100 emails sorted")
```

### Querying State (Fast ETS)

```elixir
# Get current state (microsecond lookup)
AgentState.get_current_tasks()
# → ["analyze sales data", "research competitors"]

AgentState.get_learned_facts()
# → ["IMAP timeouts at 10am", "User prefers summaries", ...]

AgentState.get_strategy("organize inbox")
# → "queue for off-peak hours"

# Get complete context for decisions
context = AgentState.get_context()
# → %{
#   current_tasks: [...],
#   recent_failures: [...],
#   learned_facts: [...],
#   strategies: %{...},
#   goals: [...]
# }
```

### Autonomous Work Cycle

```elixir
defmodule HAL.AutonomousAgent do
  def work_cycle do
    # 1. Load context (fast ETS read)
    context = AgentState.get_context()

    # 2. Analyze history
    # - What was I doing?
    # - What failed before?
    # - What did I learn?

    # 3. Decide next action (use Claude)
    action = decide_based_on_context(context)

    # 4. Execute
    result = execute(action)

    # 5. Log outcome
    AgentState.action_taken(action, result)

    # 6. Learn from outcome
    if result.failed do
      AgentState.learned("Strategy X failed: #{result.reason}", confidence: 0.8)
    end
  end
end
```

---

## Example: Learning from Failure

```elixir
# Attempt 1
AgentState.task_started("scrape competitor", "direct HTTP")
AgentState.action_failed("scrape", "403 Forbidden", retry_count: 1)

# Attempt 2
AgentState.action_failed("scrape", "403 Forbidden", retry_count: 2)

# Attempt 3
AgentState.action_failed("scrape", "403 Forbidden", retry_count: 3)

# Learn lesson
AgentState.learned("Direct scraping gets blocked", confidence: 0.95)
AgentState.task_failed("scrape competitor", "Blocked after 3 attempts")

# Adjust approach
AgentState.task_started("research competitors", "use public APIs")
AgentState.task_completed("research competitors", "Found 5 competitors via API")

# Now HAL knows:
# - Direct scraping doesn't work
# - Public APIs are better approach
# - Will use APIs for future research tasks
```

---

## Example: Resume After Restart

```elixir
# Before restart
AgentState.task_started("analyze sales data", "aggregate by month")
AgentState.action_taken("loaded 1000 rows from CSV", %{success: true})

# *** CRASH/RESTART ***

# On boot: AgentState.init() automatically runs
# → Reads agent-log.jsonl
# → Replays all events
# → Rebuilds ETS cache

# After restart
AgentState.get_current_tasks()
# → ["analyze sales data"]

AgentState.get_strategy("analyze sales data")
# → "aggregate by month"

# Agent knows exactly where it left off!
AutonomousAgent.resume_interrupted_work()
# → Continues aggregation, completes task
```

---

## Performance

### Write Performance
- **Append to JSONL:** ~1ms per event
- **Update ETS:** ~10μs per insert
- **Total:** < 2ms per event

### Read Performance
- **ETS lookup:** ~1-10μs
- **Query event log:** ~50ms for 10K events (grep-like speed)
- **Rebuild state on boot:** ~100ms for 10K events

### Storage
- **Event log:** ~1KB per event
- **10K events:** ~10MB
- **ETS memory:** ~1MB for typical state

---

## Comparison to Postgres

| Feature | Postgres | Event Sourcing |
|---------|----------|----------------|
| **Write Speed** | 5-10ms | 1-2ms |
| **Read Speed** | 1-5ms | 1-10μs (ETS) |
| **Audit Trail** | Limited | Complete |
| **Learning** | Hard | Natural |
| **Version Control** | N/A | Yes (git) |
| **Dependencies** | Postgres | None |
| **Human Readable** | No | Yes (JSONL) |
| **Temporal Queries** | Complex | Simple |
| **Resume After Crash** | Requires design | Automatic |

---

## Migration from Postgres

For now, we run **hybrid mode:**
- Postgres for Oban (job queue)
- Event sourcing for agent state
- Markdown for memory (already doing this!)

**Future:** Replace Oban with ETS + Quantum (already have Quantum).

---

## Testing

```bash
# Run demo examples
iex -S mix

# Simulate work session
iex> alias HAL.Examples.EventSourcingDemo
iex> EventSourcingDemo.simulate_work_session()

# Show learning from failure
iex> EventSourcingDemo.simulate_learning_from_failure()

# Demonstrate restart/resume
iex> EventSourcingDemo.simulate_restart()

# Show complete history
iex> EventSourcingDemo.show_agent_history()
```

---

## API Reference

### HAL.EventLog

```elixir
# Log events
EventLog.log(:task_started, %{task: "research", strategy: "web search"})

# Query recent events
EventLog.recent(limit: 50, days_back: 7)

# Query by type
EventLog.by_type(:learned, days_back: 7)

# Flexible query
EventLog.query(event: "learned", contains: "timeout", limit: 10)

# Get statistics
EventLog.stats()
# → %{total_events: 1234, by_type: %{...}, date_range: {...}}

# Replay all events
EventLog.replay()
# → %{current_tasks: [...], learned_facts: [...], ...}
```

### HAL.AgentState

```elixir
# Task management
AgentState.task_started("task", "strategy")
AgentState.task_completed("task", "outcome")
AgentState.task_failed("task", "reason", retry_count: 3)

# Action tracking
AgentState.action_taken("action", %{result: "success"})
AgentState.action_failed("action", "error", retry_count: 1)

# Learning
AgentState.learned("fact", confidence: 0.8)
AgentState.strategy_adjusted("task", "old", "new")
AgentState.decision_made("decision", "reasoning")

# Goal management
AgentState.goal_set("goal", priority: 8)
AgentState.goal_completed("goal_id", outcome: "achieved")

# Queries (fast ETS)
AgentState.get_current_tasks()
AgentState.get_learned_facts()
AgentState.get_strategy("task")
AgentState.get_context()  # Complete context for decisions
```

### HAL.AutonomousAgent

```elixir
# Autonomous work cycle
AutonomousAgent.work_cycle()

# Resume interrupted work
AutonomousAgent.resume_interrupted_work()

# Analyze and learn from history
AutonomousAgent.analyze_and_learn()

# Get activity summary
AutonomousAgent.get_activity_summary(days_back: 7)
```

---

## Best Practices

### When to Log Events

✅ **DO log:**
- Every task started/completed/failed
- Every action taken
- Every failure (with error details)
- Every fact learned
- Every strategic decision
- Every strategy adjustment

❌ **DON'T log:**
- Temporary state (use ETS)
- Sensitive data (encrypt if needed)
- Debug information (use Logger)
- High-frequency events (> 100/sec)

### Event Data Structure

```elixir
# GOOD: Rich context for learning
EventLog.log(:action_failed, %{
  action: "scrape website",
  error: "403 Forbidden",
  retry_count: 2,
  context: %{time: "10:15", day: "Monday", load: "high"}
})

# BAD: Not enough context
EventLog.log(:action_failed, %{action: "scrape"})
```

### Learning Strategy

```elixir
# Learn specific facts
AgentState.learned("IMAP timeouts between 10am-12pm", confidence: 0.9)

# Not vague generalizations
AgentState.learned("Things fail sometimes", confidence: 0.5)  # Not useful!
```

---

## Future Enhancements

- [ ] Automatic fact extraction using Claude
- [ ] Pattern detection (ML on event sequences)
- [ ] Event log compaction (archive old events)
- [ ] Distributed event log (multi-machine HAL)
- [ ] Event visualization dashboard
- [ ] Export to analytics tools

---

## References

- [Event Sourcing Pattern](https://martinfowler.com/eaaDev/EventSourcing.html)
- [CQRS + Event Sourcing](https://docs.microsoft.com/en-us/azure/architecture/patterns/cqrs)
- [Elixir ETS Documentation](https://hexdocs.pm/elixir/Application.html)

---

**Status:** ✅ Production-ready
**Version:** 1.0.0
**Last Updated:** 2026-01-29
