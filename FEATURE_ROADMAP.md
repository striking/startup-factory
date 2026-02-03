# HAL Feature Parity Roadmap
## Building Clawdbot Features in Elixir

**Goal:** Add all clawdbot features to HAL while maintaining Elixir's superior OTP architecture

**Date:** 2026-01-27
**Timeline:** 2-3 months to full feature parity
**Strategy:** Prioritize high-value features first, build incrementally

---

## 📊 Current State vs Target State

### ✅ Already Implemented (HAL)
- [x] Phoenix application with OTP supervision
- [x] Session management (GenServers)
- [x] 3 messaging channels (Telegram, Slack, Discord)
- [x] 2 AI providers (Claude Code, Gemini)
- [x] Multi-provider routing
- [x] Voice (TTS/STT via ElevenLabs/Whisper)
- [x] Job scheduling (Oban + cron)
- [x] LiveView dashboard
- [x] Database persistence (Sessions, Messages, Users)
- [x] Deployment infrastructure
- [x] 407 passing tests

### 🎯 To Add (From Clawdbot)
- [ ] Health check endpoints (monitoring)
- [ ] 9 more messaging channels (WhatsApp, iMessage, Signal, etc.)
- [ ] 8 more AI providers (GPT-4, Mistral, xAI, etc.)
- [ ] Browser automation (headless Chrome)
- [ ] Email integration (IMAP/SMTP)
- [ ] Calendar integration (Google Calendar, iCal)
- [ ] GitHub integration (webhooks, PR reviews)
- [ ] Canvas/visual workspace
- [ ] Document processing (PDF, images)
- [ ] Advanced skills system

---

## 🗓️ Implementation Phases

### Phase 1: Foundation & Monitoring (Week 1) ⭐⭐⭐⭐⭐

**Goal:** Production-ready monitoring and observability

#### 1.1 Health Check Endpoints (Day 1 - 4 hours)
```elixir
# lib/hal_web/controllers/health_controller.ex
defmodule HalWeb.HealthController do
  use HalWeb, :controller

  def index(conn, _params) do
    json(conn, %{
      status: "healthy",
      version: Application.spec(:hal, :vsn),
      uptime_seconds: System.monotonic_time(:second),
      timestamp: DateTime.utc_now(),
      components: %{
        database: check_database(),
        telegram: check_channel(:telegram),
        slack: check_channel(:slack),
        discord: check_channel(:discord),
        claude_code: check_claude_code()
      },
      metrics: %{
        active_sessions: HAL.Dashboard.count_active_sessions(),
        messages_today: HAL.Dashboard.count_messages_today(),
        memory_mb: :erlang.memory(:total) / 1_048_576,
        process_count: :erlang.system_info(:process_count)
      }
    })
  end

  def ready(conn, _params) do
    # Kubernetes readiness probe
    if all_systems_ready?() do
      send_resp(conn, 200, "ready")
    else
      send_resp(conn, 503, "not ready")
    end
  end

  def live(conn, _params) do
    # Kubernetes liveness probe (quick check)
    send_resp(conn, 200, "alive")
  end

  defp check_database do
    case Ecto.Adapters.SQL.query(HAL.Repo, "SELECT 1") do
      {:ok, _} -> %{status: "connected", latency_ms: measure_db_latency()}
      {:error, _} -> %{status: "disconnected", error: "connection failed"}
    end
  end
end
```

**Routes:**
- `GET /health` - Detailed health info
- `GET /health/ready` - Readiness probe
- `GET /health/live` - Liveness probe

**Testing:** Write comprehensive tests for each endpoint

---

#### 1.2 Telemetry & Metrics (Day 2 - 4 hours)

