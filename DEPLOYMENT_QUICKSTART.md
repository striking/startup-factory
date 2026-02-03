# HAL Deployment Quick Start

Quick reference for deploying HAL to your Mac mini.

## Prerequisites Checklist

- [ ] Elixir 1.15+ installed (`brew install elixir`)
- [ ] PostgreSQL 16+ running (`brew install postgresql@16`)
- [ ] Claude Code CLI authenticated (`claude auth login`)
- [ ] Git installed (usually pre-installed)

## 5-Minute Setup

```bash
# 1. Navigate to project
cd ~/dev/concepts/hal

# 2. Run first-time setup
./scripts/setup.sh

# 3. Edit environment file (add your API tokens)
nano ~/.hal.env

# 4. Start HAL
./scripts/deploy.sh

# 5. Verify it's running
./scripts/health_check.sh
```

That's it! HAL will now start automatically on login via launchd.

## Daily Commands

```bash
# View logs
tail -f ~/Library/Logs/hal/stdout.log

# Check health
./scripts/health_check.sh

# Deploy updates
git pull && ./scripts/deploy.sh

# Restart service
./scripts/deploy.sh restart

# Backup database
./scripts/backup.sh
```

## Web Dashboard

Open in browser: http://localhost:4000/dashboard

## Configuration Files

| File | Purpose |
|------|---------|
| `~/.hal.env` | Production environment variables (API keys, tokens) |
| `~/Library/LaunchAgents/com.hal.assistant.plist` | Auto-start service configuration |
| `~/Library/Logs/hal/` | Application logs |
| `~/backups/hal/` | Database backups |

## Required Environment Variables

Edit `~/.hal.env` and configure:

```bash
# REQUIRED
DATABASE_URL=postgresql://localhost/hal_prod
SECRET_KEY_BASE=<run: mix phx.gen.secret>

# OPTIONAL (but recommended)
TELEGRAM_BOT_TOKEN=<from @BotFather>
SLACK_BOT_TOKEN=<from Slack App settings>
DISCORD_BOT_TOKEN=<from Discord Developer Portal>
GOOGLE_AI_API_KEY=<from Google AI Studio>
OPENAI_API_KEY=<from OpenAI dashboard>
ELEVENLABS_API_KEY=<from ElevenLabs>
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Service won't start | Check logs: `tail ~/Library/Logs/hal/stderr.log` |
| Database error | Ensure PostgreSQL is running: `brew services start postgresql@16` |
| Port already in use | Check what's using port 4000: `lsof -i :4000` |
| Claude Code not found | Reinstall: `npm install -g @anthropic-ai/claude-code` |

## Service Control

```bash
# Start
launchctl load ~/Library/LaunchAgents/com.hal.assistant.plist

# Stop
launchctl unload ~/Library/LaunchAgents/com.hal.assistant.plist

# Check status
launchctl list | grep hal
```

## Complete Documentation

For detailed documentation, see: [DEPLOYMENT.md](./DEPLOYMENT.md)

---

**Pro Tip**: Set up daily backups by adding this to your crontab:
```bash
crontab -e
# Add: 0 2 * * * ~/dev/concepts/hal/scripts/backup.sh
```
