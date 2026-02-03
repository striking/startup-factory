# HAL - Personal AI Assistant Platform
## Product Requirements Document

**Version:** 1.0
**Date:** 2026-01-27
**Status:** Active Development
**Lead:** Chris O'Halloran

---

## Executive Summary

HAL is an Elixir/Phoenix reimplementation of clawdbot - a personal AI assistant that runs locally and provides unified access to Claude Code across multiple messaging platforms (Telegram, Slack, Discord), with voice capabilities, browser automation, and task scheduling.

**Why Elixir over Node.js (clawdbot's stack)?**
- Superior fault tolerance via OTP supervision trees
- Lightweight concurrent sessions (GenServers vs. heavy threads)
- Built-in real-time capabilities (Phoenix Channels + LiveView)
- Better scaling path for commercial/multi-tenant use
- Hot code reloading without downtime

**Target Deployment:** Mac mini (isolated, local-first)

**Primary Use Case:** Autonomous employee - proactive AI assistant with full system access

---

## Goals & Success Criteria

### Primary Goals
1. **Feature Parity with clawdbot** - Match core functionality of the reference implementation
2. **Extensibility** - Clean architecture for adding new channels, AI providers, and skills
3. **Reliability** - No single point of failure; automatic recovery from errors
4. **Performance** - Handle 10+ concurrent conversations without degradation

### Success Criteria
- ✅ Send message to Telegram → Claude Code responds contextually
- ✅ Multi-channel support (Telegram, Slack, Discord)
- ✅ Session continuity across conversations
- ✅ Voice input/output via Telegram
- ✅ Scheduled autonomous tasks (e.g., "Check GitHub daily at 9am")
- ✅ LiveView dashboard shows all active sessions in real-time
- ✅ 99.9% uptime with automatic supervisor recovery

---

## Technical Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────┐
│            Phoenix Gateway (Port 4000)          │
│  - WebSocket Control Plane (Phoenix Channels)  │
│  - Session Orchestration                       │
│  - LiveView Dashboard                          │
└──────────────┬──────────────────────────────────┘
               │
       ┌───────┴────────┐
       │                │
   ┌───▼────┐      ┌───▼────┐
   │Channels│      │AI Engine│
   │────────│      │─────────│
   │Telegram│      │Claude   │
   │Slack   │      │Code CLI │
   │Discord │      │Gemini   │
   └────────┘      │Codex    │
                   └────┬────┘
                        │
                ┌───────┴────────┐
                │                │
           ┌────▼─────┐   ┌─────▼────┐
           │Automation│   │  Voice   │
           │──────────│   │──────────│
           │Oban      │   │ElevenLabs│
           │Webhooks  │   │Whisper   │
           └──────────┘   └──────────┘
```

### Core Components

#### 1. Gateway Layer
- **SessionManager** - GenServer managing all active sessions
- **Session** - Individual GenServer per conversation (Telegram chat, Slack thread, etc.)
- **Router** - Routes incoming messages to appropriate sessions
- **Presence** - Tracks online users/channels

#### 2. Channel Connectors (Messaging Platforms)
- **Telegram** - via `ex_gram`
- **Slack** - via custom Slack API client
- **Discord** - via `nostrum`
- **WhatsApp** (future) - via Business API or Node.js bridge

#### 3. AI Providers
- **Claude Code** (Primary) - CLI wrapper for local Claude Code instance
  - Uses user's Anthropic subscription
  - Provides agentic loops, tools (Bash, Read, Write, WebSearch)
  - Session continuity with `--resume`
- **Gemini** - Direct API integration for lighter tasks
- **Codex** - OpenAI Codex for code-specific tasks
- **Multi-provider routing** - Route to appropriate model based on task type

#### 4. Voice Integration
- **TTS** - ElevenLabs API for text-to-speech
- **STT** - Whisper or AssemblyAI for speech-to-text
- **Voice Messages** - Handle Telegram/Discord voice messages

#### 5. Automation
- **Oban** - Persistent job queue with cron scheduling
- **Webhooks** - HTTP endpoints for external triggers
- **Proactive Tasks** - Agent-initiated actions (e.g., "Check email every hour")

#### 6. Browser Control (Future)
- **Chrome DevTools Protocol** - Headless browser automation
- **Wallaby** - Elixir-native browser testing/control

#### 7. LiveView Dashboard
- Real-time session monitoring
- Conversation history viewer
- Settings management
- Metrics & analytics

---

## Data Model

### Sessions Table
```sql
CREATE TABLE sessions (
  id UUID PRIMARY KEY,
  channel_type VARCHAR(50) NOT NULL, -- telegram, slack, discord
  channel_id VARCHAR(255) NOT NULL,  -- chat_id, channel_id, etc.
  user_id VARCHAR(255) NOT NULL,
  claude_session_id VARCHAR(255),    -- For Claude Code continuity
  settings JSONB DEFAULT '{}',
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP NOT NULL,
  last_activity TIMESTAMP NOT NULL,
  status VARCHAR(20) DEFAULT 'active' -- active, paused, archived
);

CREATE INDEX idx_sessions_channel ON sessions(channel_type, channel_id, user_id);
CREATE INDEX idx_sessions_activity ON sessions(last_activity);
```

### Messages Table
```sql
CREATE TABLE messages (
  id UUID PRIMARY KEY,
  session_id UUID REFERENCES sessions(id) ON DELETE CASCADE,
  role VARCHAR(20) NOT NULL,         -- user, assistant, system
  content TEXT NOT NULL,
  attachments JSONB DEFAULT '[]',
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP NOT NULL
);

CREATE INDEX idx_messages_session ON messages(session_id, created_at);
```

### Users Table
```sql
CREATE TABLE users (
  id UUID PRIMARY KEY,
  external_id VARCHAR(255) NOT NULL, -- Telegram user_id, Slack user_id
  platform VARCHAR(50) NOT NULL,
  username VARCHAR(255),
  settings JSONB DEFAULT '{}',
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE UNIQUE INDEX idx_users_external ON users(platform, external_id);
```

### Scheduled Tasks Table (Oban)
- Uses Oban's built-in schema
- Jobs can reference sessions for context

---

## Feature Specifications

### F1: Multi-Channel Messaging

**User Story:** As a user, I can message HAL from Telegram, Slack, or Discord and receive intelligent responses powered by Claude Code.

**Acceptance Criteria:**
- [ ] Send message in Telegram → HAL responds within 5 seconds
- [ ] Send message in Slack → HAL responds with @ mention
- [ ] Send message in Discord → HAL responds in same channel
- [ ] Context preserved within each platform's conversation
- [ ] Group chats respond only when @mentioned
- [ ] DMs respond to every message

**Technical Implementation:**
- Each connector is a supervised GenServer
- Incoming messages route through Gateway.Router
- SessionManager creates/retrieves appropriate Session GenServer
- Session calls Claude Code CLI with `--resume` for continuity

---

### F2: Claude Code Integration

**User Story:** As a user, I can ask HAL to perform coding tasks and it uses Claude Code's full capabilities (file access, bash commands, web search).

**Acceptance Criteria:**
- [ ] Claude Code CLI successfully invoked from Elixir
- [ ] Session continuity maintained across multiple prompts
- [ ] Tool usage (Bash, Read, Write, Edit) works correctly
- [ ] Structured output returned via `--output-format json`
- [ ] Long-running tasks don't timeout
- [ ] Errors handled gracefully with user feedback

**Technical Implementation:**
```elixir
# lib/hal/ai/claude_code.ex
def prompt(session_id, message, opts) do
  args = [
    "-p", message,
    "--output-format", "json",
    "--resume", session_id || generate_new_session_id(),
    "--allowedTools", opts[:allowed_tools] || default_tools()
  ]

  case System.cmd("claude", args, timeout: 60_000) do
    {output, 0} -> parse_response(output)
    {error, code} -> {:error, error}
  end
end
```

**Authentication:** Uses local Claude Code authentication (user's Pro/Max subscription)

---

### F3: Session Management

**User Story:** As a user, I can have multiple conversations happening simultaneously, and HAL remembers context for each.

**Acceptance Criteria:**
- [ ] Each Telegram chat gets isolated session
- [ ] Each Slack thread gets isolated session
- [ ] Sessions persist across HAL restarts
- [ ] Session history viewable in dashboard
- [ ] Can manually archive/delete sessions
- [ ] Max 100 messages in-memory, rest in DB

**Technical Implementation:**
- DynamicSupervisor spawns Session GenServer per unique (channel_type, channel_id, user_id)
- Session loads from DB on startup
- Periodic flush to DB (every 10 messages or 5 minutes)
- Registry for fast session lookup

---

### F4: Voice Capabilities

**User Story:** As a user, I can send voice messages to HAL and receive voice responses.

**Acceptance Criteria:**
- [ ] Telegram voice message → transcribed → sent to Claude
- [ ] Claude response → synthesized → sent as voice message back
- [ ] Support for both TTS and STT
- [ ] Voice quality is clear and natural
- [ ] Latency < 10 seconds for voice round-trip

**Technical Implementation:**
- Telegram voice message triggers download
- Speech-to-text via Whisper API or AssemblyAI
- Text sent to Claude Code
- Response synthesized via ElevenLabs
- Voice file uploaded back to Telegram

---

### F5: Scheduled Tasks & Automation

**User Story:** As a user, I can tell HAL "Check my GitHub every morning at 9am and summarize PRs" and it happens automatically.

**Acceptance Criteria:**
- [ ] Natural language scheduling: "every morning at 9am"
- [ ] Cron-like scheduling: "0 9 * * *"
- [ ] One-time scheduled tasks: "in 2 hours"
- [ ] Recurring tasks persist across restarts
- [ ] Can list/cancel scheduled tasks
- [ ] Failed tasks retry with exponential backoff

**Technical Implementation:**
```elixir
# lib/hal/workers/scheduled_task.ex
defmodule HAL.Workers.ScheduledTask do
  use Oban.Worker, queue: :scheduled

  def perform(%{args: %{"session_id" => sid, "prompt" => prompt}}) do
    HAL.Session.send_to_claude(sid, prompt)
    :ok
  end
end

# Schedule it
%{session_id: sid, prompt: "Check GitHub"}
|> HAL.Workers.ScheduledTask.new(schedule: "0 9 * * *")
|> Oban.insert()
```

---

### F6: LiveView Dashboard

**User Story:** As a user, I can open a web browser and see all my active HAL sessions, conversation history, and system stats in real-time.

**Acceptance Criteria:**
- [ ] Dashboard shows all active sessions
- [ ] Click session → view full conversation history
- [ ] Real-time updates (no refresh needed)
- [ ] System stats: message count, uptime, error rate
- [ ] Settings page for API keys, preferences
- [ ] Mobile-responsive design

**Technical Implementation:**
- Phoenix LiveView at `/dashboard`
- Subscribes to Phoenix.PubSub topics for real-time updates
- Tailwind CSS for styling
- Components: SessionCard, ChatMessage, StatsPanel

---

### F7: Multi-Provider AI Routing

**User Story:** As HAL, I can intelligently route tasks to the best AI provider (Claude Code for coding, Gemini for quick questions, Codex for code generation).

**Acceptance Criteria:**
- [ ] Coding tasks → Claude Code
- [ ] Simple questions → Gemini (faster, cheaper)
- [ ] Code generation → Codex
- [ ] User can override with `/claude` or `/gemini` command
- [ ] Fallback to Claude Code if primary fails

**Technical Implementation:**
```elixir
defmodule HAL.AI.Router do
  def route(message, opts \\ []) do
    provider = opts[:force_provider] || determine_provider(message)

    case provider do
      :claude_code -> HAL.AI.ClaudeCode.prompt(...)
      :gemini -> HAL.AI.Gemini.prompt(...)
      :codex -> HAL.AI.Codex.prompt(...)
    end
  end

  defp determine_provider(message) do
    cond do
      coding_task?(message) -> :claude_code
      simple_question?(message) -> :gemini
      true -> :claude_code
    end
  end
end
```

---

## Non-Functional Requirements

### Performance
- **Response Time:** < 5s for simple queries, < 30s for complex coding tasks
- **Concurrent Sessions:** Support 50+ simultaneous conversations
- **Memory:** < 500MB total for 10 active sessions
- **CPU:** < 20% average usage on Mac mini (M1/M2)

### Reliability
- **Uptime:** 99.9% (< 9 hours downtime per year)
- **Error Recovery:** Automatic supervisor restarts for crashed components
- **Data Persistence:** All sessions/messages persisted to Postgres
- **Graceful Degradation:** If Claude Code fails, queue messages and retry

### Security
- **API Keys:** Stored in environment variables, never in code
- **Session Isolation:** Users cannot access each other's sessions
- **Input Validation:** Sanitize all user input before processing
- **Rate Limiting:** Max 60 messages/minute per user

### Scalability
- **Horizontal Scaling:** Can run on multiple nodes via Erlang distribution
- **Database:** Postgres with connection pooling
- **Caching:** ETS for hot session data
- **Monitoring:** Telemetry + Prometheus metrics

---

## Dependencies

### External Services
- **Claude Code CLI** - Requires installation and authentication
- **Anthropic Subscription** - Pro/Max plan for API access
- **Telegram Bot Token** - From @BotFather
- **Slack App Token** - OAuth app in Slack workspace
- **Discord Bot Token** - From Discord Developer Portal
- **ElevenLabs API Key** - For TTS (optional)
- **Whisper/AssemblyAI** - For STT (optional)

### Elixir Dependencies
```elixir
# mix.exs
defp deps do
  [
    # Phoenix framework
    {:phoenix, "~> 1.7.11"},
    {:phoenix_ecto, "~> 4.4"},
    {:phoenix_live_view, "~> 0.20.2"},
    {:phoenix_live_dashboard, "~> 0.8.3"},

    # Database
    {:ecto_sql, "~> 3.11"},
    {:postgrex, ">= 0.0.0"},

    # Job queue
    {:oban, "~> 2.17"},

    # Messaging platforms
    {:ex_gram, "~> 0.52"},       # Telegram
    {:nostrum, "~> 0.8"},        # Discord
    {:slack, "~> 0.23"},         # Slack (or custom)

    # HTTP & JSON
    {:httpoison, "~> 2.2"},
    {:jason, "~> 1.4"},

    # Utilities
    {:telemetry, "~> 1.2"},
    {:uuid, "~> 1.1"},

    # Dev/Test
    {:credo, "~> 1.7", only: [:dev, :test]},
    {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
    {:ex_doc, "~> 0.31", only: :dev}
  ]
end
```

---

## Development Phases

### Phase 1: Foundation (Week 1-2)
**Goal:** Basic working system with Telegram + Claude Code

**Deliverables:**
- [ ] Phoenix app scaffolded
- [ ] Database schema & migrations
- [ ] Gateway supervision tree
- [ ] Session GenServer implementation
- [ ] Claude Code wrapper module
- [ ] Telegram connector
- [ ] Basic LiveView dashboard
- [ ] Deploy to Mac mini
- [ ] End-to-end test: Telegram → Claude → Response

**Success Metric:** Can send "What files are in this directory?" to Telegram and get accurate response

---

### Phase 2: Multi-Channel (Week 3)
**Goal:** Expand to Slack and Discord

**Deliverables:**
- [ ] Slack connector with OAuth
- [ ] Discord connector
- [ ] Channel abstraction layer
- [ ] Group chat support (@mention detection)
- [ ] Session persistence to DB
- [ ] Enhanced dashboard with channel filters

**Success Metric:** Same conversation works identically in Telegram, Slack, and Discord

---

### Phase 3: Voice & Automation (Week 4-5)
**Goal:** Add voice capabilities and scheduled tasks

**Deliverables:**
- [ ] ElevenLabs TTS integration
- [ ] Whisper/AssemblyAI STT
- [ ] Voice message handling in Telegram
- [ ] Oban job queue setup
- [ ] Cron scheduling UI
- [ ] Webhook endpoints
- [ ] Natural language scheduling parser

**Success Metric:** Send voice message to Telegram, get voice response back. Schedule "Check GitHub daily at 9am" and it works.

---

### Phase 4: Multi-Provider & Advanced (Week 6+)
**Goal:** AI provider routing and advanced features

**Deliverables:**
- [ ] Gemini integration
- [ ] Codex integration
- [ ] Smart routing logic
- [ ] Browser automation (Chrome CDP)
- [ ] Canvas/visual workspace (LiveView)
- [ ] Skills system (plugin architecture)
- [ ] User management & settings

**Success Metric:** Simple questions use Gemini (fast), coding uses Claude Code, user can force provider with commands

---

## Testing Strategy

### Unit Tests
- Each GenServer has isolated tests
- Mock external APIs (Claude Code, Telegram, etc.)
- Test supervision tree restart behavior
- Coverage target: 80%+

### Integration Tests
- End-to-end message flow (Telegram → Gateway → Claude → Response)
- Database persistence
- Oban job execution
- Phoenix Channel communication

### Manual Testing Checklist
- [ ] Send message in Telegram → Response received
- [ ] Send message in Slack → Response received
- [ ] Voice message → Voice response
- [ ] Schedule task → Executes at correct time
- [ ] Crash a Session GenServer → Auto-restarts
- [ ] Dashboard real-time updates

### Performance Testing
- Load test: 50 concurrent conversations
- Memory profiling with :observer
- Database query optimization

---

## Deployment

### Mac Mini Setup
```bash
# Install Elixir & Phoenix
brew install elixir
mix archive.install hex phx_new

# Install Claude Code CLI
npm install -g @anthropic-ai/claude-agent-sdk
claude auth login

# Clone & setup HAL
git clone [repo-url] ~/dev/hal
cd ~/dev/hal
mix deps.get
mix ecto.setup

# Configure
cp .env.example .env
# Edit .env with API keys

# Build release
MIX_ENV=prod mix release

# Run as service (launchd)
# Create ~/Library/LaunchAgents/com.hal.plist
```

### Environment Variables
```bash
# .env
DATABASE_URL=postgresql://localhost/hal_prod
SECRET_KEY_BASE=[generate with mix phx.gen.secret]
TELEGRAM_BOT_TOKEN=...
SLACK_BOT_TOKEN=...
DISCORD_BOT_TOKEN=...
ELEVENLABS_API_KEY=...
PHX_HOST=localhost
PORT=4000
```

### Monitoring
- Phoenix LiveDashboard at `/dashboard`
- Telemetry metrics
- Postgres query monitoring
- Oban job queue dashboard

---

## Success Metrics

### Week 1
- [ ] Telegram bot responds to simple questions
- [ ] Claude Code session continuity works
- [ ] Dashboard shows active session

### Week 3
- [ ] 3 channels working (Telegram, Slack, Discord)
- [ ] 10+ concurrent conversations without issues
- [ ] Session persistence across restarts

### Week 5
- [ ] Voice input/output working
- [ ] Scheduled tasks executing correctly
- [ ] 99% uptime over 1 week

### Week 8 (MVP Complete)
- [ ] Multi-provider routing
- [ ] Browser automation
- [ ] Commercial-ready for potential clients
- [ ] Full test suite passing

---

## Risks & Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Claude Code CLI unreliable | High | Medium | Add retry logic, fallback to direct API |
| Telegram API rate limits | Medium | Low | Implement rate limiting, queue messages |
| Mac mini hardware failure | High | Low | Daily backups, document setup for quick restore |
| Session memory leak | Medium | Medium | Periodic cleanup, monitoring, limits |
| Concurrent access bugs | High | Medium | Extensive testing, use Registry for isolation |

---

## Future Enhancements

### V2 Features (Post-MVP)
- [ ] WhatsApp integration
- [ ] Email integration (IMAP/SMTP)
- [ ] Calendar integration (Google Calendar)
- [ ] GitHub integration (PR reviews, issue triage)
- [ ] Custom skills marketplace
- [ ] Multi-user support (family/team)
- [ ] Mobile app (Phoenix LiveView Native)
- [ ] Analytics dashboard
- [ ] Cost tracking per session/provider

### Commercial Potential
- SaaS offering for teams
- White-label for enterprises
- Managed hosting service
- Skills/plugin marketplace

---

## References

- **Clawdbot Repository:** https://github.com/clawdbot/clawdbot
- **Claude Code Docs:** https://code.claude.com/docs
- **Phoenix Framework:** https://phoenixframework.org
- **Oban:** https://hexdocs.pm/oban
- **Ex_Gram (Telegram):** https://hexdocs.pm/ex_gram
- **Nostrum (Discord):** https://hexdocs.pm/nostrum

---

## Changelog

| Date | Version | Changes |
|------|---------|---------|
| 2026-01-27 | 1.0 | Initial PRD created |

---

**Approved By:** Chris O'Halloran
**Next Review:** End of Phase 1 (Week 2)
