import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :hal, Hal.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "hal_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  types: Hal.PostgrexTypes

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :hal, HalWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "V9JbJyHlSKyvKAvZNZc+N+MQpHgzkDd4zodM+mWrgdHxj/Yb+Hlzc7LdaOsj/I4g",
  server: false

# In test we don't send emails
config :hal, Hal.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Disable nostrum (Discord) during tests - it requires a bot token
# We need to tell nostrum not to start
config :nostrum,
  gateway_intents: :nonprivileged,
  token: nil

# Disable ex_gram (Telegram) during tests
config :ex_gram, token: nil

# Disable HAL Telegram connector during tests (avoid external network calls)
config :hal, Hal.Channels.Telegram.Supervisor,
  enabled: false,
  bot_token: nil

# Disable Linear integration during tests (avoid external network calls)
config :hal, HAL.Integrations.Tasks, api_key: false

# Oban test configuration
# Use inline testing mode - jobs execute immediately in the same process
# This is suitable for most tests. Tests that create jobs that would call
# external services (like Claude Code) should be tagged with @tag :integration
config :hal, Oban, testing: :inline

# Avoid auto-executing approved actions during tests.
config :hal, HAL.Autonomy.Approvals, auto_execute: false

# Disable budget enforcement during tests (avoid coupling test behavior to budgets).
config :hal, HAL.Costs.Budget, enforce_autonomy: false

# Disable Quantum scheduler during tests
config :hal, HAL.Scheduler, jobs: []

# In tests, keep message ingress open unless a test explicitly overrides it.
config :hal, Hal.Security,
  dm_policy: :open,
  group_policy: :open,
  dm_allowlist: [],
  group_allowlist: []

# Configure OpenAI API for tests (using a test key or mock)
# Set OPENAI_API_KEY environment variable for actual API tests
config :hal, Hal.Voice.STT, api_key: System.get_env("OPENAI_API_KEY") || "test-api-key"

# Use mock Claude client in tests to avoid consuming API quota
# For integration tests that need real API, use @tag :integration
config :hal, :claude_client, Hal.AI.ClaudeMockClient

# Use mock embedding client in tests
config :hal, :embedding_client, HAL.Memory.EmbeddingMock

# Use test classifier for routing (deterministic for tests)
# This function applies simple heuristics that match test expectations
# In production, this uses AI classification
config :hal, Hal.AI.Router,
  classifier: fn message ->
    message_lower = String.downcase(message)

    cond do
      # Check for coding signals (keywords)
      String.contains?(message_lower, [
        "code",
        "debug",
        "refactor",
        "function",
        "module",
        "file",
        "write",
        "edit",
        "read",
        "script",
        "compile",
        "build",
        "fix",
        "bug",
        "test",
        "implement"
      ]) ->
        {:ok, :coding}

      # Check for file path patterns (Unix/Windows/relative)
      Regex.match?(~r{/\w+[\w./\-_]*\.\w+}, message) ->
        {:ok, :coding}

      Regex.match?(~r{(?:lib|src|test|priv|config)/[\w/.\-_]+}, message) ->
        {:ok, :coding}

      # Code blocks
      String.contains?(message, "```") ->
        {:ok, :coding}

      # Check for simple questions
      Regex.match?(~r/^(what|who|when|where|how|why|explain|describe|tell me)/i, message) ->
        {:ok, :simple}

      true ->
        {:ok, :general}
    end
  end
