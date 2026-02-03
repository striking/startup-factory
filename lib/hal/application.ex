defmodule Hal.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Base children that always start
    # Determine which Claude client to use (mock for tests, real for dev/prod)
    claude_client = Application.get_env(:hal, :claude_client, Hal.AI.ClaudePythonClient)

    # Build list of Claude-related children
    # AgentSDK (TypeScript) is always supervised and starts lazily
    # PythonClient is only started if explicitly configured (legacy support)
    claude_children =
      cond do
        # Mock client for tests
        claude_client != nil and claude_client != Hal.AI.ClaudePythonClient ->
          [Hal.AI.ClaudeMockClient]

        # Default: use AgentSDK supervisor (PythonClient as fallback if AgentSDK unavailable)
        true ->
          # AgentSDK supervisor handles lazy port startup
          # PythonClient still available as fallback
          [
            HAL.AI.Supervisor,
            {Hal.AI.ClaudePythonClient, working_dir: File.cwd!()}
          ]
      end

    base_children =
      [
        HalWeb.Telemetry,
        Hal.Repo,
        # EventLog async writer (must start before AgentState)
        {HAL.EventLog.Writer, log_file: HAL.EventLog.log_file()},
        {DNSCluster, query: Application.get_env(:hal, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Hal.PubSub}
      ] ++
        claude_children ++
        [
          # External agent delegation (Codex, Jules, Gemini)
          HAL.Agents.Supervisor,
          # Agent state with event sourcing (JSONL + ETS)
          HAL.AgentState,
          # Agent registry for presence tracking and A2A messaging
          HAL.AgentRegistry,
          # Multi-agent orchestrator for parallel task execution
          HAL.MultiAgent.Orchestrator,
          # Delegation metrics for self-improvement
          HAL.DelegationMetrics,
          # Resilience components (rate limiters, circuit breakers, monitoring)
          HAL.Resilience.Supervisor,
          # Oban for background job processing and scheduled tasks
          {Oban, Application.fetch_env!(:hal, Oban)},
          # Quantum scheduler for periodic proactive agent evaluations
          HAL.Scheduler,
          # Goals system (autonomous goal pursuit)
          HAL.Goals.Supervisor,
          # Autonomy system (heartbeat orchestration)
          HAL.Autonomy.Supervisor,
          # MCP client for external tool integrations (Slack, GitHub, etc.)
          HAL.MCP.Supervisor,
          # Gateway supervision tree (sessions, routing, etc.)
          Hal.Gateway,
          # Startup Factory - experiment pipeline
          Factory.Supervisor
        ]

    # Optional channel connectors (only start if tokens configured)
    channel_children = []

    # Add Telegram if token configured
    channel_children =
      if System.get_env("TELEGRAM_BOT_TOKEN") do
        telegram_children = [ExGram, Hal.Channels.Telegram.Supervisor]

        # Add DeadMansSwitch if admin chat ID is configured
        telegram_children =
          if admin_chat_id = System.get_env("TELEGRAM_ADMIN_CHAT_ID") do
            dead_mans_switch_spec = {
              HAL.DeadMansSwitch,
              name: HAL.DeadMansSwitch,
              admin_channel_id: admin_chat_id,
              telegram_sender: Hal.Channels.Telegram.Sender
            }

            telegram_children ++ [dead_mans_switch_spec]
          else
            IO.puts("⚠️  DeadMansSwitch disabled (no TELEGRAM_ADMIN_CHAT_ID)")
            telegram_children
          end

        telegram_children ++ channel_children
      else
        IO.puts("⚠️  Telegram disabled (no TELEGRAM_BOT_TOKEN)")
        channel_children
      end

    # Add Slack if token configured
    channel_children =
      if System.get_env("SLACK_BOT_TOKEN") do
        [HAL.Channels.Slack.Supervisor | channel_children]
      else
        IO.puts("⚠️  Slack disabled (no SLACK_BOT_TOKEN)")
        channel_children
      end

    # Add Discord if token configured
    channel_children =
      if System.get_env("DISCORD_BOT_TOKEN") do
        [Hal.Channels.Discord.Supervisor | channel_children]
      else
        IO.puts("⚠️  Discord disabled (no DISCORD_BOT_TOKEN)")
        channel_children
      end

    # Combine all children + Phoenix endpoint
    children = base_children ++ channel_children ++ [HalWeb.Endpoint]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Hal.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HalWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
