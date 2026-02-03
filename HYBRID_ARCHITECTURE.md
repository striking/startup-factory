# Hybrid Architecture: Clawdbot + Elixir OTP Supervision

**Goal:** Get clawdbot's features (always-on, heartbeat, all integrations) with Elixir's OTP fault tolerance and GenServer management.

**Date:** 2026-01-27

---

## 🎯 The Best of Both Worlds

```
┌──────────────────────────────────────────────────────────┐
│           Elixir OTP Supervisor Layer                    │
│                                                          │
│  ┌────────────────────────────────────────────────┐    │
│  │  HAL.Application (Main Supervisor)             │    │
│  │  - Heartbeat monitoring                        │    │
│  │  - Auto-restart on failure                     │    │
│  │  - Health checks                               │    │
│  │  - Metrics & telemetry                         │    │
│  └───┬────────────────────────────────────────────┘    │
│      │                                                  │
│  ┌───▼──────────────┐  ┌──────────────┐  ┌──────────┐│
│  │ ClawdbotManager  │  │ RouterServer │  │Dashboard ││
│  │   GenServer      │  │  GenServer   │  │LiveView  ││
│  │  - Port manager  │  │  - Routes    │  │- Monitor ││
│  │  - Heartbeat     │  │  - Metrics   │  │- Control ││
│  └───┬──────────────┘  └──────────────┘  └──────────┘│
│      │                                                  │
└──────┼──────────────────────────────────────────────────┘
       │
       │ Erlang Port (stdin/stdout)
       │ with heartbeat protocol
       │
┌──────▼──────────────────────────────────────────────────┐
│           Clawdbot (Node.js Process)                     │
│                                                          │
│  - Pi Agent framework                                   │
│  - 12+ messaging channels                               │
│  - Multi-provider AI (Claude, GPT, Gemini, etc.)       │
│  - Browser automation                                   │
│  - Voice, Canvas, all features                         │
│  - Sends heartbeat every 5s                            │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

---

## 🏗️ How This Works

### 1. Elixir Starts and Supervises Clawdbot

**Elixir spawns clawdbot as an Erlang Port:**
```elixir
defmodule HAL.ClawdbotManager do
  use GenServer
  require Logger

  @heartbeat_interval 5_000  # 5 seconds
  @heartbeat_timeout 15_000  # 15 seconds

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Start clawdbot as a Port
    port = Port.open({:spawn_executable, clawdbot_path()}, [
      :binary,
      :exit_status,
      {:line, 1024},
      {:env, clawdbot_env()}
    ])

    # Monitor the port
    Process.flag(:trap_exit, true)

    # Start heartbeat timer
    schedule_heartbeat_check()

    {:ok, %{
      port: port,
      last_heartbeat: System.monotonic_time(:millisecond),
      status: :starting,
      restart_count: 0
    }}
  end

  # Receive heartbeat from clawdbot
  @impl true
  def handle_info({port, {:data, {:eol, "HEARTBEAT" <> _}}}, %{port: port} = state) do
    Logger.debug("Received heartbeat from clawdbot")
    {:noreply, %{state | last_heartbeat: System.monotonic_time(:millisecond)}}
  end

  # Check heartbeat timeout
  @impl true
  def handle_info(:check_heartbeat, state) do
    now = System.monotonic_time(:millisecond)
    time_since_heartbeat = now - state.last_heartbeat

    if time_since_heartbeat > @heartbeat_timeout do
      Logger.error("Clawdbot heartbeat timeout! Restarting...")
      restart_clawdbot(state)
    else
      schedule_heartbeat_check()
      {:noreply, state}
    end
  end

  # Handle port exit (crash)
  @impl true
  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    Logger.error("Clawdbot process exited: #{inspect(reason)}")

    if state.restart_count < 10 do
      # Auto-restart via supervisor
      {:stop, :restart, state}
    else
      # Too many restarts, alert user
      Logger.critical("Clawdbot failed 10 times, giving up")
      {:stop, :too_many_restarts, state}
    end
  end

  defp restart_clawdbot(state) do
    Port.close(state.port)
    # GenServer will be restarted by supervisor
    {:stop, :heartbeat_timeout, state}
  end

  defp clawdbot_path do
    Path.join([Application.app_dir(:hal), "priv", "clawdbot", "dist", "index.js"])
  end

  defp clawdbot_env do
    [
      {"NODE_ENV", "production"},
      {"CLAWDBOT_HEARTBEAT", "true"}
    ]
  end

  defp schedule_heartbeat_check do
    Process.send_after(self(), :check_heartbeat, @heartbeat_interval)
  end
