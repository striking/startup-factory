# HAL Heartbeat & Monitoring Design

## Current State (What OTP Already Provides)

### Built-in Process Monitoring
Elixir/OTP supervision trees ARE a heartbeat system:
- Supervisors monitor child processes
- Automatic restart on crash
- Configurable restart strategies (`:one_for_one`, `:rest_for_one`, etc.)
- Process linking for dependent processes

### What We Have Now
```
HAL.Application (Supervisor)
├── HAL.Repo (Database connection pool)
├── Oban (Job queue with built-in monitoring)
├── HAL.Gateway (Supervisor)
│   ├── Registry (Session lookups)
│   ├── DynamicSupervisor (Session spawning)
│   └── SessionManager
└── HalWeb.Endpoint (Phoenix server)
```

If any component crashes → Supervisor restarts it automatically

---

## What's Missing (24/7 Reliability Features)

### 1. External Health Monitoring ✅ (Just Built)
- **Status:** COMPLETE
- **Implementation:** `/health`, `/health/ready`, `/health/live` endpoints
- **Purpose:** External monitoring tools can verify HAL is alive
- **Usage:** Uptime monitoring services, Kubernetes probes

### 2. Internal Watchdog (Hang Detection) 🔶 TODO
**Problem:** GenServers can hang (waiting for external API, infinite loop, etc.)

**Solution:** Watchdog GenServer that monitors operation timeouts

```elixir
# lib/hal/watchdog.ex
defmodule HAL.Watchdog do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    schedule_check()
    {:ok, %{
      monitored_processes: %{},
      last_seen: %{}
    }}
  end

  # Register a process for monitoring
  def monitor(pid, timeout \\ 60_000) do
    GenServer.cast(__MODULE__, {:monitor, pid, timeout})
  end

  # Process checks in (resets timer)
  def heartbeat(pid) do
    GenServer.cast(__MODULE__, {:heartbeat, pid})
  end

  def handle_info(:check_heartbeats, state) do
    now = System.monotonic_time(:millisecond)

    # Check which processes haven't checked in
    dead_processes =
      state.monitored_processes
      |> Enum.filter(fn {pid, timeout} ->
        last_seen = state.last_seen[pid] || 0
        now - last_seen > timeout
      end)
      |> Enum.map(fn {pid, _} -> pid end)

    # Kill hung processes (supervisor will restart)
    Enum.each(dead_processes, fn pid ->
      Logger.warning("Process #{inspect(pid)} hung, killing...")
      Process.exit(pid, :watchdog_timeout)
    end)

    schedule_check()
    {:noreply, state}
  end

  def handle_cast({:monitor, pid, timeout}, state) do
    Process.monitor(pid)
    {:noreply, %{
      state |
      monitored_processes: Map.put(state.monitored_processes, pid, timeout),
      last_seen: Map.put(state.last_seen, pid, System.monotonic_time(:millisecond))
    }}
  end

  def handle_cast({:heartbeat, pid}, state) do
    {:noreply, %{
      state |
      last_seen: Map.put(state.last_seen, pid, System.monotonic_time(:millisecond))
    }}
  end

  defp schedule_check do
    Process.send_after(self(), :check_heartbeats, 10_000) # Every 10s
  end
end
```

**Usage in SessionServer:**
```elixir
defmodule HAL.Gateway.SessionServer do
  def handle_call({:prompt, message}, from, state) do
    # Register with watchdog
    HAL.Watchdog.monitor(self(), 120_000) # 2 min timeout

    Task.start(fn ->
      # Long-running AI operation
      result = HAL.AI.Router.route(message, session_id: state.id)

      # Check in with watchdog
      HAL.Watchdog.heartbeat(self())

      GenServer.reply(from, result)
    end)

    {:noreply, state}
  end
end
```

### 3. Session Timeout Management ✅ COMPLETE (MODIFIED)
**Problem:** Idle sessions consume memory

**Solution:** Spawn-on-demand with automatic termination

**Implementation:**
- Sessions spawn only when user sends first message
- Auto-terminate after 30 minutes of inactivity
- State persists to database before termination
- Re-spawn on next user message
- Memory scales with active users, not total users

**SessionCleaner repurposed:**
- Manual cleanup only for explicitly archived sessions
- 7-day grace period before deletion
- No automatic idle timeout
- Spawn-on-demand handles memory management

```elixir
defmodule HAL.Gateway.SessionCleaner do
  use GenServer

  def init(_) do
    schedule_cleanup()
    {:ok, %{}}
  end

  def handle_info(:cleanup_old_sessions, state) do
    # Only clean up archived sessions older than 7 days
    cutoff = DateTime.add(DateTime.utc_now(), -7, :day)

    HAL.Sessions.list_archived_before(cutoff)
    |> Enum.each(fn session ->
      Logger.info("Deleting archived session #{session.id}")
      HAL.Sessions.delete_session(session)
    end)

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    # Check every 24 hours
    Process.send_after(self(), :cleanup_old_sessions, :timer.hours(24))
  end
end
```

