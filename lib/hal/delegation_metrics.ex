defmodule HAL.DelegationMetrics do
  @moduledoc """
  Tracks delegation metrics for self-improvement.

  Collects data on which providers handle which tasks successfully,
  enabling HAL to optimize its delegation rules over time.

  ## Metrics Tracked

  - Delegation count per provider
  - Success/failure rates
  - Average response times
  - Task type distribution

  ## Usage

      # Record a delegation
      DelegationMetrics.record(:gemini, :research, :success, 1500)

      # Get summary stats
      DelegationMetrics.summary()

      # Check if review needed
      DelegationMetrics.review_needed?()
  """

  use GenServer
  require Logger

  @metrics_file ".claude/observations/delegation_metrics.json"
  @review_threshold 50

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record a delegation attempt.
  """
  @spec record(atom(), String.t(), :success | :failure, non_neg_integer()) :: :ok
  def record(provider, task_type, outcome, duration_ms) do
    GenServer.cast(__MODULE__, {:record, provider, task_type, outcome, duration_ms})
  end

  @doc """
  Get summary statistics.
  """
  @spec summary() :: map()
  def summary do
    GenServer.call(__MODULE__, :summary)
  end

  @doc """
  Get stats for a specific provider.
  """
  @spec provider_stats(atom()) :: map()
  def provider_stats(provider) do
    GenServer.call(__MODULE__, {:provider_stats, provider})
  end

  @doc """
  Check if delegation rules should be reviewed.
  """
  @spec review_needed?() :: boolean()
  def review_needed? do
    GenServer.call(__MODULE__, :review_needed?)
  end

  @doc """
  Get total delegation count since last review.
  """
  @spec total_delegations() :: non_neg_integer()
  def total_delegations do
    GenServer.call(__MODULE__, :total_delegations)
  end

  @doc """
  Mark that a review has been completed.
  """
  @spec mark_reviewed() :: :ok
  def mark_reviewed do
    GenServer.cast(__MODULE__, :mark_reviewed)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = load_metrics()
    {:ok, state}
  end

  @impl true
  def handle_cast({:record, provider, task_type, outcome, duration_ms}, state) do
    provider_key = to_string(provider)
    task_key = to_string(task_type)

    # Update provider metrics
    provider_metrics = Map.get(state.providers, provider_key, default_provider_metrics())

    updated_provider = %{
      provider_metrics
      | total: provider_metrics.total + 1,
        successes: provider_metrics.successes + if(outcome == :success, do: 1, else: 0),
        failures: provider_metrics.failures + if(outcome == :failure, do: 1, else: 0),
        total_duration_ms: provider_metrics.total_duration_ms + duration_ms,
        task_types: Map.update(provider_metrics.task_types, task_key, 1, &(&1 + 1))
    }

    new_state = %{
      state
      | providers: Map.put(state.providers, provider_key, updated_provider),
        total_since_review: state.total_since_review + 1,
        last_updated: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Persist metrics
    save_metrics(new_state)

    # Check if we should trigger a review
    if new_state.total_since_review >= @review_threshold do
      Logger.info("Delegation review threshold reached (#{@review_threshold} delegations)")
      trigger_review_observation(new_state)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:mark_reviewed, state) do
    new_state = %{
      state
      | total_since_review: 0,
        last_review: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    save_metrics(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:summary, _from, state) do
    summary = %{
      total_delegations: Enum.reduce(state.providers, 0, fn {_k, v}, acc -> acc + v.total end),
      total_since_review: state.total_since_review,
      last_review: state.last_review,
      providers:
        Enum.map(state.providers, fn {name, metrics} ->
          success_rate =
            if metrics.total > 0, do: metrics.successes / metrics.total * 100, else: 0

          avg_duration =
            if metrics.total > 0, do: metrics.total_duration_ms / metrics.total, else: 0

          {name,
           %{
             total: metrics.total,
             success_rate: Float.round(success_rate, 1),
             avg_duration_ms: round(avg_duration),
             top_task_types:
               metrics.task_types |> Enum.sort_by(fn {_k, v} -> -v end) |> Enum.take(3)
           }}
        end)
        |> Map.new()
    }

    {:reply, summary, state}
  end

  @impl true
  def handle_call({:provider_stats, provider}, _from, state) do
    stats = Map.get(state.providers, to_string(provider), default_provider_metrics())
    {:reply, stats, state}
  end

  @impl true
  def handle_call(:review_needed?, _from, state) do
    {:reply, state.total_since_review >= @review_threshold, state}
  end

  @impl true
  def handle_call(:total_delegations, _from, state) do
    {:reply, state.total_since_review, state}
  end

  # Private Functions

  defp default_provider_metrics do
    %{
      total: 0,
      successes: 0,
      failures: 0,
      total_duration_ms: 0,
      task_types: %{}
    }
  end

  defp default_state do
    %{
      providers: %{},
      total_since_review: 0,
      last_review: nil,
      last_updated: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp load_metrics do
    case File.read(@metrics_file) do
      {:ok, content} ->
        case Jason.decode(content, keys: :atoms) do
          {:ok, data} -> struct_from_map(data)
          {:error, _} -> default_state()
        end

      {:error, _} ->
        default_state()
    end
  end

  defp struct_from_map(data) do
    %{
      providers: data[:providers] || %{},
      total_since_review: data[:total_since_review] || 0,
      last_review: data[:last_review],
      last_updated: data[:last_updated]
    }
  end

  defp save_metrics(state) do
    File.mkdir_p!(Path.dirname(@metrics_file))
    File.write!(@metrics_file, Jason.encode!(state, pretty: true))
  end

  defp trigger_review_observation(state) do
    # Log an observation suggesting a delegation rules review
    summary = %{
      total_since_review: state.total_since_review,
      providers:
        Enum.map(state.providers, fn {name, m} ->
          rate = if m.total > 0, do: Float.round(m.successes / m.total * 100, 1), else: 0
          "#{name}: #{m.total} calls, #{rate}% success"
        end)
        |> Enum.join("; ")
    }

    HAL.Observations.log(%{
      type: "delegation_review_trigger",
      observation: "Reached #{@review_threshold} delegations since last review",
      impact: "Review delegation/rules.md and update based on observed patterns",
      metrics: summary.providers,
      confidence: "high"
    })
  end
end
