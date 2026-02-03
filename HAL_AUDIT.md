# HAL System Audit

**Date:** 2026-02-01
**Total Modules:** 72
**Started in application.ex:** ~15

## Executive Summary

HAL has significant infrastructure that is **built but not connected**. This audit identifies what's working, what's dead code, and what needs wiring.

---

## ✅ WORKING (Started & Called)

| Module | Started By | Purpose |
|--------|-----------|---------|
| `HAL.AI.Supervisor` | application.ex | AI client supervision |
| `HAL.Agents.Supervisor` | application.ex | Codex/Jules/Gemini supervision |
| `HAL.AgentState` | application.ex | Event sourcing state |
| `HAL.AgentRegistry` | application.ex | Agent process registry |
| `HAL.MultiAgent.Orchestrator` | application.ex | **Started but never used** |
| `HAL.DelegationMetrics` | application.ex | Tracks delegation stats |
| `HAL.Resilience.Supervisor` | application.ex | Circuit breakers, rate limiters |
| `HAL.Scheduler` | application.ex | Quantum cron jobs |
| `HAL.Goals.Supervisor` | application.ex | Goal management |
| `HAL.Autonomy.Supervisor` | application.ex | DynamicSupervisor for orchestrators |
| `HAL.Heartbeat` | Quantum scheduler | Periodic checks (email, calendar, goals) |

---

## ⚠️ STARTED BUT UNUSED

| Module | Problem | Fix |
|--------|---------|-----|
| `HAL.MultiAgent.Orchestrator` | Started but `create_job/2` never called | Add tool `hal_spawn_parallel_agents` |
| `HAL.Autonomy.Supervisor` | DynamicSupervisor exists but `start_orchestrator/2` never called | Auto-start on user interaction |
| `HAL.Goals.Supervisor` | Goals can be created but `HAL.Goals.Pursuer` never started | Redundant with Heartbeat now |

---

## ❌ NOT STARTED (Dead Code)

| Module | Purpose | Should Wire Up? |
|--------|---------|-----------------|
| `HAL.DeadMansSwitch` | "I'm alive" heartbeats to Telegram | **YES** - Add to application.ex |
| `HAL.AutonomousAgent` | Full autonomous agent loop | MAYBE - Evaluate vs Heartbeat |
| `HAL.Automation.Scheduler` | Different from HAL.Scheduler? | INVESTIGATE - May be redundant |
| `HAL.Automation.Workers.*` | ProactiveTask, ScheduledTask, Webhook | INVESTIGATE - Oban workers? |
| `HAL.SelfImprovement` | Analyzes patterns, suggests improvements | **YES** - Add to Quantum |
| `HAL.SelfImprovement.AnalyzerWorker` | Oban worker for analysis | **YES** - Wire to SelfImprovement |

---

## 🔄 REDUNDANT SYSTEMS (Need Consolidation)

### Periodic Work Execution
Three systems do similar things:
1. `HAL.Heartbeat` - Quantum-triggered, rotation-based checks
2. `HAL.Autonomy.Orchestrator` - Per-user, goal-focused, never started
3. `HAL.Goals.Pursuer` - Goal execution, never started

**Recommendation:** Keep Heartbeat (it works), delete or merge others.

### Orchestration
Two orchestrators with confusing names:
1. `HAL.MultiAgent.Orchestrator` - Parallel task spawning (good)
2. `HAL.Autonomy.Orchestrator` - Per-user heartbeat (redundant with Heartbeat)

**Recommendation:** Rename MultiAgent.Orchestrator to `HAL.ParallelExecutor`, delete Autonomy.Orchestrator.

### Scheduling
Two schedulers:
1. `HAL.Scheduler` - Quantum-based (used)
2. `HAL.Automation.Scheduler` - Unknown purpose

**Recommendation:** Investigate HAL.Automation.Scheduler, likely delete.

---

## 📋 WIRING PLAN (Priority Order)

### Phase 1: Critical Fixes
1. **Wire MultiAgent** - Add `hal_spawn_parallel_agents` tool so HAL can run tasks in parallel
2. **Start DeadMansSwitch** - Add to application.ex for health monitoring
3. **Wire SelfImprovement** - Add weekly job to Quantum scheduler

### Phase 2: Consolidation
4. **Delete Autonomy.Orchestrator** - Redundant with Heartbeat
5. **Delete Goals.Pursuer** - Redundant with Heartbeat goal processing
6. **Investigate HAL.Automation.\*** - Keep or delete

### Phase 3: Testing
7. **End-to-end test** - User gives multi-task → HAL executes in parallel → Reports back

---

## 🗑️ CANDIDATES FOR DELETION

| Module | Reason |
|--------|--------|
| `HAL.Autonomy.Orchestrator` | Redundant with Heartbeat |
| `HAL.Goals.Pursuer` | Redundant with Heartbeat goal processing |
| `HAL.Automation.Scheduler` | Probably redundant with HAL.Scheduler |
| `HAL.Examples.EventSourcingDemo` | Demo code |
| `HAL.AutonomousAgent` | Never used, unclear purpose |