### 4. Dead Man's Switch (Proactive Alerts) 🔶 TODO
**Problem:** HAL could be "up" but not actually working

**Solution:** Periodic external notification proving HAL is functional

```elixir
defmodule HAL.DeadMansSwitch do
  use GenServer

  # Send a message to Telegram every 6 hours to prove HAL is alive
  def init(_) do
    schedule_check_in()
    {:ok, %{}}
  end

  def handle_info(:check_in, state) do
    # Send message to configured admin channel
    admin_channel = Application.get_env(:hal, :admin_channel)

    message = """
    ✅ HAL Status Report (#{DateTime.utc_now()})

    Uptime: #{format_uptime()}
    Active Sessions: #{HAL.Dashboard.count_active_sessions()}
    Messages Today: #{HAL.Dashboard.count_messages_today()}
    Memory: #{:erlang.memory(:total) / 1_048_576 |> Float.round(1)} MB

    All systems operational.
    """

    HAL.Channels.Telegram.send_message(admin_channel, message)

    schedule_check_in()
    {:noreply, state}
  end

  defp schedule_check_in do
    # Every 6 hours
    Process.send_after(self(), :check_in, :timer.hours(6))
  end

  defp format_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    seconds = div(uptime_ms, 1000)
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{minutes}m"
  end
end
```

### 5. Restart Recovery (State Restoration) ✅ Mostly There
**What we have:**
- Sessions persisted to database
- Can restore session state on restart

**Enhancement needed:**
```elixir
defmodule HAL.Gateway.SessionManager do
  def init(_) do
    # On startup, restore active sessions from database
    HAL.Sessions.list_active()
    |> Enum.each(fn session ->
      {:ok, _pid} = start_session(session)
    end)

    {:ok, %{}}
  end
end
```

---

## Recommended Implementation Priority

### Phase 1: Essential (< 1 day)
1. ✅ Health check endpoints (DONE)
2. ✅ Session timeout cleanup (DONE - SessionCleaner integrated)
3. 🔶 Startup session restoration

### Phase 2: Enhanced Monitoring (< 2 days)
4. 🔶 Watchdog for hung processes
5. 🔶 Dead man's switch notifications

### Phase 3: Advanced (Optional)
6. Circuit breaker for failing external services
7. Distributed monitoring (if running multiple HAL instances)
8. Automatic failover

---

## External Monitoring Setup (Mac Mini)

### Option A: launchd Keepalive (Built-in macOS)
```xml
<!-- ~/Library/LaunchAgents/com.hal.agent.plist -->
<dict>
  <key>Label</key>
  <string>com.hal.agent</string>

  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
    <!-- Restart if process exits with non-zero -->
  </dict>

  <key>StandardErrorPath</key>
  <string>/Users/you/Library/Logs/hal/error.log</string>
</dict>
```

### Option B: UptimeRobot (Free External Monitoring)
- Monitor: `http://your-mac-mini.local:4000/health/ready`
- Alert: Email/SMS if down for > 5 minutes
- Free tier: 50 monitors, 5-minute intervals

### Option C: Custom Monitoring Script
```bash
#!/bin/bash
# check_hal.sh - Run via cron every 5 minutes

HEALTH_URL="http://localhost:4000/health/ready"

if ! curl -f -s "$HEALTH_URL" > /dev/null; then
  echo "HAL is down! Restarting..."
  launchctl kickstart -k gui/$(id -u)/com.hal.agent

  # Send alert
  osascript -e 'display notification "HAL was down and has been restarted" with title "HAL Alert"'
fi
```

---

## Summary: Heartbeat Strategy for HAL

| Component | Purpose | Status | Priority |
|-----------|---------|--------|----------|
| OTP Supervision | Auto-restart crashed processes | ✅ Built-in | Essential |
| Health Endpoints | External monitoring | ✅ Done | Essential |
| Session Cleanup | Remove archived sessions | ✅ Done | Medium |
| Spawn-on-demand | Memory-efficient sessions | ✅ Done | High |
| Memory System | Semantic memory with pgvector | ✅ Done | High |
| Proactive Agent | Reasoning-based actions | ✅ Done | Medium |
| Watchdog | Detect hung processes | 🔶 TODO | Medium |
| Dead Man's Switch | Proactive alerts | 🔶 TODO | Low |
| launchd Keepalive | OS-level restart | 🔶 TODO | High |

**Bottom Line:** OTP gives you heartbeat functionality via supervision trees. We have added:
1. ✅ Session cleanup (spawn-on-demand + manual archival cleanup)
2. ✅ External monitoring (health endpoints)
3. ✅ Memory system (semantic memory with pgvector)
4. ✅ Proactive agent (reasoning-based autonomous actions)
5. 🔶 OS-level keepalive (launchd) - TODO

This gives you true 24/7 reliability with automatic recovery and intelligent proactive behavior.
