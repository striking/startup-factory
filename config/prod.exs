import Config

# =============================================================================
# HAL Assistant - Production Configuration
# =============================================================================
#
# This file contains compile-time production configuration.
# Runtime configuration (secrets, environment variables) is in config/runtime.exs

# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Req

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# =============================================================================
# Logging Configuration
# =============================================================================
# Production log level (info, warning, or error recommended)
config :logger, level: :info

# Structured logging format for production
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id, :session_id, :channel]

# =============================================================================
# Phoenix Endpoint Configuration
# =============================================================================
# Enable server for releases (can be overridden by PHX_SERVER env var)
config :hal, HalWeb.Endpoint,
  server: true,
  # Cache static assets for 1 year (with digest)
  cache_static_manifest: "priv/static/cache_manifest.json",
  # Force SSL in production (uncomment when SSL is configured)
  # force_ssl: [hsts: true, rewrite_on: [:x_forwarded_proto]]
  check_origin: false

# =============================================================================
# Oban Configuration (Background Jobs)
# =============================================================================
# Production Oban configuration
config :hal, Oban,
  repo: Hal.Repo,
  plugins: [
    # Prune completed/discarded jobs after 7 days
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    # Rescue stuck jobs after 30 minutes
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    # Enable cron scheduling
    {Oban.Plugins.Cron,
     crontab: [
       # Clean up old sessions daily at 2 AM
       {"0 2 * * *", Hal.Workers.SessionCleanup},
       # Prune old messages weekly
       {"0 3 * * 0", Hal.Workers.MessagePruner}
     ]}
  ],
  queues: [
    default: 10,
    scheduled: 5,
    webhooks: 3,
    # High priority queue for real-time interactions
    priority: 20
  ]

# =============================================================================
# Quantum Scheduler Configuration
# =============================================================================
config :hal, HAL.Scheduler,
  jobs: [
    # Scheduled Tasks (user-configured, definite)
    {"0 9 * * *", {HAL.ScheduledTasks, :morning_briefing, []}},
    {"0 18 * * 5", {HAL.ScheduledTasks, :weekly_review, []}},
    # Autonomous Work Heartbeat (every 15 minutes)
    {"*/15 * * * *", {HAL.Heartbeat, :check_for_work, []}}
  ]

# =============================================================================
# ExGram (Telegram) Configuration
# =============================================================================
config :ex_gram,
  # Use webhook mode in production for better reliability
  method: :webhook

# =============================================================================
# Nostrum (Discord) Configuration
# =============================================================================
config :nostrum,
  # Log level for Discord gateway
  gateway_intents: [
    :guilds,
    :guild_messages,
    :direct_messages,
    :message_content
  ]

# =============================================================================
# Performance & Resource Limits
# =============================================================================
# ETS table configuration for session storage
config :hal, Hal.Sessions,
  # Maximum number of active sessions
  max_sessions: 1000,
  # Session timeout (4 hours)
  session_timeout: :timer.hours(4)

# Memory limits for AI operations
config :hal, Hal.AI,
  # Max context window size (tokens)
  max_context_tokens: 100_000,
  # Request timeout (30 seconds)
  request_timeout: :timer.seconds(30)

# =============================================================================
# Security Configuration
# =============================================================================
config :hal, Hal.Security,
  # Rate limiting per user (requests per minute)
  rate_limit: 30,
  # Maximum message size (100KB)
  max_message_size: 100_000

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