---

## 📊 Module Categories

### AI/LLM (Working)
- `HAL.AI.AgentSDK` ✅
- `HAL.AI.Supervisor` ✅
- `HAL.Agents.Codex` ✅ (via Supervisor)
- `HAL.Agents.Gemini` ✅ (via Supervisor)
- `HAL.Agents.Jules` ⚠️ (no API key)

### Memory (Working)
- `HAL.Memory` ✅
- `HAL.Memory.Search` ✅
- `HAL.Memory.Embedding` ✅
- `HAL.AgentState` ✅

### Goals (Partially Working)
- `HAL.Goals.Manager` ✅
- `HAL.Goals.Goal` ✅
- `HAL.Goals.Supervisor` ✅
- `HAL.Goals.Pursuer` ❌ Not started

### Autonomy (Partially Working)
- `HAL.Heartbeat` ✅
- `HAL.Autonomy.SoulLoader` ✅
- `HAL.Autonomy.TimeAwareness` ✅
- `HAL.Autonomy.HeartbeatState` ✅
- `HAL.Autonomy.Orchestrator` ❌ Not started
- `HAL.Autonomy.Supervisor` ⚠️ Started but unused

### Tools/Integrations (Working)
- `HAL.Integrations.Calendar` ✅
- `HAL.Integrations.Email` ✅
- `HAL.Integrations.Tasks` ✅
- `HAL.ToolRunner` ✅

### Resilience (Working)
- `HAL.Resilience.Supervisor` ✅
- `HAL.Resilience.CircuitBreaker` ✅
- `HAL.Resilience.RateLimiter` ✅

### Voice (Partially Working)
- `HAL.Voice.TTS` ⚠️ Only used by Telegram
- `HAL.Voice.STT` ⚠️ Only used by Telegram

### Not Started
- `HAL.DeadMansSwitch` ❌
- `HAL.SelfImprovement` ❌
- `HAL.AutonomousAgent` ❌
- `HAL.Automation.*` ❌

---

## 🚫 SIMULATED CODE (CRITICAL - Nothing Actually Works)

### HAL.Autonomy.perform_check/1 - ALL FAKE
```elixir
defp perform_check(:email) do
  :nothing_urgent  # NEVER CHECKS EMAIL
end
defp perform_check(:calendar) do
  :no_upcoming_events  # NEVER CHECKS CALENDAR
end
```

### HAL.Autonomy.execute_task/1 - ALL FAKE
```elixir
defp execute_task(%{type: :resume, task: task}) do
  AgentState.task_completed(task, "Resumed and completed")  # DOES NOTHING
end
```

### Hal.Tools.Handlers.Tasks - RETURNS MOCK DATA
```elixir
stub_tasks = [%{id: "task-1", title: "Review PR #234"...}]  # HARDCODED FAKE
```

### Hal.Tools.Handlers.Notifications - LOGS INSTEAD OF SENDING
```elixir
Logger.info("Notification stub - would send...")  # NEVER SENDS
```

**Impact:** HAL appears to work but does nothing. It "checks email" without checking. It "completes tasks" without doing anything. It "sends notifications" that never arrive.

---

## 🚨 STABILITY RISKS (From Gemini Review)

### Blocking I/O in EventLog
- **File:** `lib/hal/event_log.ex`
- **Problem:** `File.write/3` is synchronous
- **Risk:** Disk I/O spikes → GenServers block → cascading timeouts
- **Fix:** Wrap in GenServer with buffer, or use async writes

### Blocking Init in AgentState
- **File:** `lib/hal/agent_state.ex`
- **Problem:** `init/1` calls `EventLog.replay_with_snapshot()` synchronously
- **Risk:** As history grows, replay exceeds OTP 5s timeout → boot crash
- **Fix:** Move to `handle_continue/2` for async loading

### Missing MCP Client
- **Problem:** HAL can't consume external MCP servers
- **Impact:** No access to 50+ OpenCLAW integrations
- **Fix:** Add MCP Client capability

---

## Next Actions

### Phase 0: Stability Fixes (Do First)
1. [ ] Fix EventLog blocking I/O
2. [ ] Fix AgentState blocking init

### Phase 1: Critical Wiring
3. [ ] Wire `HAL.MultiAgent` - highest priority for parallel execution
4. [ ] Start `HAL.DeadMansSwitch` in application.ex
5. [ ] Add `HAL.SelfImprovement` to Quantum weekly

### Phase 2: Consolidation
6. [ ] Delete redundant modules (Autonomy.Orchestrator, Goals.Pursuer)

### Phase 3: Ecosystem
7. [ ] Add MCP Client for OpenCLAW compatibility

### Phase 4: Validation
8. [ ] End-to-end test