**Add comprehensive telemetry:**
```elixir
# lib/hal/telemetry.ex
defmodule HAL.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # VM Metrics
      last_value("vm.memory.total", unit: :byte),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),

      # Database Metrics
      summary("hal.repo.query.total_time", unit: {:native, :millisecond}),
      summary("hal.repo.query.decode_time", unit: {:native, :millisecond}),

      # Session Metrics
      last_value("hal.sessions.active_count"),
      counter("hal.sessions.created_total"),
      counter("hal.sessions.crashed_total"),

      # Message Metrics
      counter("hal.messages.received_total"),
      counter("hal.messages.sent_total"),
      summary("hal.messages.processing_time", unit: {:native, :millisecond}),

      # AI Provider Metrics
      counter("hal.ai.requests_total", tags: [:provider]),
      counter("hal.ai.errors_total", tags: [:provider]),
      summary("hal.ai.latency", unit: {:native, :millisecond}, tags: [:provider])
    ]
  end

  defp periodic_measurements do
    [
      {HAL.Telemetry, :measure_sessions, []},
      {HAL.Telemetry, :measure_channels, []}
    ]
  end

  def measure_sessions do
    :telemetry.execute(
      [:hal, :sessions],
      %{active_count: HAL.Dashboard.count_active_sessions()},
      %{}
    )
  end
end
```

**Emit telemetry events throughout codebase:**
```elixir
# In SessionServer
:telemetry.execute([:hal, :messages], %{processing_time: duration}, %{channel: :telegram})

# In AI providers
:telemetry.execute([:hal, :ai], %{latency: duration}, %{provider: :claude_code})
```

---

#### 1.3 Prometheus Metrics Endpoint (Day 2 - 2 hours)

**Export metrics in Prometheus format:**
```elixir
# Add dependency
{:telemetry_metrics_prometheus, "~> 1.1"}

# In application.ex
{TelemetryMetricsPrometheus, metrics: HAL.Telemetry.metrics(), port: 9568}
```

**Access:** `http://localhost:9568/metrics`

**Integration:** Grafana dashboard, alerting rules

---

### Phase 2: Additional AI Providers (Week 2) ⭐⭐⭐⭐

**Goal:** Support 10+ AI providers like Pi Agent

#### 2.1 OpenAI/GPT-4 Integration (Day 1 - 6 hours)
```elixir
# lib/hal/ai/openai.ex
defmodule HAL.AI.OpenAI do
  @behaviour HAL.AI.Provider

  @base_url "https://api.openai.com/v1"

  def prompt(session_id, message, opts \\ []) do
    model = opts[:model] || "gpt-4"

    body = %{
      model: model,
      messages: build_messages(session_id, message),
      temperature: opts[:temperature] || 0.7,
      max_tokens: opts[:max_tokens] || 4096
    }

    case HTTPoison.post("#{@base_url}/chat/completions", Jason.encode!(body), headers()) do
      {:ok, %{status_code: 200, body: response_body}} ->
        response = Jason.decode!(response_body)
        text = get_in(response, ["choices", Access.at(0), "message", "content"])
        {:ok, text, session_id}

      {:ok, %{status_code: status, body: body}} ->
        {:error, "OpenAI API error #{status}: #{body}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end

  def supports?(message) do
    # Good for general questions, not specialized coding
    not coding_task?(message)
  end

  def cost_estimate(message) do
    # Rough estimate: $0.03 per 1K input tokens, $0.06 per 1K output
    input_tokens = estimate_tokens(message)
    output_tokens = 1000  # Assume average response

    input_cost = (input_tokens / 1000) * 0.03
    output_cost = (output_tokens / 1000) * 0.06

    input_cost + output_cost
  end

  defp headers do
    [
      {"Authorization", "Bearer #{api_key()}"},
      {"Content-Type", "application/json"}
    ]
  end

  defp api_key do
    Application.get_env(:hal, __MODULE__)[:api_key] ||
      System.get_env("OPENAI_API_KEY")
  end
end
```

#### 2.2 Additional Providers (Days 2-5 - 2 hours each)

**Mistral AI:**
```elixir
# lib/hal/ai/mistral.ex
# Similar pattern, different endpoint
# https://api.mistral.ai/v1/chat/completions
```

**xAI (Grok):**
```elixir
# lib/hal/ai/xai.ex
# https://api.x.ai/v1/chat/completions
```

**Anthropic Direct API (non-Claude Code):**
```elixir
# lib/hal/ai/anthropic.ex
# For when you want streaming or different models
# https://api.anthropic.com/v1/messages
```

**Cohere:**
```elixir
# lib/hal/ai/cohere.ex
# https://api.cohere.ai/v1/chat
```

