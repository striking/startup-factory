# HAL Resilience System

Comprehensive resilience patterns for fault-tolerant external service integrations.

## Overview

The HAL Resilience system provides a battle-tested set of patterns for building reliable integrations with external services. It includes:

1. **Retry Logic** - Exponential backoff with jitter for transient failures
2. **Rate Limiting** - Token bucket algorithm to respect API rate limits
3. **Circuit Breakers** - Automatic failure detection and recovery
4. **Graceful Degradation** - Fallback strategies and user-friendly errors
5. **Monitoring & Alerting** - Telemetry-based metrics and health tracking

## Architecture

```
┌─────────────────────────────────────────────┐
│         HAL.Resilience.Supervisor           │
│  ┌───────────────────────────────────────┐  │
│  │  Rate Limiters                        │  │
│  │  - calendar_rate_limiter              │  │
│  │  - email_rate_limiter                 │  │
│  │  - tasks_rate_limiter                 │  │
│  └───────────────────────────────────────┘  │
│  ┌───────────────────────────────────────┐  │
│  │  Circuit Breakers                     │  │
│  │  - calendar_circuit_breaker           │  │
│  │  - email_circuit_breaker              │  │
│  │  - tasks_circuit_breaker              │  │
│  └───────────────────────────────────────┘  │
│  ┌───────────────────────────────────────┐  │
│  │  Monitor                              │  │
│  │  - Metrics collection                 │  │
│  │  - Health tracking                    │  │
│  │  - Alert dispatching                  │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

## Components

### HAL.Resilience

Core module providing high-level API for resilient calls.

```elixir
# Simple resilient call with all patterns
{:ok, result} = HAL.Resilience.call(
  fn -> HTTPoison.get("https://api.example.com") end,
  circuit_breaker: :api_breaker,
  rate_limiter: :api_limiter,
  retry: [max_attempts: 3, base_delay: 100]
)
```

### HAL.Resilience.RateLimiter

Token bucket rate limiter for controlling request rates.

**Features:**
- Token bucket algorithm
- Configurable rate and interval
- Blocking (`acquire/2`) and non-blocking (`try_acquire/2`) modes
- Automatic token replenishment
- Queue for waiting requests

**Example:**
```elixir
# Start limiter
{:ok, _} = HAL.Resilience.RateLimiter.start_link(
  name: :api_limiter,
  rate: 10,        # 10 tokens
  interval: 1000   # per second
)

# Acquire token (blocks until available)
:ok = HAL.Resilience.RateLimiter.acquire(:api_limiter)

# Try to acquire without blocking
case HAL.Resilience.RateLimiter.try_acquire(:api_limiter) do
  :ok -> make_request()
  {:error, :rate_limited} -> handle_rate_limit()
end
```

### HAL.Resilience.CircuitBreaker

Circuit breaker pattern to prevent cascading failures.

**States:**
- **Closed** - Normal operation, all requests pass through
- **Open** - Service failing, requests fail immediately
- **Half-Open** - Testing if service recovered

**State Transitions:**
```
Closed --[failures >= threshold]--> Open
Open --[timeout elapsed]--> Half-Open
Half-Open --[success]--> Closed
Half-Open --[failure]--> Open
```

**Example:**
```elixir
# Start circuit breaker
{:ok, _} = HAL.Resilience.CircuitBreaker.start_link(
  name: :api_breaker,
  failure_threshold: 5,    # Open after 5 failures
  timeout: 60_000,         # Stay open for 60 seconds
  half_open_requests: 3    # Try 3 requests when half-open
)

# Execute through circuit breaker
case HAL.Resilience.CircuitBreaker.call(:api_breaker, fn ->
  external_api_call()
end) do
  {:ok, result} -> result
  {:error, :circuit_open} -> handle_service_down()
  {:error, reason} -> handle_error(reason)
end
```

### HAL.Resilience.Monitor

Monitoring and alerting for resilience metrics.

**Tracks:**
- Retry attempts and success/failure rates
- Circuit breaker state changes
- Rate limiting events
- Error rates by service
- Response times

**Health Status:**
- `:healthy` - All systems operating normally
- `:degraded` - Some issues detected (high retry rate, rate limiting)
- `:unhealthy` - Critical issues (circuit breakers open, high error rate)

**Example:**
```elixir
# Get current health status
HAL.Resilience.Monitor.get_health()
#=> :healthy

