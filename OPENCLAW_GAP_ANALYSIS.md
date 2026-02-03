# HAL vs OpenClaw (OpenCLAW) — Gap Analysis

Last checked: 2026-02-03

This document compares HAL’s current implementation (this repo) against the OpenClaw reference implementation (“OpenCLAW”), using:
- A local OpenClaw checkout (docs + source). On this machine it lives at `~/openclaw`.
- Note: upstream docs/repo URLs are referenced by OpenClaw’s docs, but this analysis is based on the local checkout in this run.

Goal: identify what we already match, what’s missing, and what to build next to create a reliable, always-on, OTP-native “replicant” that can operate 24/7 (directed + proactive).

---

## 1) What OpenClaw is (the parts that matter for parity)

OpenClaw’s core architectural ideas (as observed in `~/openclaw/docs/...`):

- **Gateway as an always-on control plane**: one long-running service owns messaging connections, sessions, tool policy, events, and serves both WS + HTTP on one port.
- **Typed protocol**: clients connect via a versioned WS protocol with schema validation and a connect snapshot (presence/health/policy).
- **Session-first design**: stable session keys map channels/accounts/peers → session transcripts; supports reset/list/resolve and continuity.
- **Tool policy chain**: tool availability is filtered by agent + provider + channel/group policy, with sandbox/elevated controls.
- **Heartbeat**: periodic agent turns; reads `HEARTBEAT.md`; “do nothing” uses `HEARTBEAT_OK`; supports active-hours gating and wake hooks.
- **Operator ergonomics**: “doctor/security audit” style commands for repairs, migrations, and safety checks.
- **Compatibility endpoints**: optional `POST /v1/chat/completions`, `POST /v1/responses`, plus `POST /tools/invoke`.
- **ACP bridge**: stdio bridge for IDEs that maps ACP sessions → gateway sessions.

---

## 2) Where HAL already matches OpenClaw well

### Parity snapshot (agentic/autonomy)

| Capability | OpenClaw | HAL (this repo) | Status | Notes |
|---|---|---|---|---|
| Persistent sessions | Yes | Yes | Done | Spawn-on-demand `SessionServer` + DB-backed message history |
| Session keys / identity | Yes | Yes | Done | `{channel_type, channel_id, user_id}` routes to a session |
| Tool execution layer | Yes | Yes | Done | `Hal.Tools.Executor` + handler modules + prime directives |
| Human approvals for high-impact tools | Yes | Yes | Done | `/approvals` UI + persisted `approval_requests` + Oban execution worker |
| Heartbeat / periodic autonomy | Yes | Yes | Done | Quantum + Oban Cron plugins + `HAL.Heartbeat` |
| Multi-agent orchestration | Yes | Yes | Partial | `HAL.MultiAgent.Orchestrator` exists; patterns still settling |
| Tool policy engine (channel/user/role based) | Yes | Yes | Done | Centralized in `Hal.Tools.Policy` and enforced by `Hal.Tools.Executor` |
| Inbound trust gating (DM pairing/allowlists) | Yes | Yes | Done | Router-level gate + pairing UI at `/security` |
| Control-plane protocol (WS RPC + snapshot) | Yes | No | Missing | LiveView UI exists; no external gateway protocol yet |

### Always-on + OTP foundations
- Strong OTP supervision in `lib/hal/application.ex` with dedicated supervisors and background schedulers.
- Spawn-on-demand per-session processes in `lib/hal/gateway/*` (Registry + DynamicSupervisor + SessionServer) match the “session-first” idea well.
- Proactive scheduling exists via **Quantum** (`HAL.Scheduler`) and **Oban** cron plugins (`config/config.exs`).

### Heartbeat / autonomy primitives
- Heartbeat polling using `workspace/HEARTBEAT.md` exists (`lib/hal/heartbeat.ex`).
- Time gating + “don’t interrupt the user” primitives exist (`lib/hal/autonomy/time_awareness.ex`).
- A clear *action boundary* model exists (`lib/hal/autonomy/authorization.ex`) — conceptually similar to OpenClaw tool/elevated policies.
- Rotation-based checks now call **real integrations** for email/calendar when credentials exist (`lib/hal/autonomy.ex`, `lib/hal/integrations/*`).

### A2UI direction
- HAL has an A2UI protocol layer (`lib/hal/a2ui.ex`), which aligns with OpenClaw’s “agents declare UI” approach.

