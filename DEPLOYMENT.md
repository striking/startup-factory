# HAL Deployment Guide

This guide covers deploying HAL to a Mac mini for production use as an autonomous personal AI assistant.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Environment Configuration](#environment-configuration)
- [Building the Release](#building-the-release)
- [Service Installation](#service-installation)
- [Backup and Restore](#backup-and-restore)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)

---

## Prerequisites

### Required Software

1. **Elixir 1.15+** with Erlang/OTP 26+
   ```bash
   brew install elixir
   elixir --version  # Should show 1.15.x or higher
   ```

2. **PostgreSQL 16+**
   ```bash
   brew install postgresql@16
   brew services start postgresql@16
   ```

3. **Claude Code CLI** (for AI capabilities)
   ```bash
   npm install -g @anthropic-ai/claude-code
   claude auth login  # Follow prompts to authenticate
   ```

4. **Git** (usually pre-installed on macOS)
   ```bash
   git --version
   ```

### Optional Software

- **Node.js** (if using assets pipeline)
  ```bash
  brew install node
  ```

### System Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 2 cores | 4+ cores (M1/M2/M3) |
| RAM | 4 GB | 8+ GB |
| Disk | 10 GB | 50+ GB |
| macOS | 12.0+ | 14.0+ |

---

## Quick Start

For experienced users, here's the quick deployment path:

```bash
# 1. Clone the repository
cd ~/dev/concepts/hal

# 2. Copy and configure environment
cp .env.production ~/.hal.env
# Edit ~/.hal.env with your API keys and tokens

# 3. Generate secrets
mix phx.gen.secret  # Copy output to SECRET_KEY_BASE in ~/.hal.env

# 4. Create production database
createdb hal_prod

# 5. Run deployment
chmod +x scripts/*.sh
./scripts/deploy.sh

# 6. Verify
./scripts/health_check.sh
open http://localhost:4000/dashboard
```

---

## Detailed Setup

### Step 1: Clone and Configure

```bash
# Navigate to project
cd ~/dev/concepts/hal

# Install Elixir dependencies
mix deps.get
```

### Step 2: Configure Environment

1. Copy the production environment template:
   ```bash
   cp .env.production ~/.hal.env
   ```

2. Generate a secure secret key:
   ```bash
   mix phx.gen.secret
   ```

3. Edit `~/.hal.env` with your values:
   ```bash
   nano ~/.hal.env
   ```

   **Required values:**
   - `SECRET_KEY_BASE` - The key generated above
   - `DATABASE_URL` - Usually `postgresql://localhost/hal_prod`

   **Optional but recommended:**
   - `TELEGRAM_BOT_TOKEN` - From @BotFather
   - `SLACK_BOT_TOKEN` - From Slack App settings
   - `DISCORD_BOT_TOKEN` - From Discord Developer Portal
   - `GOOGLE_AI_API_KEY` - For Gemini integration
   - `ELEVENLABS_API_KEY` - For voice synthesis

### Step 3: Set Up Database

```bash
# Create the production database
createdb hal_prod

# Verify connection
psql hal_prod -c "SELECT 1"
```

### Step 4: Authenticate Claude Code

```bash
# Login to Claude Code (uses your Anthropic subscription)
claude auth login

# Verify authentication
claude --version
```

---

## Environment Configuration

### Environment Variables Reference

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | Yes | PostgreSQL connection URL |
| `SECRET_KEY_BASE` | Yes | Phoenix secret key (64+ chars) |
| `PHX_HOST` | No | Hostname (default: localhost) |
| `PORT` | No | HTTP port (default: 4000) |
| `TELEGRAM_BOT_TOKEN` | No | Telegram bot token |
| `SLACK_BOT_TOKEN` | No | Slack bot token (xoxb-...) |
| `SLACK_APP_TOKEN` | No | Slack app token (xapp-...) |
| `DISCORD_BOT_TOKEN` | No | Discord bot token |
| `GOOGLE_AI_API_KEY` | No | Gemini API key |
| `OPENAI_API_KEY` | No | OpenAI API key (for Whisper/Codex) |
| `ELEVENLABS_API_KEY` | No | ElevenLabs API key (TTS) |
| `ELEVENLABS_VOICE_ID` | No | Voice ID (default: Rachel) |
| `AI_ROUTING_ENABLED` | No | Enable smart AI routing (default: true) |
| `POOL_SIZE` | No | Database connection pool (default: 10) |

### Environment File Locations

The release looks for environment files in this order:
1. `${RELEASE_ROOT}/.env` - Release directory
2. `~/.hal.env` - User home directory (recommended)

---

## Building the Release

### Manual Build

```bash
cd ~/dev/concepts/hal

# Clean previous builds
rm -rf _build/prod

# Fetch production dependencies
MIX_ENV=prod mix deps.get --only prod

# Compile
MIX_ENV=prod mix compile

# Build release
MIX_ENV=prod mix release

# The release will be at: _build/prod/rel/hal/
```

### Using Deploy Script

The deploy script handles everything:

```bash
./scripts/deploy.sh
```

Options:
- `./scripts/deploy.sh deploy` - Full deployment (default)
- `./scripts/deploy.sh build` - Build only, don't install service
- `./scripts/deploy.sh stop` - Stop the service
- `./scripts/deploy.sh start` - Start the service
- `./scripts/deploy.sh restart` - Restart the service
- `./scripts/deploy.sh status` - Check service status

---

## Service Installation

### Launchd Service

HAL runs as a launchd user agent, which:
- Starts automatically when you log in
- Restarts automatically if it crashes
- Logs output to `~/Library/Logs/hal/`

### Manual Installation

If you prefer to install the service manually:

1. Copy the plist template:
   ```bash
   cp com.hal.assistant.plist ~/Library/LaunchAgents/
   ```

2. Edit with your username and paths:
   ```bash
   nano ~/Library/LaunchAgents/com.hal.assistant.plist
   ```

3. Load the service:
   ```bash
   launchctl load ~/Library/LaunchAgents/com.hal.assistant.plist
   ```

### Service Commands

```bash
# Start
launchctl load ~/Library/LaunchAgents/com.hal.assistant.plist

# Stop
launchctl unload ~/Library/LaunchAgents/com.hal.assistant.plist

# Check status
launchctl list | grep hal

# View logs
tail -f ~/Library/Logs/hal/stdout.log
```

---

## Backup and Restore

### Automated Backups

Set up daily backups with cron:

```bash
# Edit crontab
crontab -e

# Add this line for daily backup at 2 AM:
0 2 * * * /Users/YOUR_USERNAME/dev/concepts/hal/scripts/backup.sh >> ~/Library/Logs/hal/backup.log 2>&1
```

### Manual Backup

```bash
./scripts/backup.sh
```

Backups are stored in `~/backups/hal/` with 7-day retention.

### Restore from Backup

```bash
# List available backups
./scripts/restore.sh --list

# Restore latest backup
./scripts/restore.sh

# Restore specific backup
./scripts/restore.sh ~/backups/hal/hal_backup_20260128_020000.sql.gz
```

**Warning**: Restore will drop and recreate the database!

---

## Monitoring

### Health Check

```bash
# Full health check
./scripts/health_check.sh

# Quick check (exit code only)
./scripts/health_check.sh --quiet

# JSON output (for monitoring systems)
./scripts/health_check.sh --json
```

### Dashboard

Access the web dashboard:
- **HAL Dashboard**: http://localhost:4000/dashboard
- **Phoenix LiveDashboard**: http://localhost:4000/dev/dashboard (dev only)

### Logs

```bash
# View live logs
tail -f ~/Library/Logs/hal/stdout.log

# View errors
tail -f ~/Library/Logs/hal/stderr.log

# View all logs with less
less +F ~/Library/Logs/hal/stdout.log
```

### Metrics

HAL exposes telemetry metrics that can be viewed in the Phoenix LiveDashboard:
- Memory usage
- Process counts
- Database query times
- Request latencies

---

## Troubleshooting

### Common Issues

#### 1. Service Won't Start

**Symptoms**: `launchctl list` shows exit code instead of `-`

**Check logs**:
```bash
tail -50 ~/Library/Logs/hal/stderr.log
```

**Common causes**:
- Missing environment variables
- Database not running
- Port 4000 already in use

**Solutions**:
```bash
# Check if port is in use
lsof -i :4000

# Ensure PostgreSQL is running
brew services start postgresql@16

# Verify environment
cat ~/.hal.env | grep -v "^#" | grep -v "^$"
```

#### 2. Database Connection Failed

**Error**: `connection refused` or `database does not exist`

**Solutions**:
```bash
# Ensure PostgreSQL is running
brew services start postgresql@16

# Create database if missing
createdb hal_prod

# Test connection
psql hal_prod -c "SELECT 1"
```

#### 3. Claude Code Not Working

**Error**: `claude: command not found`

**Solutions**:
```bash
# Reinstall Claude Code
npm install -g @anthropic-ai/claude-code

# Verify installation
which claude

# Re-authenticate
claude auth login
```

#### 4. Release Build Fails

**Solutions**:
```bash
# Clean everything
rm -rf _build deps

# Fetch fresh dependencies
mix deps.get

# Compile with verbose errors
MIX_ENV=prod mix compile --verbose
```

#### 5. Out of Memory

**Symptoms**: Slow response, OOM kills

**Solutions**:
```bash
# Check current memory usage
ps aux | grep beam

# Reduce connection pool in ~/.hal.env
POOL_SIZE=5

# Restart service
./scripts/deploy.sh restart
```

### Log Analysis

Look for these patterns in logs:

| Pattern | Meaning | Action |
|---------|---------|--------|
| `CRASH REPORT` | Process crashed | Check supervision tree |
| `GenServer terminating` | GenServer died | Look at reason |
| `connection refused` | Database/API issue | Check connections |
| `timeout` | Slow response | Check load/network |
| `undef` | Missing function | Check code compatibility |

### Getting Help

1. Check the logs first
2. Run health check: `./scripts/health_check.sh`
3. Check GitHub issues
4. Review the PRD.md for intended behavior

---

## Maintenance

### Updating HAL

```bash
# Pull latest code
git pull origin main

# Deploy update
./scripts/deploy.sh
```

### Database Migrations

Migrations run automatically during deployment. To run manually:

```bash
# Via release
./_build/prod/rel/hal/bin/hal eval "Hal.Release.migrate()"

# Via mix (development)
MIX_ENV=prod mix ecto.migrate
```

### Log Rotation

Logs are not automatically rotated. Add to crontab:

```bash
# Weekly log rotation (keep 4 weeks)
0 0 * * 0 find ~/Library/Logs/hal -name "*.log" -mtime +28 -delete
```

Or use logrotate if installed:

```bash
brew install logrotate
```

### Updating Dependencies

```bash
# Check for updates
mix hex.outdated

# Update all dependencies
mix deps.update --all

# Rebuild release
./scripts/deploy.sh
```

### Security Updates

1. Keep Elixir/Erlang updated: `brew upgrade elixir`
2. Update dependencies monthly
3. Rotate secrets periodically
4. Review Claude Code permissions

---

## Architecture Notes

### Release Structure

```
_build/prod/rel/hal/
├── bin/
│   └── hal           # Main executable
├── lib/              # Compiled BEAM files
├── releases/
│   └── 0.1.0/
│       ├── elixir
│       ├── env.sh    # Runtime environment
│       ├── vm.args   # VM arguments
│       └── sys.config
└── erts-*/           # Embedded Erlang runtime
```

### Process Tree

```
hal_application
├── Hal.Repo (Database)
├── Hal.Gateway.Supervisor
│   ├── Hal.Gateway.SessionManager
│   ├── Hal.Gateway.Router
│   └── DynamicSupervisor (Sessions)
├── Hal.Channels.Telegram.Supervisor
├── HAL.Channels.Slack.Supervisor
├── Nostrum.Application (Discord)
├── Oban (Job Queue)
└── HalWeb.Endpoint (Phoenix)
```

### Port Usage

| Port | Service |
|------|---------|
| 4000 | Phoenix HTTP |
| 5432 | PostgreSQL |
| 9100-9200 | Erlang distribution (clustering) |

---

## Quick Reference

### Essential Commands

```bash
# Deploy
./scripts/deploy.sh

# Health check
./scripts/health_check.sh

# View logs
tail -f ~/Library/Logs/hal/stdout.log

# Stop service
launchctl unload ~/Library/LaunchAgents/com.hal.assistant.plist

# Start service
launchctl load ~/Library/LaunchAgents/com.hal.assistant.plist

# Backup
./scripts/backup.sh

# Restore
./scripts/restore.sh

# Database migrations
./_build/prod/rel/hal/bin/hal eval "Hal.Release.migrate()"

# Remote console
./_build/prod/rel/hal/bin/hal remote
```

### File Locations

| Purpose | Location |
|---------|----------|
| Project | `~/dev/concepts/hal/` |
| Release | `~/dev/concepts/hal/_build/prod/rel/hal/` |
| Environment | `~/.hal.env` |
| Service plist | `~/Library/LaunchAgents/com.hal.assistant.plist` |
| Logs | `~/Library/Logs/hal/` |
| Backups | `~/backups/hal/` |

---

## Support

- **PRD**: See `PRD.md` for product requirements
- **Agents**: See `AGENTS.md` for AI agent documentation
- **Issues**: Report issues on GitHub

---

*Last updated: 2026-01-28*
