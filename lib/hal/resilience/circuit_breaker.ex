defmodule HAL.Resilience.CircuitBreaker do
  @moduledoc """
  Circuit breaker pattern for fault tolerance.

  Implements the circuit breaker pattern to prevent cascading failures
  when external services are experiencing issues. The circuit has three states:

  - **Closed** - Normal operation, requests pass through
  - **Open** - Service is failing, requests fail immediately
  - **Half-Open** - Testing if service has recovered

  ## State Transitions

      Closed --[failures >= threshold]--> Open
      Open --[timeout elapsed]--> Half-Open
      Half-Open --[success]--> Closed
      Half-Open --[failure]--> Open

  ## Configuration

      config :hal, HAL.Resilience.CircuitBreaker,
        breakers: [
          google_calendar: [failure_threshold: 5, timeout: 60_000, half_open_requests: 3],
          gmail_api: [failure_threshold: 3, timeout: 30_000],
          openai_api: [failure_threshold: 10, timeout: 120_000]
        ]

  ## Usage

      # Start a circuit breaker
      {:ok, pid} = HAL.Resilience.CircuitBreaker.start_link(
        name: :api_breaker,
        failure_threshold: 5,    # Open after 5 consecutive failures
        timeout: 60_000,         # Stay open for 60 seconds
        half_open_requests: 3    # Try 3 requests in half-open state
      )

      # Execute a function through the circuit breaker
      case HAL.Resilience.CircuitBreaker.call(:api_breaker, fn ->
        HTTPoison.get("https://api.example.com")
      end) do
        {:ok, result} -> result
        {:error, :circuit_open} -> # Service is down
        {:error, reason} -> # Other error
      end

  ## Telemetry Events

  - `[:hal, :resilience, :circuit_breaker, :open]` - Circuit opened
  - `[:hal, :resilience, :circuit_breaker, :close]` - Circuit closed
  - `[:hal, :resilience, :circuit_breaker, :half_open]` - Circuit half-open
  - `[:hal, :resilience, :circuit_breaker, :call, :success]` - Call succeeded
  - `[:hal, :resilience, :circuit_breaker, :call, :failure]` - Call failed
  """

  use GenServer
  require Logger

  @type breaker_name :: atom() | pid()
  @type state_name :: :closed | :open | :half_open

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            name: atom(),
            failure_threshold: pos_integer(),
            timeout: pos_integer(),
            half_open_requests: pos_integer(),
            state: :closed | :open | :half_open,
            failure_count: non_neg_integer(),
            success_count: non_neg_integer(),
            last_failure_time: integer() | nil,
            half_open_attempts: non_neg_integer()
          }

    defstruct [
      :name,
      :failure_threshold,
      :timeout,
      :half_open_requests,
      :state,
      :failure_count,
      :success_count,
      :last_failure_time,
      :half_open_attempts
    ]
  end

  # Client API

  @doc """
  Starts a circuit breaker GenServer.

  ## Options

    * `:name` - Required. The registered name for this breaker
    * `:failure_threshold` - Number of failures before opening (default: 5)
    * `:timeout` - Time to wait before trying half-open in ms (default: 60_000)
    * `:half_open_requests` - Number of requests to try in half-open state (default: 3)
  """
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Executes a function through the circuit breaker.

  ## Returns

    * `{:ok, result}` - Function succeeded
    * `{:error, :circuit_open}` - Circuit is open, request rejected
    * `{:error, reason}` - Function failed with reason
  """
  @spec call(breaker_name(), function()) :: {:ok, any()} | {:error, any()}
  def call(breaker, func) when is_function(func, 0) do
    case GenServer.call(breaker, :can_execute?) do
      :ok ->
        execute_and_record(breaker, func)

      {:error, :circuit_open} = error ->
        error
    end
  end

  @doc """
  Returns the current state of the circuit breaker.
  """
  @spec get_state(breaker_name()) :: state_name()
  def get_state(breaker) do
    GenServer.call(breaker, :get_state)
  end

  @doc """
  Returns full state information (for debugging).
  """
  def get_info(breaker) do
    GenServer.call(breaker, :get_info)
  end

  @doc """
  Manually resets the circuit breaker to closed state.
  """
  @spec reset(breaker_name()) :: :ok
  def reset(breaker) do
    GenServer.cast(breaker, :reset)
  end

  @doc """
  Manually opens the circuit breaker.
  """
  @spec open(breaker_name()) :: :ok
  def open(breaker) do
    GenServer.cast(breaker, :open)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    failure_threshold = Keyword.get(opts, :failure_threshold, 5)
    timeout = Keyword.get(opts, :timeout, 60_000)
    half_open_requests = Keyword.get(opts, :half_open_requests, 3)

    state = %State{
      name: name,
      failure_threshold: failure_threshold,
      timeout: timeout,
      half_open_requests: half_open_requests,
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure_time: nil,
      half_open_attempts: 0
    }

    Logger.info(
      "Circuit breaker started: #{name} (threshold: #{failure_threshold}, timeout: #{timeout}ms)"
    )

    {:ok, state}
  end

  @impl true
  def handle_call(:can_execute?, _from, state) do
    state = maybe_transition_to_half_open(state)

    case state.state do
      :closed ->
        {:reply, :ok, state}

      :half_open ->
        if state.half_open_attempts < state.half_open_requests do
          {:reply, :ok, %{state | half_open_attempts: state.half_open_attempts + 1}}
        else
          {:reply, {:error, :circuit_open}, state}
        end

      :open ->
        {:reply, {:error, :circuit_open}, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    state = maybe_transition_to_half_open(state)
    {:reply, state.state, state}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    state = maybe_transition_to_half_open(state)

    info = %{
      state: state.state,
      failure_count: state.failure_count,
      success_count: state.success_count,
      failure_threshold: state.failure_threshold,
      timeout: state.timeout,
      last_failure_time: state.last_failure_time,
      half_open_attempts: state.half_open_attempts
    }

    {:reply, info, state}
  end

  @impl true
  def handle_cast(:reset, state) do
    new_state = %{
      state
      | state: :closed,
        failure_count: 0,
        success_count: 0,
        last_failure_time: nil,
        half_open_attempts: 0
    }

    Logger.info("Circuit breaker reset: #{state.name}")

    :telemetry.execute(
      [:hal, :resilience, :circuit_breaker, :reset],
      %{},
      %{breaker: state.name}
    )

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:open, state) do
    new_state = transition_to_open(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_success}, state) do
    new_state = handle_success(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_failure, _reason}, state) do
    new_state = handle_failure(state)
    {:noreply, new_state}
  end

  # Private Functions

  defp execute_and_record(breaker, func) do
    start_time = System.monotonic_time(:millisecond)

    try do
      result = func.()
      duration = System.monotonic_time(:millisecond) - start_time

      case result do
        {:ok, _} = success ->
          GenServer.cast(breaker, {:record_success})

          :telemetry.execute(
            [:hal, :resilience, :circuit_breaker, :call, :success],
            %{duration: duration},
            %{}
          )

          success

        {:error, _} = error ->
          GenServer.cast(breaker, {:record_failure, error})

          :telemetry.execute(
            [:hal, :resilience, :circuit_breaker, :call, :failure],
            %{duration: duration},
            %{error: error}
          )

          error

        other ->
          # Treat non-standard returns as success
          GenServer.cast(breaker, {:record_success})
          {:ok, other}
      end
    rescue
      exception ->
        duration = System.monotonic_time(:millisecond) - start_time
        error = {:error, {:exception, exception}}

        GenServer.cast(breaker, {:record_failure, error})

        :telemetry.execute(
          [:hal, :resilience, :circuit_breaker, :call, :failure],
          %{duration: duration},
          %{error: error}
        )

        error
    end
  end

  defp handle_success(state) do
    case state.state do
      :closed ->
        # In closed state, success resets failure count
        %{state | failure_count: 0, success_count: state.success_count + 1}

      :half_open ->
        # In half-open, success moves toward closed
        new_success_count = state.success_count + 1

        if new_success_count >= state.half_open_requests do
          transition_to_closed(state)
        else
          %{state | success_count: new_success_count, failure_count: 0}
        end

      :open ->
        # Shouldn't happen, but reset counts
        state
    end
  end

  defp handle_failure(state) do
    case state.state do
      :closed ->
        new_failure_count = state.failure_count + 1

        if new_failure_count >= state.failure_threshold do
          transition_to_open(%{state | failure_count: new_failure_count})
        else
          %{state | failure_count: new_failure_count}
        end

      :half_open ->
        # Any failure in half-open goes back to open
        transition_to_open(state)

      :open ->
        # Already open, update last failure time
        %{state | last_failure_time: System.monotonic_time(:millisecond)}
    end
  end

  defp transition_to_open(state) do
    Logger.warning(
      "Circuit breaker opened: #{state.name} (failures: #{state.failure_count}/#{state.failure_threshold})"
    )

    :telemetry.execute(
      [:hal, :resilience, :circuit_breaker, :open],
      %{failure_count: state.failure_count},
      %{breaker: state.name}
    )

    %{
      state
      | state: :open,
        last_failure_time: System.monotonic_time(:millisecond),
        half_open_attempts: 0
    }
  end

  defp transition_to_half_open(state) do
    Logger.info("Circuit breaker half-open: #{state.name}")

    :telemetry.execute(
      [:hal, :resilience, :circuit_breaker, :half_open],
      %{},
      %{breaker: state.name}
    )

    %{
      state
      | state: :half_open,
        failure_count: 0,
        success_count: 0,
        half_open_attempts: 0
    }
  end

  defp transition_to_closed(state) do
    Logger.info("Circuit breaker closed: #{state.name}")

    :telemetry.execute(
      [:hal, :resilience, :circuit_breaker, :close],
      %{},
      %{breaker: state.name}
    )

    %{
      state
      | state: :closed,
        failure_count: 0,
        success_count: 0,
        half_open_attempts: 0,
        last_failure_time: nil
    }
  end

  defp maybe_transition_to_half_open(%{state: :open} = state) do
    now = System.monotonic_time(:millisecond)
    time_since_failure = now - (state.last_failure_time || now)

    if time_since_failure >= state.timeout do
      transition_to_half_open(state)
    else
      state
    end
  end

  defp maybe_transition_to_half_open(state), do: state
end