**Perplexity:**
```elixir
# lib/hal/ai/perplexity.ex
# https://api.perplexity.ai/chat/completions
```

**Local Models (Ollama):**
```elixir
# lib/hal/ai/ollama.ex
# http://localhost:11434/api/chat
```

#### 2.3 Enhanced Router (Day 5 - 4 hours)

**Smarter routing with cost optimization:**
```elixir
defmodule HAL.AI.Router do
  # Enhanced routing logic
  def route(message, opts \\ []) do
    providers = available_providers(message, opts)

    selected = if opts[:optimize_cost] do
      select_cheapest(providers, message)
    else
      select_best_quality(providers, message)
    end

    case selected.module.prompt(opts[:session_id], message, opts) do
      {:ok, response, session_id} ->
        {:ok, response, session_id}

      {:error, reason} when opts[:enable_fallback] ->
        # Try next provider
        fallback_route(message, providers, selected, opts)

      error ->
        error
    end
  end

  defp select_cheapest(providers, message) do
    Enum.min_by(providers, fn p ->
      p.module.cost_estimate(message)
    end)
  end
end
```

---

### Phase 3: Browser Automation (Week 3) ⭐⭐⭐⭐

**Goal:** Headless Chrome automation for web tasks

#### 3.1 Wallaby/Hound Integration (Days 1-3)

**Add dependency:**
```elixir
# mix.exs
{:wallaby, "~> 0.30"}
# or
{:hound, "~> 1.1"}
```

**Browser manager:**
```elixir
# lib/hal/browser/manager.ex
defmodule HAL.Browser.Manager do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Start ChromeDriver
    {:ok, driver_pid} = start_chromedriver()

    {:ok, %{driver: driver_pid, sessions: %{}}}
  end

  def new_session do
    GenServer.call(__MODULE__, :new_session)
  end

  def navigate(session_id, url) do
    GenServer.call(__MODULE__, {:navigate, session_id, url})
  end

  def screenshot(session_id) do
    GenServer.call(__MODULE__, {:screenshot, session_id})
  end

  def execute_script(session_id, script) do
    GenServer.call(__MODULE__, {:execute_script, session_id, script})
  end
end
```

**Browser actions:**
```elixir
# lib/hal/browser/actions.ex
defmodule HAL.Browser.Actions do
  use Wallaby.DSL

  def search_google(query) do
    session = start_session()

    session
    |> visit("https://google.com")
    |> fill_in(Query.text_field("q"), with: query)
    |> click(Query.button("Google Search"))
    |> assert_has(Query.css(".g"))
    |> page_source()
  end

  def fill_form(url, form_data) do
    session = start_session()

    session
    |> visit(url)
    |> fill_form_fields(form_data)
    |> click(Query.button("Submit"))
    |> page_source()
  end

  def take_screenshot(url) do
    session = start_session()

    session
    |> visit(url)
    |> take_screenshot()
  end
end
```

#### 3.2 Chrome DevTools Protocol (Days 4-5)

**For advanced automation:**
```elixir
# lib/hal/browser/cdp.ex
defmodule HAL.Browser.CDP do
  @moduledoc """
  Chrome DevTools Protocol client for advanced browser control
  """

  def connect(ws_url) do
    {:ok, pid} = WebSockex.start_link(ws_url, __MODULE__, %{})
    {:ok, pid}
  end

  def navigate(pid, url) do
    send_command(pid, "Page.navigate", %{url: url})
  end

  def evaluate_script(pid, expression) do
    send_command(pid, "Runtime.evaluate", %{expression: expression})
  end

  defp send_command(pid, method, params) do
    WebSockex.send_frame(pid, {:text, Jason.encode!(%{
      id: :erlang.unique_integer(),
      method: method,
      params: params
    })})
  end
end
```

---

### Phase 4: WhatsApp Integration (Week 4) ⭐⭐⭐⭐⭐

**Goal:** WhatsApp Business API integration

**Options:**
1. **WhatsApp Business API** (official, requires approval)
2. **Baileys library** (unofficial, via Node.js bridge)
3. **wa-automate-nodejs** (wrapper)

#### 4.1 WhatsApp Business API (Recommended for production)

