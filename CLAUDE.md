# HAL Project

**Elixir/Phoenix Personal AI Assistant**

## NO SIMULATION RULE (NON-NEGOTIABLE)

**NEVER create simulated/mock/placeholder implementations without EXPLICIT disclosure.**

- ❌ NEVER say something "works" when it's returning fake data
- ❌ NEVER use placeholder API responses without telling the user
- ❌ NEVER imply a feature is functional when it's stubbed
- ✅ ALWAYS flag simulated code with `# SIMULATED:` comments
- ✅ ALWAYS tell the user upfront: "This is simulated because X doesn't exist yet"
- ✅ ALWAYS document simulation status in module @moduledoc

**If an API doesn't exist yet, say so. Don't pretend.**

## Core Principle

**Claude (Opus 4.5) via Agent SDK is THE BRAIN. The brain decides everything.**

```
User → HAL (Gateway) → Claude/Opus (THE BRAIN)
                              │
                              ├── Decides what to do
                              ├── Decides when to delegate
                              └── Calls specialist agents:
                                   ├── HAL.Agents.Codex (coding)
                                   ├── HAL.Agents.Jules (async background)
                                   └── HAL.Agents.Gemini (summarization)
```

**Anti-patterns:**
- ❌ HAL routing logic ("if task contains 'code', use Codex")
- ❌ Bypassing the brain (calling agents directly)
- ❌ Multiple decision makers

**Correct pattern:** Claude receives → Claude decides → Claude calls HAL tools → HAL executes

## Commands

```bash
# Development
mix compile                    # Build
mix test                       # Run tests
mix phx.server                 # Start server
iex -S mix phx.server          # Start with console

# Database
mix ecto.migrate               # Run migrations
mix ecto.reset                 # Reset database

# Quality
mix format                     # Format code
mix credo --strict             # Lint
```

## Definition of Done

Before declaring any task complete:

- [ ] `mix compile` passes (no errors)
- [ ] `mix test` passes
- [ ] `mix phx.server` starts without crashing
- [ ] Manual smoke test if UI changed

**Never say "done" without running the server.**

## Architecture

### Skills (Agent Skills Standard)

```
.claude/skills/
├── calendar-management/   # → HAL.Tools.Calendar (Elixir)
├── email-management/      # → HAL.Tools.Email (Elixir)
├── task-management/       # → HAL.Tasks (Elixir)
└── hal-memory/           # → HAL.Memory (Elixir)
```

- Skills = Instructions (progressive disclosure, ~100 tokens until activated)
- Tools = Elixir implementations in `lib/hal/`
- Prefer skills + CLIs over MCP (token efficient)

### Agent Delegation

```elixir
# lib/hal/agents/
├── supervisor.ex   # OTP supervisor
├── codex.ex       # OpenAI Codex (complex coding)
├── jules.ex       # Jules API (async background tasks)
└── gemini.ex      # Gemini (fast summarization/completion)
```

Claude decides. HAL executes via SDK/API.

### Key Modules

| Module | Purpose |
|--------|---------|
| `HAL.AI.AgentSDK` | Claude Agent SDK client |
| `HAL.AI.Router` | Routes to Claude/Gemini |
| `HAL.Agents.*` | External agent delegation |
| `HAL.Memory` | Semantic memory (pgvector) |
| `HAL.AgentState` | Event sourcing (JSONL + ETS) |
| `HAL.Gateway` | Channel handling |

### Environment Variables

```bash
# Required
DATABASE_URL=postgresql://localhost/hal_dev
SECRET_KEY_BASE=<mix phx.gen.secret>
ANTHROPIC_API_KEY=sk-ant-...

# Optional (channels)
TELEGRAM_BOT_TOKEN=...
DISCORD_BOT_TOKEN=...
SLACK_BOT_TOKEN=...

# Optional (agents)
OPENAI_API_KEY=...          # For Codex/Jules
GOOGLE_AI_API_KEY=...       # For Gemini
```

## Code Style

- Elixir standard: `mix format` enforced
- Use pattern matching over conditionals
- Prefer pipelines for transformations
- GenServers for stateful processes
- Supervisors for fault tolerance

## Testing

- Event sourcing: check `workspace/agent-log.jsonl`
- Memory: requires pgvector extension
- Channels: disabled without tokens (expected)