### Reliability improvements (recent)
- **Non-blocking boot**: `HAL.AgentState` now loads event-sourced state via `handle_continue/2` (`lib/hal/agent_state.ex`).
- **Non-blocking event log writes**: `HAL.EventLog` now buffers writes through `HAL.EventLog.Writer` (`lib/hal/event_log.ex`, `lib/hal/event_log/writer.ex`).

### Tooling improvements (recent)
- “Tasks” tool handler now uses Linear instead of stub responses (`lib/hal/tools/handlers/tasks.ex`, `lib/hal/integrations/tasks.ex`).

### Human approvals (recent)
- Durable, UI-driven approvals for codops-impacting tools:
  - Tool calls create a persisted `approval_requests` row.
  - Human approves in the LiveView UI (`/approvals`).
  - Approved requests enqueue a durable Oban worker to execute.
  - Fixed the execution enqueue bug (invalid Oban unique keys) on **2026-02-03**.

### Mission Control UI (recent)
- A Mission Control-style LiveView exists at `/mission-control`:
  - Agent presence (`HAL.AgentRegistry`)
  - Task board (`autonomous_tasks`)
  - Approvals inline (approve/deny)
  - Live feed (`HAL.EventLog`)

### Safety improvements (recent)
- `HAL.Core.PrimeDirectives` now correctly reads tool args whether they arrive with atom keys or JSON string keys (`lib/hal/core/prime_directives.ex`).

### MCP ecosystem (recent)
- HAL now has an MCP client + supervisor (`lib/hal/mcp/client.ex`, `lib/hal/mcp/supervisor.ex`) and starts it in `lib/hal/application.ex`.

---

## 3) Biggest gaps vs OpenClaw (prioritized)

### P0 — Must-have for a safe 24/7 autonomous agent

1) **Context plumbing (tools + identity must work outside chat sessions)**
   - OpenClaw’s cron/heartbeat/session tools always run with a real session identity + policy context.
   - **Fixed (2026-02-02):** Autonomous tasks + multi-agent now run through `HAL.Autonomy.Brain.prompt/2` with `user_id + hal_session_id + channel` context, so tool calls can execute outside chat sessions.
   - Remaining: audit any other non-interactive workers that still call `Hal.AI.Router.route/2` without `:user_id` and move them to the same pattern.

2) **Inbound security controls (DM pairing + allowlists)**
   - **Implemented (2026-02-03):** pairing + allowlists via `Hal.Security`, enforced in `Hal.Gateway.Router` before session creation, with operator UI at `/security`.
   - Default posture: DMs require pairing; groups are allowlist-only.

3) **Tool policy enforcement (not just “tools exist”)**
   - **Implemented (2026-02-03):** `Hal.Tools.Policy` is the single policy surface and is enforced by `Hal.Tools.Executor` for every tool call (before directives/approvals).
   - Current rules: `role=owner` can run all tools; paired non-owners are limited to memory tools.
   - Note: the Agent SDK bridge still exposes HAL tool definitions, but policy prevents unauthorized execution.

4) **MCP integration is present but not yet “productized”**
   - The MCP client exists and can connect/call tools via stdio.
   - Missing (for OpenClaw-like leverage):
     - A HAL tool wrapper to expose MCP tools to Claude in a controlled way.
     - A policy layer for which MCP servers/tools are allowed per user/channel.
     - Timeouts/backpressure/observability around MCP calls.

5) **Start-up + I/O robustness**
   - Mostly addressed:
     - `HAL.AgentState` no longer blocks supervisor boot on replay.
     - `HAL.EventLog` no longer blocks callers on file writes.
   - Follow-ups recommended:
     - Ensure event log writes are serialized safely (current writer flush uses async Tasks).
     - Add bounded memory/backpressure behavior if disk is slow/unwritable.

### P1 — OpenClaw compatibility/control-plane parity

5) **Gateway control plane protocol**
   - OpenClaw has a WS RPC protocol, connect snapshot, presence/health, and versioning.
   - HAL has LiveView UI routes (`lib/hal_web/router.ex`) and session processes, but no external RPC protocol comparable to OpenClaw’s.

6) **Compatibility HTTP endpoints**
   - Missing equivalents of:
     - `POST /v1/chat/completions`
     - `POST /v1/responses`
     - `POST /tools/invoke`
   - These matter if you want to plug HAL into existing OpenAI/OpenResponses-compatible clients or automation glue.

