defmodule HAL.Resilience do
  @moduledoc """
  Core resilience patterns for HAL system.

  This module provides reusable patterns for building fault-tolerant
  integrations with external services:

  1. **Retry Logic** - Exponential backoff with jitter
  2. **Rate Limiting** - Token bucket algorithm
  3. **Circuit Breakers** - Automatic failure detection and recovery
  4. **Graceful Degradation** - Fallback strategies
  5. **Error Monitoring** - Telemetry-based alerting

  ## Usage

  ### Retry with Exponential Backoff

      HAL.Resilience.retry(fn ->
        HTTPoison.get("https://api.example.com")
      end, max_attempts: 3, base_delay: 100)

  ### Rate Limiting

      {:ok, limiter} = HAL.Resilience.RateLimiter.start_link(
        name: :api_limiter,
        rate: 10,
        interval: 1000
      )

      HAL.Resilience.RateLimiter.acquire(:api_limiter)

  ### Circuit Breaker

      {:ok, breaker} = HAL.Resilience.CircuitBreaker.start_link(
        name: :api_breaker,
        failure_threshold: 5,
        timeout: 60_000
      )

      HAL.Resilience.CircuitBreaker.call(:api_breaker, fn ->
        external_api_call()
      end)

  ## Telemetry Events

  This module emits telemetry events for monitoring:

  - `[:hal, :resilience, :retry, :start]` - Retry attempt started
  - `[:hal, :resilience, :retry, :success]` - Retry succeeded
  - `[:hal, :resilience, :retry, :failure]` - All retries exhausted
  - `[:hal, :resilience, :circuit_breaker, :open]` - Circuit opened
  - `[:hal, :resilience, :circuit_breaker, :close]` - Circuit closed
  - `[:hal, :resilience, :rate_limit, :throttled]` - Request throttled
  """

  require Logger

  @type retry_opts :: [
          max_attempts: pos_integer(),
          base_delay: pos_integer(),
          max_delay: pos_integer(),
          jitter: boolean(),
          backoff_factor: number(),
          retry_on: (any() -> boolean())
        ]

  @doc """
  Executes a function with retry logic and exponential backoff.

  ## Options

    * `:max_attempts` - Maximum number of attempts (default: 3)
    * `:base_delay` - Initial delay in milliseconds (default: 100)
    * `:max_delay` - Maximum delay in milliseconds (default: 10_000)
    * `:jitter` - Add random jitter to delays (default: true)
    * `:backoff_factor` - Exponential backoff multiplier (default: 2)
    * `:retry_on` - Function to determine if error should be retried (default: retry all)

  ## Examples

      # Simple retry
      {:ok, result} = HAL.Resilience.retry(fn ->
        {:ok, HTTPoison.get!("https://api.example.com")}
      end)

      # Custom retry logic
      {:ok, result} = HAL.Resilience.retry(fn ->
        case make_api_call() do
          {:ok, result} -> {:ok, result}
          {:error, :rate_limited} -> {:error, :rate_limited}
          {:error, _} = error -> error
        end
      end,
        max_attempts: 5,
        base_delay: 200,
        retry_on: fn
          {:error, :rate_limited} -> true
          {:error, :timeout} -> true
          _ -> false
        end
      )
  """
  @spec retry(function(), retry_opts()) :: {:ok, any()} | {:error, any()}
  def retry(func, opts \\ []) when is_function(func, 0) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    base_delay = Keyword.get(opts, :base_delay, 100)
    max_delay = Keyword.get(opts, :max_delay, 10_000)
    jitter = Keyword.get(opts, :jitter, true)
    backoff_factor = Keyword.get(opts, :backoff_factor, 2)
    retry_on = Keyword.get(opts, :retry_on, fn _ -> true end)

    do_retry(func, 1, max_attempts, base_delay, max_delay, jitter, backoff_factor, retry_on)
  end

  @doc """
  Wraps a function with circuit breaker protection.

  This is a convenience function that uses a named circuit breaker.
  For better performance, consider using the CircuitBreaker GenServer directly.

  ## Examples

      {:ok, result} = HAL.Resilience.with_circuit_breaker(:api_breaker, fn ->
        external_api_call()
      end)
  """
  def with_circuit_breaker(name, func) do
    HAL.Resilience.CircuitBreaker.call(name, func)
  end

  @doc """
  Wraps a function with rate limiting.

  ## Examples

      {:ok, result} = HAL.Resilience.with_rate_limit(:api_limiter, fn ->
        external_api_call()
      end)
  """
  def with_rate_limit(name, func) do
    case HAL.Resilience.RateLimiter.acquire(name) do
      :ok -> func.()
      {:error, :rate_limited} = error -> error
    end
  end

  @doc """
  Combines retry, circuit breaker, and rate limiting.

  This is the recommended high-level API for resilient external calls.

  ## Examples

      {:ok, result} = HAL.Resilience.call(
        fn -> HTTPoison.get("https://api.example.com") end,
        circuit_breaker: :api_breaker,
        rate_limiter: :api_limiter,
        retry: [max_attempts: 3, base_delay: 100]
      )
  """
  def call(func, opts \\ []) do
    circuit_breaker = Keyword.get(opts, :circuit_breaker)
    rate_limiter = Keyword.get(opts, :rate_limiter)
    retry_opts = Keyword.get(opts, :retry, [])

    wrapped_func = fn ->
      result =
        case rate_limiter do
          nil -> func.()
          name -> with_rate_limit(name, func)
        end

      case result do
        {:ok, _} = success -> success
        {:error, _} = error -> error
        other -> {:ok, other}
      end
    end

    final_func =
      case circuit_breaker do
        nil -> wrapped_func
        name -> fn -> with_circuit_breaker(name, wrapped_func) end
      end

    if retry_opts != [] do
      retry(final_func, retry_opts)
    else
      final_func.()
    end
  end

  # Private Functions

  defp do_retry(
         func,
         attempt,
         max_attempts,
         base_delay,
         max_delay,
         jitter,
         backoff_factor,
         retry_on
       ) do
    start_time = System.monotonic_time(:millisecond)

    :telemetry.execute(
      [:hal, :resilience, :retry, :start],
      %{attempt: attempt},
      %{max_attempts: max_attempts}
    )

    result = func.()

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, _} = success ->
        :telemetry.execute(
          [:hal, :resilience, :retry, :success],
          %{attempt: attempt, duration: duration},
          %{}
        )

        success

      {:error, _} = error ->
        should_retry = attempt < max_attempts and retry_on.(error)

        if should_retry do
          delay = calculate_delay(attempt, base_delay, max_delay, jitter, backoff_factor)

          Logger.warning(
            "Retry attempt #{attempt}/#{max_attempts} failed: #{inspect(error)}. Retrying in #{delay}ms..."
          )

          :telemetry.execute(
            [:hal, :resilience, :retry, :attempt],
            %{attempt: attempt, delay: delay, duration: duration},
            %{error: error}
          )

          Process.sleep(delay)

          do_retry(
            func,
            attempt + 1,
            max_attempts,
            base_delay,
            max_delay,
            jitter,
            backoff_factor,
            retry_on
          )
        else
          :telemetry.execute(
            [:hal, :resilience, :retry, :failure],
            %{attempt: attempt, duration: duration},
            %{error: error}
          )

          Logger.error(
            "All retry attempts exhausted (#{attempt}/#{max_attempts}): #{inspect(error)}"
          )

          error
        end

      other ->
        # Handle non-standard returns
        Logger.warning("Retry function returned unexpected value: #{inspect(other)}")
        {:ok, other}
    end
  end

  defp calculate_delay(attempt, base_delay, max_delay, jitter, backoff_factor) do
    # Exponential backoff: base_delay * (backoff_factor ^ (attempt - 1))
    delay = base_delay * :math.pow(backoff_factor, attempt - 1)
    delay = min(trunc(delay), max_delay)

    if jitter do
      # Add random jitter between 0% and 25% of delay
      jitter_amount = trunc(delay * 0.25 * :rand.uniform())
      delay + jitter_amount
    else
      delay
    end
  end

  @doc """
  Formats error for user-friendly display.

  ## Examples

      iex> HAL.Resilience.format_error({:error, :timeout})
      "Request timed out. Please try again."

      iex> HAL.Resilience.format_error({:error, :circuit_open})
      "Service temporarily unavailable. Please try again in a few minutes."
  """
  def format_error({:error, error}) do
    case error do
      :timeout ->
        "Request timed out. Please try again."

      :circuit_open ->
        "Service temporarily unavailable. Please try again in a few minutes."

      :rate_limited ->
        "Too many requests. Please wait a moment and try again."

      :connection_refused ->
        "Unable to connect to the service. It may be temporarily down."

      {:http_error, status} when status in 500..599 ->
        "The service is experiencing issues (error #{status}). Please try again later."

      {:http_error, 429} ->
        "Rate limit exceeded. Please wait a moment and try again."

      {:http_error, 401} ->
        "Authentication failed. Please check your API credentials."

      {:http_error, 403} ->
        "Access denied. You don't have permission to access this resource."

      {:http_error, 404} ->
        "Resource not found."

      _ ->
        "An error occurred: #{inspect(error)}"
    end
  end

  def format_error(other), do: inspect(other)
end