# Get detailed metrics
HAL.Resilience.Monitor.get_metrics()
#=> %{
#     total_calls: 1000,
#     error_rate: 0.02,
#     retry_rate: 0.15,
#     circuit_breakers: %{opens: 0, successes: 980, failures: 20},
#     ...
#   }
```

## Configuration

Configure in `config/runtime.exs`:

```elixir
config :hal, HAL.Resilience,
  # Rate limiter settings
  rate_limiters: [
    calendar: [rate: 10, interval: 1000],      # 10 req/sec
    email: [rate: 10, interval: 1000],         # 10 req/sec
    tasks: [rate: 10, interval: 1000],         # 10 req/sec
    openai: [rate: 3, interval: 1000],         # 3 req/sec
    gemini: [rate: 10, interval: 1000]         # 10 req/sec
  ],

  # Circuit breaker settings
  circuit_breakers: [
    calendar: [
      failure_threshold: 5,
      timeout: 60_000,
      half_open_requests: 3
    ],
    email: [
      failure_threshold: 5,
      timeout: 60_000,
      half_open_requests: 3
    ],
    tasks: [
      failure_threshold: 5,
      timeout: 60_000,
      half_open_requests: 3
    ],
    openai: [
      failure_threshold: 10,
      timeout: 120_000,
      half_open_requests: 5
    ],
    gemini: [
      failure_threshold: 5,
      timeout: 60_000,
      half_open_requests: 3
    ]
  ]

config :hal, HAL.Resilience.Monitor,
  # Alert settings
  error_threshold: 0.1,    # Alert if > 10% error rate
  window: 300_000,         # 5 minute window
  alert_handlers: [
    {HAL.Resilience.Monitor.LogAlert, level: :error}
  ]
```

## Integration Examples

### Calendar Integration

```elixir
defmodule HAL.Integrations.Calendar do
  @rate_limiter :calendar_rate_limiter
  @circuit_breaker :calendar_circuit_breaker

  def list_events(token, opts \\ []) do
    HAL.Resilience.call(
      fn -> make_api_request(token, opts) end,
      circuit_breaker: @circuit_breaker,
      rate_limiter: @rate_limiter,
      retry: [
        max_attempts: 3,
        base_delay: 100,
        retry_on: &retryable_error?/1
      ]
    )
    |> handle_error()
  end

  defp retryable_error?({:error, error}) do
    case error do
      :timeout -> true
      :rate_limited -> true
      {:http_error, status} when status in 500..599 -> true
      _ -> false
    end
  end

  defp handle_error({:ok, result}), do: {:ok, result}

  defp handle_error({:error, :circuit_open}) do
    {:error, "Calendar service is temporarily unavailable."}
  end

  defp handle_error({:error, error}) do
    {:error, HAL.Resilience.format_error({:error, error})}
  end
end
```

### Email Integration

```elixir
defmodule HAL.Integrations.Email do
  @rate_limiter :email_rate_limiter
  @circuit_breaker :email_circuit_breaker

  def send_email(token, opts) do
    HAL.Resilience.call(
      fn -> send_via_gmail_api(token, opts) end,
      circuit_breaker: @circuit_breaker,
      rate_limiter: @rate_limiter,
      retry: [
        max_attempts: 2,
        base_delay: 200,
        retry_on: &retryable_error?/1
      ]
    )
    |> handle_error()
  end
end
```

## Telemetry Events

The resilience system emits telemetry events for monitoring:

```elixir
# Retry events
[:hal, :resilience, :retry, :start]       # Retry started
[:hal, :resilience, :retry, :attempt]     # Retry attempt
[:hal, :resilience, :retry, :success]     # Retry succeeded
[:hal, :resilience, :retry, :failure]     # All retries exhausted

# Circuit breaker events
[:hal, :resilience, :circuit_breaker, :open]       # Circuit opened
[:hal, :resilience, :circuit_breaker, :half_open]  # Circuit half-open
[:hal, :resilience, :circuit_breaker, :close]      # Circuit closed
[:hal, :resilience, :circuit_breaker, :call, :success]  # Call succeeded
[:hal, :resilience, :circuit_breaker, :call, :failure]  # Call failed

# Rate limit events
[:hal, :resilience, :rate_limit, :acquired]    # Token acquired
[:hal, :resilience, :rate_limit, :throttled]   # Request throttled
```

### Attaching Telemetry Handlers

```elixir
:telemetry.attach(
  "my-app-resilience-handler",
  [:hal, :resilience, :circuit_breaker, :open],
  fn _event_name, measurements, metadata, _config ->
    Logger.error("Circuit breaker opened: #{inspect(metadata)}")
    send_alert_to_pagerduty(metadata)
  end,
  nil
)
```

## Monitoring Dashboard

Access resilience metrics via LiveView dashboard (coming soon):

- Real-time circuit breaker states
- Rate limiter token availability
- Error rates and retry statistics
- Service health indicators
- Alert history

## Best Practices

### 1. Always Define Retryable Errors

Be explicit about which errors should trigger retries:

```elixir
defp retryable_error?({:error, error}) do
  case error do
    :timeout -> true
    :rate_limited -> true
    :connection_refused -> true
    {:http_error, status} when status in 500..599 -> true
    _ -> false
  end
end
```

### 2. Use Appropriate Retry Settings

Different operations need different retry strategies:

```elixir
# Read operations - aggressive retries
retry: [max_attempts: 3, base_delay: 100]

# Write operations - fewer retries, longer delays
retry: [max_attempts: 2, base_delay: 500]

