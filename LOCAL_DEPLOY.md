# Local Deploy (Dev)

This is the fastest way to run HAL locally for a multi-week testing period.

## 1) Prereqs

- Postgres running locally (`config/dev.exs` uses `postgres/postgres` on `hal_dev`)
- Node installed (required for the Claude Agent SDK bridge)
- Optional: `codex` installed for Codex delegation

## 2) One-time setup

```bash
mix deps.get
mix ecto.setup
```

## 3) Preflight

```bash
mix hal.doctor
```

## 4) Run

```bash
PORT=4004 mix phx.server
```

Then open:

- `http://localhost:4004/` (Dashboard)
- `http://localhost:4004/mission-control` (Mission Control)
- `http://localhost:4004/chat` (Web chat)
- `http://localhost:4004/approvals` (Human approvals)
- `http://localhost:4004/changes` (Codops change requests)
- `http://localhost:4004/security` (Pairing / inbound trust gating)

## 5) Inbound security (pairing + allowlists)

By default:
- DMs require pairing (`HAL_DM_POLICY=pairing`)
- Groups are allowlist-only (`HAL_GROUP_POLICY=allowlist`)

Useful env vars:
```bash
# DMs: pairing | allowlist | open | disabled
HAL_DM_POLICY=pairing

# Groups: allowlist | open | disabled
HAL_GROUP_POLICY=allowlist

# Comma-separated pairs (platform/id)
HAL_DM_ALLOWLIST=telegram:123456789,slack:U123
HAL_GROUP_ALLOWLIST=telegram:-1001234567890,slack:C123
```

## 6) Quick smoke tests

1. (Optional) Send the bot a DM (Telegram/Slack/Discord) and confirm you get a pairing code; approve it in `http://localhost:4004/security`.
2. In `http://localhost:4004/chat`, ask HAL to delegate a small coding task via `hal_delegate_to_codex`.
3. Open `http://localhost:4004/approvals` (or `http://localhost:4004/mission-control`) and approve the pending request.
4. Confirm the approval moves through `queued → running → completed` (or shows an error if delegation fails).
5. On `http://localhost:4004/mission-control`, confirm tasks + live feed update.
6. On `http://localhost:4004/` or `http://localhost:4004/mission-control`, click `Run heartbeat` to force an autonomy tick and confirm it doesn’t crash.
