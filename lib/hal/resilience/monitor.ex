defmodule HAL.Resilience.Monitor do
  @moduledoc """
  Monitoring and alerting for resilience patterns.

  This module attaches telemetry handlers to track resilience metrics
  and sends alerts when issues are detected.

  ## Metrics Tracked

  - Retry attempts and success/failure rates
  - Circuit breaker state changes
  - Rate limiting events
  - Error rates by service
  - Response times

  ## Alert Conditions

  - Circuit breaker opens (immediate)
  - High retry rate (> 50% of requests)
  - Rate limiting frequently triggered
  - Service errors > threshold

  ## Usage

      # Start monitoring in application supervisor
      children = [
        HAL.Resilience.Monitor
      ]

      # Configure alerts
      config :hal, HAL.Resilience.Monitor,
        alert_handlers: [
          {HAL.Resilience.Monitor.SlackAlert, channel: "#alerts"},
          {HAL.Resilience.Monitor.LogAlert, level: :error}
        ],
        error_threshold: 0.1,  # Alert if > 10% error rate
        window: 300_000        # 5 minute window
  """

  use GenServer
  require Logger

  @type metric :: %{
          timestamp: integer(),
          event: atom(),
          measurements: map(),
          metadata: map()
        }

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            metrics: list(),
            window: pos_integer(),
            error_threshold: float(),
            alert_handlers: list()
          }

    defstruct metrics: [],
              window: 300_000,
              error_threshold: 0.1,
              alert_handlers: []
  end

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets metrics summary for the configured time window.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Gets health status based on recent metrics.

  Returns:
  - `:healthy` - All systems operating normally
  - `:degraded` - Some issues detected
  - `:unhealthy` - Critical issues
  """
  def get_health do
    GenServer.call(__MODULE__, :get_health)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %State{
      window: Keyword.get(opts, :window, 300_000),
      error_threshold: Keyword.get(opts, :error_threshold, 0.1),
      alert_handlers: Keyword.get(opts, :alert_handlers, [])
    }

    # Attach telemetry handlers
    attach_handlers()

    # Schedule periodic cleanup
    schedule_cleanup()

    Logger.info("Resilience monitor started (window: #{state.window}ms)")

    {:ok, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    state = cleanup_old_metrics(state)
    summary = calculate_summary(state.metrics)
    {:reply, summary, state}
  end

  @impl true
  def handle_call(:get_health, _from, state) do
    state = cleanup_old_metrics(state)
    health = determine_health(state)
    {:reply, health, state}
  end

  @impl true
  def handle_info({:telemetry_event, event_name, measurements, metadata}, state) do
    metric = %{
      timestamp: System.monotonic_time(:millisecond),
      event: event_name,
      measurements: measurements,
      metadata: metadata
    }

    new_state = %{state | metrics: [metric | state.metrics]}

    # Check if we should send alerts
    new_state = check_and_alert(new_state, metric)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    new_state = cleanup_old_metrics(state)
    schedule_cleanup()
    {:noreply, new_state}
  end

  # Private Functions

  defp attach_handlers do
    events = [
      [:hal, :resilience, :retry, :start],
      [:hal, :resilience, :retry, :success],
      [:hal, :resilience, :retry, :failure],
      [:hal, :resilience, :retry, :attempt],
      [:hal, :resilience, :circuit_breaker, :open],
      [:hal, :resilience, :circuit_breaker, :close],
      [:hal, :resilience, :circuit_breaker, :half_open],
      [:hal, :resilience, :circuit_breaker, :call, :success],
      [:hal, :resilience, :circuit_breaker, :call, :failure],
      [:hal, :resilience, :rate_limit, :acquired],
      [:hal, :resilience, :rate_limit, :throttled]
    ]

    :telemetry.attach_many(
      "hal-resilience-monitor",
      events,
      &handle_event/4,
      nil
    )
  end

  defp handle_event(event_name, measurements, metadata, _config) do
    send(__MODULE__, {:telemetry_event, event_name, measurements, metadata})
  end

  defp cleanup_old_metrics(state) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - state.window

    new_metrics =
      Enum.filter(state.metrics, fn metric ->
        metric.timestamp >= cutoff
      end)

    %{state | metrics: new_metrics}
  end

  defp calculate_summary(metrics) do
    # Count events by type
    retry_attempts = count_events(metrics, [:hal, :resilience, :retry, :attempt])
    retry_successes = count_events(metrics, [:hal, :resilience, :retry, :success])
    retry_failures = count_events(metrics, [:hal, :resilience, :retry, :failure])

    circuit_breaker_opens = count_events(metrics, [:hal, :resilience, :circuit_breaker, :open])

    circuit_breaker_successes =
      count_events(metrics, [:hal, :resilience, :circuit_breaker, :call, :success])

    circuit_breaker_failures =
      count_events(metrics, [:hal, :resilience, :circuit_breaker, :call, :failure])

    rate_limit_throttled = count_events(metrics, [:hal, :resilience, :rate_limit, :throttled])

    total_calls = circuit_breaker_successes + circuit_breaker_failures
    error_rate = if total_calls > 0, do: circuit_breaker_failures / total_calls, else: 0.0
    retry_rate = if total_calls > 0, do: retry_attempts / total_calls, else: 0.0

    %{
      window_ms: calculate_window(metrics),
      total_calls: total_calls,
      error_rate: Float.round(error_rate, 4),
      retry_rate: Float.round(retry_rate, 4),
      retries: %{
        attempts: retry_attempts,
        successes: retry_successes,
        failures: retry_failures
      },
      circuit_breakers: %{
        opens: circuit_breaker_opens,
        successes: circuit_breaker_successes,
        failures: circuit_breaker_failures
      },
      rate_limiting: %{
        throttled: rate_limit_throttled
      }
    }
  end

  defp determine_health(state) do
    summary = calculate_summary(state.metrics)

    cond do
      # Critical: Circuit breakers opening
      summary.circuit_breakers.opens > 0 ->
        :unhealthy

      # Critical: High error rate
      summary.error_rate > state.error_threshold ->
        :unhealthy

      # Warning: High retry rate
      summary.retry_rate > 0.5 ->
        :degraded

      # Warning: Frequent rate limiting
      summary.rate_limiting.throttled > summary.total_calls * 0.2 ->
        :degraded

      true ->
        :healthy
    end
  end

  defp check_and_alert(state, metric) do
    case metric.event do
      [:hal, :resilience, :circuit_breaker, :open] ->
        send_alert(state, :critical, "Circuit breaker opened", metric)

      _ ->
        # Check thresholds
        summary = calculate_summary(state.metrics)

        cond do
          summary.error_rate > state.error_threshold ->
            send_alert(state, :warning, "High error rate: #{summary.error_rate}", metric)

          summary.retry_rate > 0.5 ->
            send_alert(state, :warning, "High retry rate: #{summary.retry_rate}", metric)

          true ->
            :ok
        end
    end

    state
  end

  defp send_alert(state, level, message, metric) do
    alert = %{
      level: level,
      message: message,
      metric: metric,
      timestamp: System.system_time(:second)
    }

    Logger.log(
      if(level == :critical, do: :error, else: :warning),
      "[Resilience Alert] #{message}: #{inspect(metric)}"
    )

    # Call configured alert handlers
    Enum.each(state.alert_handlers, fn handler ->
      try do
        case handler do
          {module, opts} -> apply(module, :send_alert, [alert, opts])
          module -> apply(module, :send_alert, [alert, []])
        end
      rescue
        error ->
          Logger.error("Failed to send alert via #{inspect(handler)}: #{inspect(error)}")
      end
    end)
  end

  defp count_events(metrics, event_name) do
    Enum.count(metrics, fn metric -> metric.event == event_name end)
  end

  defp calculate_window(metrics) do
    if Enum.empty?(metrics) do
      0
    else
      newest = Enum.max_by(metrics, & &1.timestamp)
      oldest = Enum.min_by(metrics, & &1.timestamp)
      newest.timestamp - oldest.timestamp
    end
  end

  defp schedule_cleanup do
    # Clean up old metrics every minute
    Process.send_after(self(), :cleanup, 60_000)
  end
end
