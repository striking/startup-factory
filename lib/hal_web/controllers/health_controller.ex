defmodule HalWeb.HealthController do
  @moduledoc """
  Health check endpoints for monitoring and Kubernetes probes.

  ## Endpoints

  - GET /health - Detailed health status with component checks and metrics
  - GET /health/ready - Readiness probe (returns 200 if ready, 503 if not)
  - GET /health/live - Liveness probe (always returns 200 if process is alive)

  ## Status Levels

  - `healthy` - All core components operational
  - `degraded` - Some core components impaired
  - `unhealthy` - Critical components (database, Claude Code, PubSub) down

  ## Components

  Core (affect health status):
  - database - PostgreSQL connection
  - pubsub - Phoenix PubSub for LiveView real-time
  - claude_code - Claude Code CLI

  Optional (reported but don't affect status):
  - telegram, slack, discord - External chat integrations (only checked if configured)
  """

  use HalWeb, :controller

  @doc """
  Detailed health check endpoint.

  Returns comprehensive system status including:
  - Overall status (healthy/degraded/unhealthy)
  - Component health (database, channels, Claude Code)
  - System metrics (sessions, memory, messages)
  - Uptime information
  """
  def index(conn, _params) do
    # Check core components (affect health status)
    core_components = %{
      database: check_database(),
      pubsub: check_pubsub(),
      claude_code: check_claude_code()
    }

    # Check optional integrations (reported but don't affect status)
    channel_components = build_optional_integrations()

    # Merge into full components map for response payload
    components = Map.merge(core_components, channel_components)

    # Gather metrics
    metrics = %{
      active_sessions: Hal.Dashboard.count_active_sessions(),
      messages_today: Hal.Dashboard.count_messages_today(),
      memory_mb: :erlang.memory(:total) / 1_048_576
    }

    # Determine overall status (based only on core components)
    overall_status = determine_status(core_components)

    response = %{
      status: overall_status,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      uptime_seconds: get_uptime_seconds(),
      components: components,
      metrics: metrics
    }

    json(conn, response)
  end

  @doc """
  Kubernetes readiness probe.

  Returns 200 if the system is ready to serve requests, 503 otherwise.
  Checks critical components like database and Claude Code availability.
  """
  def ready(conn, _params) do
    if all_systems_ready?() do
      send_resp(conn, 200, "ready")
    else
      send_resp(conn, 503, "not ready")
    end
  end

  @doc """
  Kubernetes liveness probe.

  Always returns 200 if the process is alive.
  This is a fast check with no external dependencies.
  """
  def live(conn, _params) do
    send_resp(conn, 200, "alive")
  end

  # ============================================================================
  # Component Health Checks
  # ============================================================================

  defp check_database do
    start_time = System.monotonic_time(:millisecond)

    case Ecto.Adapters.SQL.query(Hal.Repo, "SELECT 1", []) do
      {:ok, _result} ->
        end_time = System.monotonic_time(:millisecond)
        response_time = end_time - start_time

        %{
          status: "healthy",
          response_time_ms: response_time
        }

      {:error, error} ->
        %{
          status: "unhealthy",
          error: "Database connection failed: #{inspect(error)}"
        }
    end
  end

  defp check_pubsub do
    # Check if Phoenix PubSub is running (core for LiveView real-time)
    case Process.whereis(Hal.PubSub) do
      nil ->
        %{status: "unhealthy", error: "PubSub not running"}

      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          %{status: "healthy"}
        else
          %{status: "unhealthy", error: "PubSub process dead"}
        end
    end
  end

  defp check_channel(channel_type) do
    # Check if the channel supervisor is running
    supervisor_module =
      case channel_type do
        :telegram -> Hal.Channels.Telegram.Supervisor
        :slack -> HAL.Channels.Slack.Supervisor
        :discord -> Hal.Channels.Discord.Supervisor
      end

    case Process.whereis(supervisor_module) do
      nil ->
        %{status: "disabled", reason: "Not configured"}

      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          %{status: "healthy"}
        else
          %{status: "unhealthy", error: "Supervisor process dead"}
        end
    end
  end

  defp build_optional_integrations do
    %{
      telegram: check_channel(:telegram),
      slack: check_channel(:slack),
      discord: check_channel(:discord)
    }
  end

  defp check_claude_code do
    # Check if Claude Code CLI is available by running --version
    try do
      case System.cmd("claude", ["--version"], stderr_to_stdout: true) do
        {output, 0} ->
          # Extract version from output (e.g., "Claude Code v1.2.3")
          version = String.trim(output)

          %{
            status: "healthy",
            version: version
          }

        {_output, _exit_code} ->
          %{
            status: "unhealthy",
            error: "Claude Code CLI not available"
          }
      end
    rescue
      error ->
        %{
          status: "unhealthy",
          error: "Failed to check Claude Code: #{inspect(error)}"
        }
    end
  end

  # ============================================================================
  # Status Determination
  # ============================================================================

  defp determine_status(core_components) do
    # All core components must be healthy for overall healthy status
    all_healthy? =
      Enum.all?(core_components, fn {_name, check} ->
        check[:status] == "healthy"
      end)

    if all_healthy?, do: "healthy", else: "unhealthy"
  end

  defp all_systems_ready? do
    # For readiness, check all core components
    db_check = check_database()
    pubsub_check = check_pubsub()
    claude_check = check_claude_code()

    db_check[:status] == "healthy" and
      pubsub_check[:status] == "healthy" and
      claude_check[:status] == "healthy"
  end

  # ============================================================================
  # Utilities
  # ============================================================================

  defp get_uptime_seconds do
    # Get VM uptime from :erlang.statistics(:wall_clock)
    case :erlang.statistics(:wall_clock) do
      {uptime_ms, _} ->
        div(uptime_ms, 1000)

      _ ->
        0
    end
  end
end