```elixir
# lib/hal/channels/whatsapp/client.ex
defmodule HAL.Channels.WhatsApp.Client do
  use GenServer

  @base_url "https://graph.facebook.com/v18.0"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def send_message(to, text) do
    GenServer.call(__MODULE__, {:send_message, to, text})
  end

  @impl true
  def handle_call({:send_message, to, text}, _from, state) do
    body = %{
      messaging_product: "whatsapp",
      to: to,
      type: "text",
      text: %{body: text}
    }

    url = "#{@base_url}/#{state.phone_number_id}/messages"

    case HTTPoison.post(url, Jason.encode!(body), headers(state.access_token)) do
      {:ok, %{status_code: 200}} ->
        {:reply, :ok, state}

      error ->
        {:reply, {:error, error}, state}
    end
  end

  # Webhook handler
  def handle_webhook(params) do
    # Process incoming WhatsApp messages
    # Route to HAL.Gateway.Router
  end
end
```

**Webhook endpoint:**
```elixir
# lib/hal_web/controllers/whatsapp_webhook_controller.ex
defmodule HalWeb.WhatsAppWebhookController do
  use HalWeb, :controller

  def verify(conn, %{"hub.mode" => "subscribe", "hub.challenge" => challenge}) do
    # WhatsApp webhook verification
    send_resp(conn, 200, challenge)
  end

  def webhook(conn, params) do
    # Process incoming messages
    HAL.Channels.WhatsApp.Client.handle_webhook(params)
    send_resp(conn, 200, "ok")
  end
end
```

#### 4.2 Baileys Bridge (Alternative - Quick start)

**If you need WhatsApp immediately:**
```bash
# Create Node.js bridge service
mkdir priv/whatsapp-bridge
cd priv/whatsapp-bridge
npm init -y
npm install @whiskeysockets/baileys
```

**Bridge server:**
```javascript
// priv/whatsapp-bridge/index.js
const { default: makeWASocket } = require('@whiskeysockets/baileys');

const sock = makeWASocket({
  printQRInTerminal: true
});

sock.ev.on('messages.upsert', async (m) => {
  // Send to Elixir via HTTP
  await fetch('http://localhost:4000/api/whatsapp/message', {
    method: 'POST',
    body: JSON.stringify(m)
  });
});

// Listen for commands from Elixir
app.post('/send', (req, res) => {
  const { to, message } = req.body;
  sock.sendMessage(to, { text: message });
  res.json({ success: true });
});
```

**Call from Elixir:**
```elixir
defmodule HAL.Channels.WhatsApp.BaileysBridge do
  def send_message(to, text) do
    HTTPoison.post("http://localhost:3000/send", Jason.encode!(%{
      to: to,
      message: text
    }))
  end
end
```

---

### Phase 5: Email Integration (Week 5) ⭐⭐⭐⭐

**Goal:** Full email capabilities (read, send, search)

#### 5.1 IMAP Client (Incoming)

```elixir
# Add dependency
{:mail, "~> 0.3"}
{:gen_smtp, "~> 1.2"}

# lib/hal/email/imap_client.ex
defmodule HAL.Email.IMAPClient do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Connect to IMAP server
    {:ok, conn} = :imap.connect([
      {:host, 'imap.gmail.com'},
      {:port, 993},
      {:ssl, true}
    ])

    :imap.login(conn, email(), password())

    # Start polling for new messages
    schedule_check()

    {:ok, %{conn: conn}}
  end

  def handle_info(:check_new_emails, state) do
    {:ok, messages} = :imap.search(state.conn, 'UNSEEN')

    Enum.each(messages, fn msg_id ->
      {:ok, email} = :imap.fetch(state.conn, msg_id)
      process_email(email)
    end)

    schedule_check()
    {:noreply, state}
  end

  defp process_email(email) do
    # Parse email
    parsed = Mail.parse(email)

    # Create session and send to AI
    HAL.Gateway.SessionManager.get_or_create_session(
      :email,
      parsed.from,
      parsed.from
    )
    |> HAL.Session.handle_message(%{
      text: parsed.body,
      subject: parsed.subject,
      from: parsed.from
    })
  end
end
```

#### 5.2 SMTP Client (Outgoing)

