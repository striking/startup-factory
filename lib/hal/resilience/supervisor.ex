defmodule HAL.Resilience.Supervisor do
  @moduledoc """
  Supervisor for resilience components (rate limiters and circuit breakers).

  This supervisor starts and manages:
  - Rate limiters for each external service
  - Circuit breakers for each external service
  - Resilience monitor for metrics and alerting

  ## Configuration

  Configure rate limits and circuit breaker settings in config/runtime.exs:

      config :hal, HAL.Resilience,
        rate_limiters: [
          calendar: [rate: 10, interval: 1000],
          email: [rate: 10, interval: 1000],
          tasks: [rate: 10, interval: 1000],
          openai: [rate: 3, interval: 1000],
          gemini: [rate: 10, interval: 1000]
        ],
        circuit_breakers: [
          calendar: [failure_threshold: 5, timeout: 60_000],
          email: [failure_threshold: 5, timeout: 60_000],
          tasks: [failure_threshold: 5, timeout: 60_000],
          openai: [failure_threshold: 10, timeout: 120_000],
          gemini: [failure_threshold: 5, timeout: 60_000]
        ]
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children =
      [
        # Start rate limiters
        rate_limiter_specs(),
        # Start circuit breakers
        circuit_breaker_specs(),
        # Start monitor
        HAL.Resilience.Monitor
      ]
      |> List.flatten()

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp rate_limiter_specs do
    rate_limiters = get_config(:rate_limiters, default_rate_limiters())

    Enum.map(rate_limiters, fn {name, opts} ->
      limiter_name = limiter_name(name)
      opts = Keyword.put(opts, :name, limiter_name)

      %{
        id: {:rate_limiter, name},
        start: {HAL.Resilience.RateLimiter, :start_link, [opts]},
        restart: :permanent
      }
    end)
  end

  defp circuit_breaker_specs do
    breakers = get_config(:circuit_breakers, default_circuit_breakers())

    Enum.map(breakers, fn {name, opts} ->
      breaker_name = breaker_name(name)
      opts = Keyword.put(opts, :name, breaker_name)

      %{
        id: {:circuit_breaker, name},
        start: {HAL.Resilience.CircuitBreaker, :start_link, [opts]},
        restart: :permanent
      }
    end)
  end

  defp default_rate_limiters do
    [
      calendar: [rate: 10, interval: 1000],
      email: [rate: 10, interval: 1000],
      tasks: [rate: 10, interval: 1000],
      openai: [rate: 3, interval: 1000],
      gemini: [rate: 10, interval: 1000]
    ]
  end

  defp default_circuit_breakers do
    [
      # External service breakers
      calendar: [failure_threshold: 5, timeout: 60_000, half_open_requests: 3],
      email: [failure_threshold: 5, timeout: 60_000, half_open_requests: 3],
      tasks: [failure_threshold: 5, timeout: 60_000, half_open_requests: 3],
      # AI provider breakers - more tolerant since AI calls can be slow
      openai: [failure_threshold: 10, timeout: 120_000, half_open_requests: 5],
      gemini: [failure_threshold: 5, timeout: 60_000, half_open_requests: 3],
      # Claude providers - separate breakers for different clients
      claude_code: [failure_threshold: 5, timeout: 180_000, half_open_requests: 3],
      claude_sdk: [failure_threshold: 5, timeout: 180_000, half_open_requests: 3],
      claude_python: [failure_threshold: 5, timeout: 180_000, half_open_requests: 3]
    ]
  end

  defp get_config(key, default) do
    Application.get_env(:hal, HAL.Resilience, [])
    |> Keyword.get(key, default)
  end

  defp limiter_name(name) do
    :"#{name}_rate_limiter"
  end

  defp breaker_name(name) do
    :"#{name}_circuit_breaker"
  end

  # Public API for getting breaker/limiter names

  @doc """
  Returns the registered name for a circuit breaker.

  ## Examples

      iex> HAL.Resilience.Supervisor.get_breaker_name(:claude_code)
      :claude_code_circuit_breaker
  """
  def get_breaker_name(name), do: breaker_name(name)

  @doc """
  Returns the registered name for a rate limiter.
  """
  def get_limiter_name(name), do: limiter_name(name)

  @doc """
  Checks if a circuit breaker exists and is healthy.
  Returns {:ok, :closed | :half_open} or {:error, :circuit_open | :not_found}
  """
  def breaker_status(name) do
    breaker = breaker_name(name)

    try do
      case HAL.Resilience.CircuitBreaker.get_state(breaker) do
        :closed -> {:ok, :closed}
        :half_open -> {:ok, :half_open}
        :open -> {:error, :circuit_open}
      end
    catch
      :exit, _ -> {:error, :not_found}
    end
  end
end
