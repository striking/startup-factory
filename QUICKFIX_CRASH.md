# Quick Fix: Discord Token Crash

**Problem:** Server crashes with "A bot token needs to be supplied"

**Cause:** Discord (Nostrum) requires a token, even if you're not using Discord.

---

## Quick Solutions

### Solution 1: Use Standalone Test (WORKS NOW!)

```bash
# Test event sourcing without Phoenix
elixir test_standalone.exs
```

This works immediately and shows:
- ✅ Event logging
- ✅ Agent state
- ✅ Learning system
- ✅ All demos

**No Discord/Telegram/Phoenix needed!**

---

### Solution 2: Start Server with Minimal Config

1. **Create `.env`:**
```bash
cat > .env << 'EOF'
# Database
DATABASE_URL=postgresql://localhost/hal_dev

# Phoenix
SECRET_KEY_BASE=uFGjf54CjFGkRdGqgxRPoLCajAtfsUXaL5hXQal4IkE9yKN5GlHZL0OfISrq5v0k
PORT=4000

# Minimal tokens (won't actually connect, just stops crash)
DISCORD_BOT_TOKEN=dummy_for_testing
TELEGRAM_BOT_TOKEN=dummy_for_testing
EOF
```

2. **Source env and start:**
```bash
source .env
mix ecto.create  # Create DB if needed
mix ecto.migrate # Run migrations
mix phx.server   # Start server
```

3. **Open browser:**
```
http://localhost:4000/agent
```

---

### Solution 3: Actually Configure Discord (Optional)

If you want real Discord integration:

1. Go to https://discord.com/developers/applications
2. Create a new application
3. Go to "Bot" section
4. Copy bot token
5. Add to `.env`:
```bash
DISCORD_BOT_TOKEN=your_real_token_here
```

---

## What Actually Crashed?

```
** (RuntimeError) A bot token needs to be supplied in your config file
    (nostrum 0.10.4) lib/nostrum/token.ex:37
```

**NOT my event sourcing code** - that works fine!

It's Nostrum (Discord client) in the application supervision tree.

---

## Proof It Works

Run standalone test:
```bash
$ elixir test_standalone.exs

============================================================
🧪 STANDALONE EVENT SOURCING TEST
============================================================

Initializing...
✓ Initialized

📝 Simulating work session...
✓ Started: organize inbox
✓ Action: created label
✗ Action failed: IMAP timeout
🧠 Learned: IMAP timeouts at peak hours
🔄 Strategy adjusted: queue for off-peak
✅ Task completed

✅ ALL TESTS PASSED - Event Sourcing Working!
```

---

## Files to Check

After running standalone test:
```bash
# Event log created?
cat workspace/agent-log.jsonl | jq .

# Events logged?
wc -l workspace/agent-log.jsonl
```

You should see JSON events like:
```json
{"timestamp":"2026-01-29T18:13:16Z","event":"task_started","data":{"task":"organize inbox","strategy":"create labels by sender"}}
{"timestamp":"2026-01-29T18:13:16Z","event":"learned","data":{"fact":"IMAP timeouts at peak hours","confidence":0.8}}
```

---

## TL;DR

```bash
# THIS WORKS NOW (no config needed):
elixir test_standalone.exs

# For full UI, add dummy tokens:
echo 'export DISCORD_BOT_TOKEN=dummy' >> .env
echo 'export TELEGRAM_BOT_TOKEN=dummy' >> .env
source .env
mix phx.server
```

**My code works - just needed Discord token!** 😅