7) **ACP bridge**
   - No `acp` stdio bridge exists today; implementing one would unlock IDE integrations that speak ACP.

8) **MCP client**
   - **Implemented** (see above), but still needs tool exposure + policy + hardening.

### P2 — Breadth features (nice, but after safety/control plane)

9) **Multi-channel breadth**
   - OpenClaw supports WhatsApp/iMessage/Signal/Teams/etc.
   - HAL currently targets Telegram/Slack/Discord (and web UI). Parity will require a channel abstraction + connector suite.

10) **Operator “doctor/security audit” ergonomics**
   - HAL has health endpoints, dashboards, resilience building blocks.
   - Missing: a single “make it work again” command (migrations, config audits, permissions checks, token health).

---

## 4) OTP-first architecture recommendations (to beat OpenClaw, not just copy it)

### A) Make the Gateway a true control plane (OTP-native)

Recommended top-level structure (conceptual):

- `Hal.Application`
  - `Hal.Gateway` (Supervisor)
    - `Registry` (sessions)
    - `DynamicSupervisor` (SessionServer children)
    - `Hal.Gateway.ControlPlane` (WS RPC + HTTP compatibility endpoints)
    - `Hal.Gateway.Presence` (connect snapshot, tick/ping, health)
    - `Hal.Gateway.Policy` (tool + routing policy engine)
    - `Hal.Gateway.Security` (pairing + allowlists)
  - `HAL.Heartbeat` + scheduler
  - `Oban` workers (event-driven “wake”, reminders, background tool jobs)

Key principle: **Claude decides; HAL executes**. HAL should present context and policy constraints; Claude should choose the action plan.

### B) Replace “hardcoded autonomy logic” with “context + model choice”

OpenClaw heartbeats are basically: “here’s the workspace + checklist + constraints; decide if anything needs doing.”

HAL should converge to:
- One autonomy loop (one owner) for proactive operation per user/agent.
- It runs periodic turns and event-driven turns (“wake on new email”, “wake on job exit”).
- It emits structured events (so the rest of the system can react deterministically).

### C) Reliability: keep GenServers thin and non-blocking

To support 24/7 uptime:
- Move heavy state rebuilds to `handle_continue/2` (boot must stay fast).
- Don’t do blocking file I/O in hot paths; buffer or isolate it.
- Don’t serialize all work through a single GenServer (use Task supervision/pools).

### D) Security: treat every inbound channel as hostile content

Minimum OpenClaw-equivalent posture for “always on”:
- DM pairing by default; allowlists for groups/channels.
- Tool allowlists by default (deny-by-default for exec/write/edit).
- Sandboxed execution for anything touching shell/files/web, unless explicitly trusted.
- A single “security audit” report (config + network exposure + tool blast radius).

---

## 5) Concrete next steps (suggested implementation order)

### Phase 0 (stability/safety)
1. Add DM pairing + allowlist enforcement to message ingress (Router-level gate).
2. Introduce a unified policy engine for tool permissions; enforce it for Claude Code `allowed_tools` and HAL tool handlers.
3. Harden the event log writer (serialize writes + backpressure/alerts on failures).
4. Expose MCP via HAL tools (with strict allowlists per server/tool).

### Phase 1 (control plane parity)
5. Add `POST /tools/invoke` (simple, high leverage) backed by HAL’s tool executor + policy engine.
6. Add `POST /v1/chat/completions` + SSE streaming (optional at first).
7. Add `POST /v1/responses` (item-based input; can be “subset compatible” initially).

### Phase 2 (ecosystem)
8. Implement ACP bridge (`hal acp`) to map IDE ACP sessions to HAL sessions.
9. Add MCP client support for OpenClaw-style integrations (or an equivalent “skills/tools” ecosystem).

---

## Appendix: key HAL files touched by this analysis

- Core supervision: `lib/hal/application.ex`
- Session control plane: `lib/hal/gateway/gateway.ex`, `lib/hal/gateway/session_manager.ex`, `lib/hal/gateway/session_server.ex`, `lib/hal/gateway/router.ex`
- Heartbeat/autonomy: `lib/hal/heartbeat.ex`, `lib/hal/autonomy.ex`, `lib/hal/autonomy/*`
- Persistence: `lib/hal/event_log.ex`, `lib/hal/agent_state.ex`
- Tool system: `lib/hal/tools.ex`, `lib/hal/tools/*`
- A2UI: `lib/hal/a2ui.ex`