# Idempotent operations - more retries OK
retry: [max_attempts: 5, base_delay: 100]
```

### 3. Handle Circuit Breaker States

Always provide user-friendly messages for circuit breaker states:

```elixir
defp handle_error({:error, :circuit_open}) do
  {:error, "Service temporarily unavailable. Please try again in a few minutes."}
end
```

### 4. Configure Rate Limits Conservatively

Start with conservative rate limits and increase based on actual API limits:

```elixir
# If API allows 100 req/sec, configure for 50 req/sec
rate_limiters: [
  my_api: [rate: 50, interval: 1000]
]
```

### 5. Monitor Health Regularly

Check health status periodically and alert on degradation:

```elixir
case HAL.Resilience.Monitor.get_health() do
  :healthy -> :ok
  :degraded -> Logger.warning("Resilience degraded")
  :unhealthy -> send_alert("Resilience unhealthy!")
end
```

## Testing

### Testing with Resilience Patterns

```elixir
defmodule MyApp.IntegrationTest do
  use ExUnit.Case

  test "retries on transient failures" do
    # Mock API that fails twice then succeeds
    mock_api = fn
      attempt when attempt < 3 -> {:error, :timeout}
      _attempt -> {:ok, "success"}
    end

    result = HAL.Resilience.retry(
      mock_api,
      max_attempts: 3,
      base_delay: 10
    )

    assert {:ok, "success"} = result
  end

  test "respects rate limits" do
    {:ok, limiter} = HAL.Resilience.RateLimiter.start_link(
      name: :test_limiter,
      rate: 5,
      interval: 1000
    )

    # First 5 should succeed
    Enum.each(1..5, fn _ ->
      assert :ok = HAL.Resilience.RateLimiter.try_acquire(:test_limiter)
    end)

    # 6th should be rate limited
    assert {:error, :rate_limited} = HAL.Resilience.RateLimiter.try_acquire(:test_limiter)
  end

  test "circuit breaker opens after threshold" do
    {:ok, breaker} = HAL.Resilience.CircuitBreaker.start_link(
      name: :test_breaker,
      failure_threshold: 3,
      timeout: 1000
    )

    # Fail 3 times to open circuit
    Enum.each(1..3, fn _ ->
      HAL.Resilience.CircuitBreaker.call(:test_breaker, fn ->
        {:error, :service_down}
      end)
    end)

    # Circuit should now be open
    assert {:error, :circuit_open} = HAL.Resilience.CircuitBreaker.call(
      :test_breaker,
      fn -> {:ok, "test"} end
    )
  end
end
```

## Troubleshooting

### Circuit Breaker Stuck Open

**Symptoms:** Circuit breaker stays open even when service recovers

**Solutions:**
- Check `timeout` setting - may be too long
- Increase `half_open_requests` to give more chances
- Manually reset: `HAL.Resilience.CircuitBreaker.reset(:breaker_name)`

### Rate Limiting Too Aggressive

**Symptoms:** Many requests throttled, slow response times

**Solutions:**
- Increase `rate` in rate limiter config
- Decrease `interval` for faster token replenishment
- Check if multiple limiters are applied to same request

### High Retry Rate

**Symptoms:** Many retries, increased latency

**Solutions:**
- Investigate root cause of failures
- Adjust `retry_on` function to be more selective
- Reduce `max_attempts` to fail faster
- Increase `base_delay` to give service more time to recover

### Memory Usage Growing

**Symptoms:** Increasing memory usage over time

**Solutions:**
- Check Monitor metrics window size
- Verify rate limiter waiters queue not growing unbounded
- Review circuit breaker state - may need manual intervention

## Performance Characteristics

### Rate Limiter
- **Memory:** O(1) per limiter + O(n) for waiting requests queue
- **CPU:** Minimal, periodic token refill
- **Latency:** ~1-10ms for acquire, 0ms for try_acquire

### Circuit Breaker
- **Memory:** O(1) per breaker
- **CPU:** Minimal, state checks and transitions
- **Latency:** <1ms overhead per call

### Monitor
- **Memory:** O(n) where n = events in window
- **CPU:** Low, periodic cleanup and aggregation
- **Latency:** No impact on requests

## Future Enhancements

- [ ] Adaptive rate limiting based on API responses
- [ ] Distributed circuit breakers (via Redis/ETS)
- [ ] Bulkhead pattern for resource isolation
- [ ] Hedging requests for reduced tail latency
- [ ] Grafana dashboard for metrics visualization
- [ ] Alert handlers for Slack, PagerDuty, etc.
- [ ] Per-user rate limiting
- [ ] Request prioritization/QoS

## References

- [Release It! by Michael Nygard](https://pragprog.com/titles/mnee2/release-it-second-edition/)
- [Martin Fowler - Circuit Breaker](https://martinfowler.com/bliki/CircuitBreaker.html)
- [Token Bucket Algorithm](https://en.wikipedia.org/wiki/Token_bucket)
- [Erlang/OTP Supervision Principles](https://www.erlang.org/doc/design_principles/sup_princ.html)
