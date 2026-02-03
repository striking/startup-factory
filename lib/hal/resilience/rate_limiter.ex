defmodule HAL.Resilience.RateLimiter do
  @moduledoc """
  Token bucket rate limiter for API calls.

  Implements a token bucket algorithm to limit the rate of requests
  to external services. Tokens are replenished at a fixed rate, and
  each request consumes one token.

  ## Configuration

      config :hal, HAL.Resilience.RateLimiter,
        limiters: [
          google_calendar: [rate: 10, interval: 1000],
          gmail_api: [rate: 5, interval: 1000],
          openai_api: [rate: 3, interval: 1000]
        ]

  ## Usage

      # Start a rate limiter
      {:ok, pid} = HAL.Resilience.RateLimiter.start_link(
        name: :api_limiter,
        rate: 10,        # 10 tokens
        interval: 1000   # per 1000ms (1 second)
      )

      # Acquire a token (blocks until available)
      :ok = HAL.Resilience.RateLimiter.acquire(:api_limiter)

      # Try to acquire without blocking
      case HAL.Resilience.RateLimiter.try_acquire(:api_limiter) do
        :ok -> make_request()
        {:error, :rate_limited} -> # handle rate limit
      end

      # Check available tokens
      HAL.Resilience.RateLimiter.available(:api_limiter)
      #=> 7

  ## Token Bucket Algorithm

  The token bucket starts with `rate` tokens. Every `interval` milliseconds,
  the bucket is refilled to `rate` tokens. When a request is made:

  - If tokens are available, consume one and allow the request
  - If no tokens are available, either block until a token is available
    (acquire/2) or return an error (try_acquire/2)

  This allows for burst traffic up to `rate` requests, while maintaining
  an average rate of `rate / interval` requests per millisecond.
  """

  use GenServer
  require Logger

  @type limiter_name :: atom() | pid()
  @type rate :: pos_integer()
  @type interval :: pos_integer()

  defmodule State do
    @moduledoc false
    defstruct [
      :name,
      :rate,
      :interval,
      :tokens,
      :last_refill,
      :waiters
    ]

    @type t :: %__MODULE__{
            name: atom(),
            rate: pos_integer(),
            interval: pos_integer(),
            tokens: number(),
            last_refill: integer(),
            waiters: :queue.queue()
          }
  end

  # Client API

  @doc """
  Starts a rate limiter GenServer.

  ## Options

    * `:name` - Required. The registered name for this limiter
    * `:rate` - Required. Number of tokens in the bucket
    * `:interval` - Required. Refill interval in milliseconds
  """
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Acquires a token from the rate limiter.

  Blocks until a token is available. Use `try_acquire/2` for non-blocking.

  ## Options

    * `:timeout` - Maximum time to wait in milliseconds (default: 5000)
  """
  @spec acquire(limiter_name(), keyword()) :: :ok | {:error, :timeout}
  def acquire(limiter, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    GenServer.call(limiter, {:acquire, self()}, timeout)
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
  end

  @doc """
  Tries to acquire a token without blocking.

  Returns immediately with `:ok` if a token is available,
  or `{:error, :rate_limited}` if not.
  """
  @spec try_acquire(limiter_name()) :: :ok | {:error, :rate_limited}
  def try_acquire(limiter) do
    GenServer.call(limiter, :try_acquire)
  end

  @doc """
  Returns the number of available tokens.
  """
  @spec available(limiter_name()) :: non_neg_integer()
  def available(limiter) do
    GenServer.call(limiter, :available)
  end

  @doc """
  Resets the rate limiter to full capacity.
  """
  @spec reset(limiter_name()) :: :ok
  def reset(limiter) do
    GenServer.cast(limiter, :reset)
  end

  @doc """
  Returns the current state of the rate limiter (for debugging).
  """
  def get_state(limiter) do
    GenServer.call(limiter, :get_state)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    rate = Keyword.fetch!(opts, :rate)
    interval = Keyword.fetch!(opts, :interval)

    state = %State{
      name: name,
      rate: rate,
      interval: interval,
      tokens: rate,
      last_refill: System.monotonic_time(:millisecond),
      waiters: :queue.new()
    }

    # Schedule periodic refill
    schedule_refill(interval)

    Logger.info("Rate limiter started: #{name} (#{rate} tokens / #{interval}ms)")

    {:ok, state}
  end

  @impl true
  def handle_call({:acquire, pid}, from, state) do
    state = refill_tokens(state)

    if state.tokens >= 1 do
      new_state = %{state | tokens: state.tokens - 1}

      :telemetry.execute(
        [:hal, :resilience, :rate_limit, :acquired],
        %{tokens_remaining: new_state.tokens},
        %{limiter: state.name}
      )

      {:reply, :ok, new_state}
    else
      # No tokens available - add to waiters queue
      new_waiters = :queue.in({from, pid}, state.waiters)
      new_state = %{state | waiters: new_waiters}

      :telemetry.execute(
        [:hal, :resilience, :rate_limit, :throttled],
        %{queue_length: :queue.len(new_waiters)},
        %{limiter: state.name}
      )

      Logger.debug("Rate limit reached for #{state.name}, queuing request")

      {:noreply, new_state}
    end
  end

  @impl true
  def handle_call(:try_acquire, _from, state) do
    state = refill_tokens(state)

    if state.tokens >= 1 do
      new_state = %{state | tokens: state.tokens - 1}

      :telemetry.execute(
        [:hal, :resilience, :rate_limit, :acquired],
        %{tokens_remaining: new_state.tokens},
        %{limiter: state.name}
      )

      {:reply, :ok, new_state}
    else
      :telemetry.execute(
        [:hal, :resilience, :rate_limit, :throttled],
        %{tokens_remaining: 0},
        %{limiter: state.name}
      )

      {:reply, {:error, :rate_limited}, state}
    end
  end

  @impl true
  def handle_call(:available, _from, state) do
    state = refill_tokens(state)
    {:reply, trunc(state.tokens), state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    state = refill_tokens(state)
    {:reply, state, state}
  end

  @impl true
  def handle_cast(:reset, state) do
    new_state = %{
      state
      | tokens: state.rate,
        last_refill: System.monotonic_time(:millisecond),
        waiters: :queue.new()
    }

    Logger.info("Rate limiter reset: #{state.name}")
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:refill, state) do
    state = refill_tokens(state)
    state = process_waiters(state)
    schedule_refill(state.interval)
    {:noreply, state}
  end

  # Private Functions

  defp refill_tokens(state) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - state.last_refill

    if elapsed >= state.interval do
      # Full refill
      %{state | tokens: state.rate, last_refill: now}
    else
      # Partial refill based on elapsed time
      # tokens_to_add = (elapsed / interval) * rate
      tokens_to_add = elapsed / state.interval * state.rate
      new_tokens = min(state.tokens + tokens_to_add, state.rate)
      %{state | tokens: new_tokens, last_refill: now}
    end
  end

  defp process_waiters(%{tokens: tokens, waiters: waiters} = state) when tokens >= 1 do
    case :queue.out(waiters) do
      {{:value, {from, _pid}}, new_waiters} ->
        GenServer.reply(from, :ok)

        new_state = %{
          state
          | tokens: tokens - 1,
            waiters: new_waiters
        }

        :telemetry.execute(
          [:hal, :resilience, :rate_limit, :waiter_processed],
          %{tokens_remaining: new_state.tokens},
          %{limiter: state.name}
        )

        # Process more waiters if tokens available
        process_waiters(new_state)

      {:empty, _} ->
        state
    end
  end

  defp process_waiters(state), do: state

  defp schedule_refill(interval) do
    # Refill more frequently for smoother rate limiting
    refill_interval = div(interval, 10)
    Process.send_after(self(), :refill, max(refill_interval, 10))
  end
end
