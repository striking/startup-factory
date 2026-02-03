# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configure timezone database for Quantum scheduler
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :hal,
  ecto_repos: [Hal.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :hal, HalWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: HalWeb.ErrorHTML, json: HalWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Hal.PubSub,
  live_view: [signing_salt: "nzVoXVW3"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :hal, Hal.Mailer, adapter: Swoosh.Adapters.Local

# Approval execution
# When enabled, approved requests are enqueued for execution via Oban.
config :hal, HAL.Autonomy.Approvals, auto_execute: true

# Budget enforcement
# When enabled, autonomous turns will stop once the daily/monthly budget is exceeded.
config :hal, HAL.Costs.Budget, enforce_autonomy: true

# Inbound trust gating (OpenClaw-style pairing/allowlists)
config :hal, Hal.Security,
  dm_policy: :pairing,
  group_policy: :allowlist,
  dm_allowlist: [],
  group_allowlist: []

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Oban configuration
# Oban is used for background job processing and scheduled tasks
config :hal, Oban,
  repo: Hal.Repo,
  plugins: [
    # Prune completed/discarded jobs after 7 days
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    # Rescue stuck jobs after 30 minutes
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    # Enable cron scheduling for proactive notifications and tasks
    {Oban.Plugins.Cron,
     crontab: [
       # Calendar reminder check every 5 minutes
       {"*/5 * * * *", Hal.Notifications.Workers.CalendarReminderWorker},
       # Email urgent check every 10 minutes (uses Claude for urgency assessment)
       {"*/10 * * * *", Hal.Notifications.Workers.EmailAlertWorker},
       # Process any pending autonomous tasks every minute
       {"* * * * *", Hal.Tasks.TaskExecutorWorker, args: %{check_pending: true}},
       # Self-improvement analysis daily at 3 AM
       {"0 3 * * *", HAL.SelfImprovement.AnalyzerWorker},
       # Habit nudge check every 5 minutes
       {"*/5 * * * *", Hal.Habits.NudgeWorker}
     ]}
  ],
  queues: [
    # Default queue for general background jobs
    default: 10,
    # Scheduled tasks queue (lower concurrency for controlled execution)
    scheduled: 5,
    # Webhooks queue (lower concurrency, typically external calls)
    webhooks: 3,
    # Outbound messages queue (rate limited per channel)
    messages: 30
  ]

# Claude Agent SDK configuration
# Uses TypeScript SDK via Node.js Port for better streaming and session management
config :hal, HAL.AI.AgentSDK,
  # Model to use (claude-sonnet-4-5-20250929 for cost efficiency, claude-opus-4-5 for quality)
  model: "claude-sonnet-4-5-20250929",
  # Start port immediately (false = lazy start on first query)
  start_immediately: false

# HAL workspace directory (Moltbot pattern)
# Contains AGENTS.md, MEMORY.md, SOUL.md, USER.md, TOOLS.md, HEARTBEAT.md
# and memory/ directory for daily logs
config :hal, :workspace_dir, Path.expand("workspace")

# Quantum scheduler configuration
# Used for scheduled tasks and autonomous work heartbeat
config :hal, HAL.Scheduler,
  timezone: "Australia/Sydney",
  jobs: [
    # ============================================
    # HEARTBEAT (Autonomous Work)
    # ============================================
    # Main heartbeat - checks for autonomous work every 30 minutes
    # Uses rotation-based task selection via HeartbeatState
    heartbeat: [
      schedule: "*/30 * * * *",
      task: {HAL.Heartbeat, :check_for_work, []},
      overlap: false
    ],

    # ============================================
    # SCHEDULED TASKS (User-Configured)
    # ============================================
    # Morning briefing at 9am Sydney time (Mon-Fri)
    morning_briefing: [
      schedule: "0 9 * * 1-5",
      task: {HAL.ScheduledTasks, :morning_briefing, []}
    ],

    # Weekly review on Friday at 6pm
    weekly_review: [
      schedule: "0 18 * * 5",
      task: {HAL.ScheduledTasks, :weekly_review, []}
    ],

    # ============================================
    # MAINTENANCE (runs in quiet hours)
    # ============================================
    # Daily memory maintenance at 2am (won't disturb)
    daily_maintenance: [
      schedule: "0 2 * * *",
      task: {HAL.Autonomy, :work_cycle, []},
      overlap: false
    ],

    # ============================================
    # SELF-IMPROVEMENT (learns from delegation patterns)
    # ============================================
    # Daily analysis of delegation metrics at 3am
    # Auto-applies high-confidence suggestions (rate limited to 3/day)
    self_improvement: [
      schedule: "0 3 * * *",
      task: {HAL.SelfImprovement, :scheduled_run, []},
      overlap: false
    ]
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