```elixir
# lib/hal/email/smtp_client.ex
defmodule HAL.Email.SMTPClient do
  def send_email(to, subject, body) do
    email = Mail.build()
    |> Mail.put_to(to)
    |> Mail.put_from(from_email())
    |> Mail.put_subject(subject)
    |> Mail.put_text(body)

    :gen_smtp_client.send(
      Mail.render(email),
      smtp_config()
    )
  end

  defp smtp_config do
    [
      relay: "smtp.gmail.com",
      port: 587,
      username: email(),
      password: app_password(),
      tls: :always
    ]
  end
end
```

---

### Phase 6: Additional Channels (Weeks 6-8) ⭐⭐⭐

#### 6.1 iMessage (macOS only - Week 6)

**Via AppleScript:**
```elixir
# lib/hal/channels/imessage/client.ex
defmodule HAL.Channels.IMessage.Client do
  def send_message(to, text) do
    script = """
    tell application "Messages"
      set targetService to 1st account whose service type = iMessage
      set targetBuddy to participant "#{to}" of targetService
      send "#{escape_quotes(text)}" to targetBuddy
    end tell
    """

    System.cmd("osascript", ["-e", script])
  end

  def poll_messages do
    # Read iMessage database (SQLite)
    # ~/Library/Messages/chat.db
    db_path = Path.join([System.user_home(), "Library", "Messages", "chat.db"])

    {:ok, conn} = Exqlite.Sqlite3.open(db_path)

    {:ok, rows} = Exqlite.Sqlite3.execute(conn, """
      SELECT message.text, handle.id, message.date
      FROM message
      JOIN handle ON message.handle_id = handle.ROWID
      WHERE message.date > ?
      ORDER BY message.date DESC
    """, [last_check_timestamp()])

    Enum.each(rows, &process_message/1)
  end
end
```

#### 6.2 Signal (Week 7)

**Via signal-cli:**
```elixir
# lib/hal/channels/signal/client.ex
defmodule HAL.Channels.Signal.Client do
  def send_message(to, text) do
    System.cmd("signal-cli", [
      "-u", phone_number(),
      "send",
      "-m", text,
      to
    ])
  end

  def receive_messages do
    # Run signal-cli in receive mode
    System.cmd("signal-cli", [
      "-u", phone_number(),
      "receive",
      "--json"
    ])
  end
end
```

#### 6.3 Microsoft Teams (Week 8)

**Via Microsoft Graph API:**
```elixir
# lib/hal/channels/teams/client.ex
defmodule HAL.Channels.Teams.Client do
  @base_url "https://graph.microsoft.com/v1.0"

  def send_message(channel_id, text) do
    body = %{
      body: %{
        content: text
      }
    }

    HTTPoison.post(
      "#{@base_url}/teams/#{team_id()}/channels/#{channel_id}/messages",
      Jason.encode!(body),
      headers()
    )
  end

  defp headers do
    [
      {"Authorization", "Bearer #{access_token()}"},
      {"Content-Type", "application/json"}
    ]
  end
end
```

---

### Phase 7: Advanced Features (Weeks 9-12) ⭐⭐⭐

#### 7.1 GitHub Integration

```elixir
# lib/hal/integrations/github.ex
defmodule HAL.Integrations.GitHub do
  @base_url "https://api.github.com"

  def list_pull_requests(owner, repo) do
    HTTPoison.get("#{@base_url}/repos/#{owner}/#{repo}/pulls", headers())
  end

  def review_pr(owner, repo, pr_number, comments) do
    # AI-powered PR review
    # Get PR diff, analyze with Claude, post comments
  end

  def create_issue(owner, repo, title, body) do
    HTTPoison.post(
      "#{@base_url}/repos/#{owner}/#{repo}/issues",
      Jason.encode!(%{title: title, body: body}),
      headers()
    )
  end

  # Webhook handler
  def handle_webhook(event_type, payload) do
    case event_type do
      "pull_request" -> handle_pr_event(payload)
      "issues" -> handle_issue_event(payload)
      "push" -> handle_push_event(payload)
    end
  end
end
```

#### 7.2 Calendar Integration

