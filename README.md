# Startup Factory 🏭

An autonomous startup experiment engine built on Elixir/OTP.

**Philosophy:** Launch fast, fail cheap, iterate relentlessly. Every hypothesis gets a landing page, a small ad budget, and 72 hours to prove itself.

## How It Works

```
Idea Queue → Generate (v0) → Deploy (Vercel) → Validate (Ads) → Analyze → Scale/Pivot/Kill
```

1. **Ideas** come from various sources (manual input, trend monitoring, competitor analysis)
2. **v0.dev** generates landing pages from prompts in seconds
3. **Vercel** deploys instantly to unique URLs
4. **Small ad spend** drives traffic (Facebook/Google)
5. **Metrics** (signups, conversions) determine fate
6. **Decisions** are automated: scale winners, kill losers, pivot maybes

## Architecture

```
startup-factory/
├── lib/
│   ├── factory/                 # 🆕 Startup Factory context
│   │   ├── wallet.ex           # Budget management ($10/day cap)
│   │   ├── experiment.ex       # GenServer per experiment
│   │   ├── v0_client.ex        # v0.dev API integration
│   │   ├── deployer.ex         # Vercel deployment
│   │   ├── pipeline.ex         # Autonomous orchestration
│   │   └── supervisor.ex       # OTP supervision
│   ├── hal/                    # HAL foundation (memory, channels)
│   └── hal_web/                # Phoenix LiveView dashboard
├── python/                     # Claude Agent SDK (ErlPort)
└── experiments/                # Generated landing pages (gitignored)
```

## Quick Start

```bash
# Setup
mix deps.get
mix ecto.setup

# Configure (required)
export V0_API_KEY="your-v0-key"
export VERCEL_TOKEN="your-vercel-token"
export ANTHROPIC_API_KEY="your-claude-key"

# Run
iex -S mix phx.server
```

## Usage

### Queue Ideas

```elixir
# Simple hypothesis
Factory.Pipeline.queue_idea("Plumbers need an AI tool to generate invoices faster")

# Detailed hypothesis
Factory.Pipeline.queue_idea(%{
  hypothesis: "Electricians struggle to track job costs",
  target_audience: "Solo electricians in Australia",
  problem: "Manual spreadsheet tracking leads to undercharging",
  solution: "Automated job costing app with material estimation"
})
```

### Monitor Pipeline

```elixir
# Get status
Factory.Pipeline.status()
# => %{queued_ideas: 3, active_experiments: 2, budget_remaining_cents: 750}

# Trigger next experiment manually
Factory.Pipeline.trigger_next()
```

### Manage Experiments

```elixir
# List active
Factory.Experiment.list_all()

# Get details
Factory.Experiment.get("abc123")

# Record signup (webhook from landing page)
Factory.Experiment.record_signup("abc123", %{email: "user@example.com"})

# Record revenue
Factory.Experiment.record_revenue("abc123", 4900, "Stripe payment")

# Advance stage manually
Factory.Experiment.advance("abc123")

# Kill an experiment
Factory.Experiment.kill("abc123", "Pivot to different niche")
```

### Budget Management

```elixir
# Check wallet
Factory.Wallet.status()
# => %{
#   daily_budget_cents: 1000,
#   daily_remaining_cents: 450,
#   experiments: [...]
# }

# See remaining budget
Factory.Wallet.remaining_today()
```

## Experiment Lifecycle

| Stage | Duration | What Happens |
|-------|----------|--------------|
| ideation | instant | Hypothesis defined |
| generation | ~30s | v0 creates landing page |
| deployment | ~60s | Vercel deploys to URL |
| validation | 24-72h | Traffic from ads, collect signups |
| analysis | instant | Calculate CAC, conversion rate |
| decision | instant | Scale / Pivot / Kill |

## Decision Logic

- **Scale** 🚀: Conversion >5%, positive ROI
- **Pivot** 🔄: Some traction (>5 signups), CR >1%
- **Kill** 💀: <3 signups or CR <0.5%
- **Continue** ⏳: Inconclusive, need more data

## Budget Rules

- **Daily cap:** $10 (configurable)
- **Per experiment:** Max $50
- **Auto-pause:** Experiments exceeding burn rate
- **Daily reset:** Budget refreshes at midnight UTC

## Notifications

Results are reported to Telegram (if configured):

```
🧪 Experiment Complete: abc123

📊 Decision: SCALE

🚀 Strong signal! Time to double down.
```

## Coming Soon

- [ ] Facebook Ads API integration
- [ ] Google Ads API integration
- [ ] A/B variant testing
- [ ] Revenue tracking integration (Stripe webhooks)
- [ ] Dashboard UI (Phoenix LiveView)
- [ ] Automated pivot suggestions

## Credits

Built on top of [HAL](https://github.com/striking/hal), an autonomous agent framework.

Uses:
- [v0.dev](https://v0.dev) for AI-powered landing page generation
- [Vercel](https://vercel.com) for instant deployment
- [Elixir/OTP](https://elixir-lang.org) for bulletproof orchestration