end
```

### 2. Clawdbot Modified to Send Heartbeats

**In clawdbot's main process:**
```typescript
// clawdbot/src/heartbeat.ts
export function startHeartbeat() {
  // Send heartbeat to parent process (Elixir) via stdout
  setInterval(() => {
    console.log(`HEARTBEAT:${Date.now()}:${process.memoryUsage().heapUsed}`);
  }, 5000);
}

// In main.ts
if (process.env.CLAWDBOT_HEARTBEAT === 'true') {
  startHeartbeat();
}
```

### 3. Communication Protocol

**Elixir → Clawdbot (via Port stdin):**
```elixir
# Send commands to clawdbot
Port.command(port, Jason.encode!(%{
  type: "message",
  channel: "telegram",
  chat_id: 12345,
  text: "What's the weather?"
}) <> "\n")
```

**Clawdbot → Elixir (via stdout):**
```typescript
// In clawdbot, send responses back
process.stdout.write(JSON.stringify({
  type: "response",
  session_id: "...",
  text: "The weather is sunny"
}) + "\n");
```

---

## 🔥 Key Benefits

### ✅ Fault Tolerance (OTP)
```elixir
# If clawdbot crashes, supervisor restarts it
children = [
  {HAL.ClawdbotManager, []},
  {HAL.RouterServer, []},
  {HAL.MetricsCollector, []}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

**What this means:**
- Clawdbot crashes → Elixir detects it → Auto-restarts
- Supervisor handles backoff strategy
- Circuit breaker prevents infinite restart loops
- Can restart individual components

### ✅ Heartbeat Monitoring
```elixir
# Elixir monitors clawdbot health
# If no heartbeat for 15s → restart
# Can include metrics in heartbeat:
# - Memory usage
# - Active sessions
# - Error count
```

**What this means:**
- Detect hangs (not just crashes)
- Proactive restarts before full failure
- Metrics collection for monitoring

### ✅ All Clawdbot Features
- 12+ messaging channels (no reimplementation!)
- Multi-provider AI (Pi Agent)
- Browser automation (working)
- Voice, Canvas, everything
- Actively maintained by clawdbot team

### ✅ Elixir Control Layer
```elixir
# Can add Elixir-specific features:
# - Advanced routing logic
# - Rate limiting
# - Request queuing
# - Load balancing (multiple clawdbot instances)
# - Metrics aggregation
# - Custom dashboard (LiveView)
```

---

## 📋 Implementation Plan

### Phase 1: Basic Hybrid (Week 1)

**Goal:** Elixir starts clawdbot, monitors it, restarts on crash

**Tasks:**
1. Create `HAL.ClawdbotManager` GenServer
2. Spawn clawdbot as Erlang Port
3. Implement heartbeat protocol
4. Test crash recovery

**Deliverable:**
```bash
# Start Elixir
iex -S mix

# Elixir spawns clawdbot
# Clawdbot runs, sends heartbeats
# Kill clawdbot process → Elixir restarts it
```

### Phase 2: Communication Protocol (Week 2)

**Goal:** Bidirectional communication between Elixir and clawdbot

**Tasks:**
1. Define JSON protocol (commands/responses)
2. Implement Port stdin/stdout handling
3. Route messages through Elixir
4. Test end-to-end message flow

**Deliverable:**
```
Telegram message
  ↓
Clawdbot receives
  ↓
Sends to Elixir (via stdout)
  ↓
Elixir RouterServer processes
  ↓
Sends to AI (back to clawdbot via stdin)
  ↓
Response flows back
```

### Phase 3: Enhanced Monitoring (Week 3)

**Goal:** Full observability and control

**Tasks:**
1. Metrics collection (memory, sessions, errors)
2. LiveView dashboard showing clawdbot status
3. Manual restart/stop controls
4. Alert system (Telegram/email on failures)

**Deliverable:**
- Real-time dashboard showing clawdbot health
- Can restart clawdbot from web UI
- Alerts on failures

### Phase 4: Advanced Features (Week 4+)

**Optional enhancements:**
1. Multiple clawdbot instances (load balancing)
2. Session affinity (sticky sessions per channel)
3. Graceful shutdown (finish in-flight requests)
4. Hot reload (update clawdbot without downtime)
5. Circuit breaker (stop restarting if always failing)

---

## 🔧 Detailed Implementation

### File Structure
```
hal/
├── lib/
│   ├── hal/
│   │   ├── clawdbot/
│   │   │   ├── manager.ex          # GenServer managing Port
│   │   │   ├── supervisor.ex       # Supervises manager
│   │   │   ├── protocol.ex         # JSON protocol codec
│   │   │   └── heartbeat.ex        # Heartbeat monitoring
│   │   ├── router_server.ex        # Routes messages
│   │   └── metrics_collector.ex    # Collects metrics
│   └── hal_web/
│       └── live/
│           └── clawdbot_live.ex    # Monitoring dashboard
├── priv/
│   └── clawdbot/                   # Embedded clawdbot
│       ├── package.json
│       └── dist/
│           └── index.js            # Compiled clawdbot
└── mix.exs
```

### HAL.Clawdbot.Supervisor
```elixir
defmodule HAL.Clawdbot.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Manager spawns and monitors clawdbot
      {HAL.Clawdbot.Manager, []},

      # Metrics collector
      {HAL.Clawdbot.MetricsCollector, []},

      # Circuit breaker (prevents infinite restarts)
      {HAL.Clawdbot.CircuitBreaker, []}
    ]

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
  end
end
```

### HAL.Clawdbot.Protocol
```elixir
defmodule HAL.Clawdbot.Protocol do
  @moduledoc """
  JSON protocol for communication between Elixir and clawdbot.
  """

  # Commands sent TO clawdbot
  def encode_message(channel, chat_id, text) do
    Jason.encode!(%{
      type: "message",
      channel: channel,
      chat_id: chat_id,
      text: text
    }) <> "\n"
  end

  def encode_command(command, params) do
    Jason.encode!(%{
      type: "command",
      command: command,
      params: params
    }) <> "\n"
  end

  # Responses received FROM clawdbot
  def decode_line(line) do
    case Jason.decode(line) do
      {:ok, data} -> parse_message(data)
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp parse_message(%{"type" => "heartbeat"} = data) do
    {:heartbeat, %{
      timestamp: data["timestamp"],
      memory: data["memory"],
      sessions: data["sessions"]
    }}
  end

  defp parse_message(%{"type" => "response"} = data) do
    {:response, %{
      session_id: data["session_id"],
      text: data["text"]
    }}
  end

  defp parse_message(%{"type" => "error"} = data) do
    {:error, data["message"]}
  end

  defp parse_message(_), do: {:error, :unknown_type}
end
```

### Clawdbot Heartbeat Modification

**File: `clawdbot/src/supervisor.ts` (new file)**
```typescript
import { EventEmitter } from 'events';

export class ElixirSupervisor extends EventEmitter {
  private heartbeatInterval: NodeJS.Timeout | null = null;

  constructor() {
    super();
    this.startHeartbeat();
    this.setupStdinListener();
  }

  private startHeartbeat() {
    // Send heartbeat every 5 seconds
    this.heartbeatInterval = setInterval(() => {
      const heartbeat = {
        type: 'heartbeat',
        timestamp: Date.now(),
        memory: process.memoryUsage().heapUsed,
        sessions: this.getActiveSessionCount()
      };

      // Send to Elixir via stdout
      process.stdout.write(JSON.stringify(heartbeat) + '\n');
    }, 5000);
  }

  private setupStdinListener() {
    // Listen for commands from Elixir
    let buffer = '';

    process.stdin.on('data', (chunk) => {
      buffer += chunk.toString();
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';

      for (const line of lines) {
        if (line.trim()) {
          this.handleCommand(line);
        }
      }
    });
  }

  private handleCommand(line: string) {
    try {
      const command = JSON.parse(line);
      this.emit('command', command);
    } catch (error) {
      console.error('Invalid command from Elixir:', line);
    }
  }

  private getActiveSessionCount(): number {
    // Return count of active sessions
    // Implementation depends on clawdbot internals
    return 0;
  }

  destroy() {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
    }
  }
}

// In main.ts
import { ElixirSupervisor } from './supervisor';

if (process.env.SUPERVISED_BY_ELIXIR === 'true') {
  const supervisor = new ElixirSupervisor();

  supervisor.on('command', (command) => {
    // Handle commands from Elixir
    handleElixirCommand(command);
  });
}
```

---

## 🎯 Benefits Summary

| Feature | Pure Elixir (HAL) | Pure Clawdbot | Hybrid |
|---------|------------------|---------------|--------|
| **Fault tolerance** | ⭐⭐⭐⭐⭐ OTP | ⭐⭐⭐ systemd | ⭐⭐⭐⭐⭐ OTP supervises Node |
| **Heartbeat monitoring** | ⭐⭐⭐ Manual | ⭐⭐⭐ Manual | ⭐⭐⭐⭐⭐ Built-in |
| **All integrations** | ⭐⭐ Slow | ⭐⭐⭐⭐⭐ Done | ⭐⭐⭐⭐⭐ Done |
| **Memory efficiency** | ⭐⭐⭐⭐⭐ 2KB/session | ⭐⭐⭐ 10MB/conn | ⭐⭐⭐ Node overhead |
| **Development speed** | ⭐⭐ Slow | ⭐⭐⭐⭐⭐ Fast | ⭐⭐⭐⭐ Fast |
| **Auto-restart** | ⭐⭐⭐⭐⭐ OTP | ⭐⭐⭐ systemd | ⭐⭐⭐⭐⭐ OTP |
| **Observability** | ⭐⭐⭐⭐ Native | ⭐⭐⭐ Logs | ⭐⭐⭐⭐⭐ Both |
| **Customization** | ⭐⭐⭐⭐⭐ Full | ⭐⭐⭐⭐ Fork | ⭐⭐⭐⭐⭐ Full |

**Winner:** **Hybrid** - Gets all the benefits!

---

## 🚀 Getting Started

### Step 1: Clone Clawdbot Into Your HAL Project
```bash
cd /Users/chrisohalloran/dev/concepts/hal
mkdir -p priv/clawdbot
cd priv/clawdbot
git clone https://github.com/clawdbot/clawdbot .
npm install
npm run build
```

### Step 2: Add Supervisor to HAL
```elixir
# lib/hal/application.ex
children = [
  # Existing children...
  HAL.Repo,
  HAL.Gateway,

  # NEW: Clawdbot supervision
  {HAL.Clawdbot.Supervisor, []}
]
```

### Step 3: Test It
```bash
# Start HAL
mix phx.server

# Elixir will spawn clawdbot
# Monitor in dashboard
# Kill clawdbot → watch it restart
```

---

## 💡 Why This Is The Best Solution

1. **✅ OTP Fault Tolerance**
   - Clawdbot crashes → Elixir restarts it
   - Supervisor strategies (exponential backoff, circuit breaker)
   - Process isolation

2. **✅ All Clawdbot Features**
   - Don't reimplement anything
   - Get updates from clawdbot team
   - All 12+ channels work

3. **✅ Heartbeat Monitoring**
   - Detect hangs (not just crashes)
   - Proactive restarts
   - Health metrics

4. **✅ Elixir Control**
   - Advanced routing in Elixir
   - Multiple clawdbot instances
   - Load balancing
   - Custom dashboard

5. **✅ Future-Proof**
   - Can add more Node.js processes
   - Can wrap other tools
   - Can migrate gradually

---

## 🎯 Timeline

**Week 1:** Basic supervision (Elixir starts/monitors clawdbot)
**Week 2:** Communication protocol (bidirectional messages)
**Week 3:** Dashboard & monitoring
**Week 4:** Production deployment

**Total:** ~1 month to production-grade hybrid system

---

---

## 🧠 Memory System

HAL now includes a 4-tier memory architecture for personalized AI assistance:

### Architecture Overview
- **Tier 1:** Working memory (GenServer state) - Immediate conversation context
- **Tier 2:** Session cache (PostgreSQL) - Full conversation history
- **Tier 3:** Semantic memory (pgvector) - Cross-session learned facts
- **Tier 4:** Structured memory (PostgreSQL) - Queryable relational data

### Key Features
- Semantic similarity search using pgvector
- 1536-dimensional embeddings (OpenAI ada-002)
- Cosine distance for matching
- Cross-session memory retention
- User preference learning
- Context-aware responses

See [MEMORY_ARCHITECTURE.md](MEMORY_ARCHITECTURE.md) for detailed documentation.

---

## 🤖 Proactive Agent

HAL includes a reasoning-based proactive agent that autonomously takes actions based on context:

### How It Works
```
Quantum Scheduler
  ↓
  ├─ HAL.ScheduledTasks (definite, time-based)
  │   ├─ Morning briefing (9am daily)
  │   └─ Weekly review (Friday 6pm)
  │
  └─ HAL.Heartbeat (autonomous, every 15 min)
      ↓
      Check: Active user sessions?
      ├─ Yes → Skip (don't interrupt)
      └─ No → Call Claude Code as autonomous worker
          ↓
          Claude reviews context and decides work
          ↓
          Execute autonomous work
          ↓
          Learn from interaction (store in memory)
```

### Key Features
- **Two patterns:**
  - **ScheduledTasks:** User-configured tasks at specific times (briefings, reviews)
  - **Heartbeat:** Autonomous work finder every 15 minutes
- **Simple approach:** Just call Claude Code with clear goals, no structured parsing
- **Session awareness:** Heartbeat checks for active sessions, won't interrupt user
- **Agent autonomy:** Claude decides what work to do, not rigid action types
- **Memory integration:** Learns from every interaction

### Pattern
**Simple over complex.** No JSON parsing, no structured actions. Just give Claude a goal and let it figure out the workflow.

---

## 🚀 Spawn-on-Demand Sessions

HAL uses a memory-efficient spawn-on-demand session model:

### Lifecycle
1. **Spawn:** Session GenServer starts on first user message
2. **Active:** Handles conversation for up to 30 minutes
3. **Persist:** State saved to database before termination
4. **Terminate:** Auto-terminates after 30 minutes of inactivity
5. **Re-spawn:** Automatically spawns on next user message

### Benefits
- Memory scales with active users, not total users
- Idle sessions don't consume resources
- State persistence ensures continuity
- Crash isolation per session
- Automatic recovery via supervisor

### SessionCleaner Repurposed
- Manual cleanup only for archived sessions
- 7-day grace period before deletion
- No automatic idle timeout (spawn-on-demand handles this)

---

## 📊 Unified Channel Gateway

HAL uses `HAL.ChannelGateway` for unified message routing:

### Supported Channels
- Telegram
- Slack
- Discord
- Email (IMAP/SMTP)
- Terminal (CLI)

### Features
- Single entry point: `route_message/2`
- Automatic user creation/lookup
- Channel normalization
- Consistent message format across all channels

---

This gives you **EXACTLY** what you want:
- ✅ Clawdbot's features (always-on, all integrations)
- ✅ Elixir's OTP supervision
- ✅ Heartbeat monitoring
- ✅ Fault tolerance
- ✅ 4-tier memory system with semantic search
- ✅ Proactive agent with reasoning
- ✅ Spawn-on-demand session management
- ✅ Best of both worlds