```elixir
# lib/hal/integrations/calendar.ex
defmodule HAL.Integrations.Calendar do
  @base_url "https://www.googleapis.com/calendar/v3"

  def list_events(calendar_id, time_min, time_max) do
    params = %{
      timeMin: time_min,
      timeMax: time_max,
      singleEvents: true,
      orderBy: "startTime"
    }

    HTTPoison.get(
      "#{@base_url}/calendars/#{calendar_id}/events",
      headers(),
      params: params
    )
  end

  def create_event(calendar_id, summary, start_time, end_time) do
    body = %{
      summary: summary,
      start: %{dateTime: start_time},
      end: %{dateTime: end_time}
    }

    HTTPoison.post(
      "#{@base_url}/calendars/#{calendar_id}/events",
      Jason.encode!(body),
      headers()
    )
  end
end
```

#### 7.3 Document Processing

```elixir
# lib/hal/documents/processor.ex
defmodule HAL.Documents.Processor do
  def process_pdf(file_path) do
    # Use :pdf_to_text or similar
    # Extract text, send to AI for analysis
  end

  def process_image(file_path) do
    # Use Mogrify for image manipulation
    # OCR with Tesseract
    # Vision API for analysis
  end

  def process_audio(file_path) do
    # Use HAL.Voice.STT for transcription
  end
end
```

---

## 📋 Priority Order

### 🔥 Critical (Do First)
1. Health checks & monitoring (Week 1)
2. OpenAI/GPT-4 (Week 2)
3. Email integration (Week 5)

### ⭐ High Priority (Do Second)
4. Browser automation (Week 3)
5. WhatsApp (Week 4)
6. Mistral, xAI providers (Week 2)

### 📦 Medium Priority (Do Third)
7. GitHub integration (Week 9)
8. Calendar integration (Week 9)
9. iMessage (Week 6)
10. Signal (Week 7)

### 🎁 Nice to Have (Do Last)
11. Teams (Week 8)
12. Document processing (Week 10)
13. Advanced skills system (Week 11-12)

---

## 🎯 Quick Wins (Start Today)

### Can Implement in < 4 Hours Each:

**1. Health Endpoints** ✅
```bash
# Add controller
# Add routes
# Add tests
# Deploy
```

**2. Telemetry Events** ✅
```bash
# Add :telemetry.execute calls
# Set up metrics
# Prometheus endpoint
```

**3. OpenAI Provider** ✅
```bash
# Copy Gemini provider structure
# Change API endpoint
# Update configuration
# Add tests
```

---

## 📦 Dependencies to Add

```elixir
# mix.exs
defp deps do
  [
    # ... existing deps ...

    # Browser automation
    {:wallaby, "~> 0.30"},

    # Email
    {:mail, "~> 0.3"},
    {:gen_smtp, "~> 1.2"},

    # WhatsApp (if using Baileys bridge)
    # Node.js bridge handles this

    # Document processing
    {:mogrify, "~> 0.9"},  # Image manipulation

    # Metrics
    {:telemetry_metrics_prometheus, "~> 1.1"}
  ]
end
```

---

## 🧪 Testing Strategy

### Each New Feature Needs:
1. Unit tests (provider/channel logic)
2. Integration tests (end-to-end flow)
3. Error handling tests
4. Performance tests (if applicable)

### Maintain 80%+ Coverage

---

## 📊 Success Metrics

| Milestone | Target Date | Success Criteria |
|-----------|-------------|------------------|
| **Phase 1 Complete** | Week 1 | Health endpoints live, metrics working |
| **10 AI Providers** | Week 2 | Can switch providers seamlessly |
| **Browser Working** | Week 3 | Can automate web tasks |
| **WhatsApp Working** | Week 4 | Can send/receive WhatsApp |
| **Email Working** | Week 5 | Can read/send emails |
| **6+ Channels** | Week 8 | Telegram, Slack, Discord, WhatsApp, Email, iMessage |
| **Full Parity** | Week 12 | Match clawdbot features |

---

## 🚀 Next Steps

**Want me to:**

1. **Start with health checks NOW?** (4 hours, quick win)
2. **Build OpenAI provider?** (6 hours, high value)
3. **Set up browser automation?** (3 days, complex)
4. **All of the above in parallel?** (spawn multiple agents)

**Your call - what should we tackle first?**
