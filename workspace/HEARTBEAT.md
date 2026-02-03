# HEARTBEAT.md

HAL's periodic checklist. Rotate through these items 2-4 times per day.
Track completion in heartbeat-state.json to avoid redundant checks.

---

## Active Checklist

- [ ] **Memory Review** - Read today's memory/YYYY-MM-DD.md, extract important items to MEMORY.md
- [ ] **Git Status** - Check workspace/ for uncommitted changes, commit if significant
- [ ] **Project Health** - Quick check: does `mix compile` still pass?
- [ ] **Daily Log** - Ensure today's memory log exists, add summary if empty

## Proactive Work (Do Without Asking)

These can be done autonomously during heartbeats:

1. **Organize memory files** - Clean up, dedupe, improve formatting
2. **Update documentation** - Fix typos, improve clarity in AGENTS.md
3. **Commit workspace changes** - If you've made improvements, commit them
4. **Review and curate MEMORY.md** - Distill daily logs into long-term memory
5. **Clean up old heartbeat-state.json entries** - Remove stale data

## When to Reach Out

Notify Chris if:
- Something is broken (compile errors, test failures)
- Found something interesting worth sharing
- Been quiet for >8 hours (brief "still here" message)
- Calendar event coming up in <2 hours
- Urgent email detected

## When to Stay Quiet (HEARTBEAT_OK)

- Late night (23:00-08:00) unless urgent
- Weekend mornings before 10:00
- Nothing new since last check (<30 min ago)
- User is actively chatting (session active)
- All checks completed recently

---

## Check Intervals (Reference)

| Check | Interval | Notes |
|-------|----------|-------|
| Email headers | 2h | Just subjects, don't open |
| Calendar | 4h | Next 24-48 hours |
| Git status | 6h | Workspace changes |
| Memory maintenance | 24h | Daily curation |
| Weather | 8h | If relevant |

---

**Token Tip:** If nothing needs attention, just reply `HEARTBEAT_OK` to save tokens.
