defmodule HAL.SelfImprovement.ImprovementManager do
  @moduledoc """
  Manages pending improvements with review, A/B testing, and rollback capabilities.

  ## Workflow

  1. Analyzer proposes improvements → stored in pending_improvements.json
  2. User reviews proposals → approve, reject, or A/B test
  3. Approved improvements are applied with backup
  4. A/B tested improvements run for N days, then auto-evaluate
  5. Rollback available for any applied improvement

  ## A/B Testing

  When an improvement is A/B tested:
  - 50% of interactions use the improvement
  - Metrics are tracked separately
  - After test period, winner is determined automatically
  """

  require Logger

  @pending_path ".claude/pending_improvements.json"
  @active_path ".claude/active_improvements.json"
  @ab_tests_path ".claude/ab_tests.json"

  @doc """
  Lists pending improvements awaiting review.
  """
  @spec list_pending() :: [map()]
  def list_pending do
    load_json(@pending_path)
  end

  @doc """
  Lists active improvements.
  """
  @spec list_active() :: [map()]
  def list_active do
    load_json(@active_path)
  end

  @doc """
  Lists active A/B tests.
  """
  @spec list_ab_tests() :: [map()]
  def list_ab_tests do
    load_json(@ab_tests_path)
  end

  @doc """
  Approves and applies an improvement.
  """
  @spec approve(integer()) :: {:ok, map()} | {:error, term()}
  def approve(index) do
    pending = list_pending()

    case Enum.at(pending, index) do
      nil ->
        {:error, :not_found}

      improvement ->
        # Apply the improvement
        case apply_improvement(improvement) do
          {:ok, applied} ->
            # Remove from pending
            new_pending = List.delete_at(pending, index)
            save_json(@pending_path, new_pending)

            # Add to active
            active = list_active()
            save_json(@active_path, active ++ [applied])

            Logger.info("Applied improvement: #{improvement[:description]}")
            {:ok, applied}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Rejects an improvement (removes from pending).
  """
  @spec reject(integer(), String.t()) :: :ok
  def reject(index, reason \\ "User rejected") do
    pending = list_pending()

    case Enum.at(pending, index) do
      nil ->
        {:error, :not_found}

      improvement ->
        # Log rejection
        HAL.Observations.log(%{
          type: "improvement_rejected",
          improvement: improvement[:description],
          reason: reason
        })

        # Remove from pending
        new_pending = List.delete_at(pending, index)
        save_json(@pending_path, new_pending)

        Logger.info("Rejected improvement: #{improvement[:description]}")
        :ok
    end
  end

  @doc """
  Starts an A/B test for an improvement.

  The improvement will be applied to 50% of interactions.
  After `days` days, results are evaluated.
  """
  @spec start_ab_test(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def start_ab_test(index, opts \\ []) do
    days = Keyword.get(opts, :days, 7)
    pending = list_pending()

    case Enum.at(pending, index) do
      nil ->
        {:error, :not_found}

      improvement ->
        # Create A/B test record
        test = %{
          id: Ecto.UUID.generate(),
          improvement: improvement,
          started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          ends_at: DateTime.utc_now() |> DateTime.add(days, :day) |> DateTime.to_iso8601(),
          status: "running",
          metrics: %{
            control: %{interactions: 0, successes: 0, failures: 0, avg_duration_ms: 0},
            treatment: %{interactions: 0, successes: 0, failures: 0, avg_duration_ms: 0}
          }
        }

        # Remove from pending
        new_pending = List.delete_at(pending, index)
        save_json(@pending_path, new_pending)

        # Add to A/B tests
        tests = list_ab_tests()
        save_json(@ab_tests_path, tests ++ [test])

        Logger.info("Started A/B test for: #{improvement[:description]}")
        {:ok, test}
    end
  end

  @doc """
  Records an interaction result for A/B testing.

  Call this when an interaction completes to track metrics.
  """
  @spec record_ab_interaction(String.t(), :control | :treatment, map()) :: :ok
  def record_ab_interaction(test_id, variant, result) do
    tests = list_ab_tests()

    updated =
      Enum.map(tests, fn test ->
        if test[:id] == test_id do
          metrics = test[:metrics]
          variant_key = to_string(variant)

          variant_metrics =
            metrics[variant_key] ||
              %{
                interactions: 0,
                successes: 0,
                failures: 0,
                avg_duration_ms: 0
              }

          new_metrics =
            variant_metrics
            |> Map.update(:interactions, 1, &(&1 + 1))
            |> update_success_failure(result[:success])
            |> update_avg_duration(result[:duration_ms])

          put_in(test, [:metrics, variant_key], new_metrics)
        else
          test
        end
      end)

    save_json(@ab_tests_path, updated)
    :ok
  end

  @doc """
  Evaluates completed A/B tests and applies winners.
  """
  @spec evaluate_completed_tests() :: [map()]
  def evaluate_completed_tests do
    now = DateTime.utc_now()
    tests = list_ab_tests()

    {completed, still_running} =
      Enum.split_with(tests, fn test ->
        {:ok, ends_at, _} = DateTime.from_iso8601(test[:ends_at])
        DateTime.compare(now, ends_at) != :lt
      end)

    results =
      Enum.map(completed, fn test ->
        result = evaluate_test(test)

        case result[:winner] do
          :treatment ->
            # Apply the improvement
            apply_improvement(test[:improvement])

            Logger.info(
              "A/B test winner: treatment - applying #{test[:improvement][:description]}"
            )

          :control ->
            Logger.info(
              "A/B test winner: control - not applying #{test[:improvement][:description]}"
            )

          :inconclusive ->
            Logger.info("A/B test inconclusive for #{test[:improvement][:description]}")
        end

        Map.put(test, :result, result)
      end)

    # Update tests file
    save_json(@ab_tests_path, still_running)

    # Log completed tests
    Enum.each(results, fn test ->
      HAL.Observations.log(%{
        type: "ab_test_completed",
        improvement: test[:improvement][:description],
        winner: test[:result][:winner],
        control_success_rate: test[:result][:control_rate],
        treatment_success_rate: test[:result][:treatment_rate]
      })
    end)

    results
  end

  @doc """
  Rolls back an active improvement.
  """
  @spec rollback(integer()) :: {:ok, String.t()} | {:error, term()}
  def rollback(index) do
    active = list_active()

    case Enum.at(active, index) do
      nil ->
        {:error, :not_found}

      improvement ->
        case HAL.SelfImprovement.revert_last() do
          {:ok, msg} ->
            # Remove from active
            new_active = List.delete_at(active, index)
            save_json(@active_path, new_active)

            Logger.info("Rolled back improvement: #{improvement[:description]}")
            {:ok, msg}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Gets whether an interaction should use treatment (for A/B testing).

  Returns the test ID and variant if there's an active test.
  """
  @spec get_ab_variant() :: {:ok, String.t(), :control | :treatment} | :no_test
  def get_ab_variant do
    tests = list_ab_tests()

    running =
      Enum.find(tests, fn test ->
        test[:status] == "running"
      end)

    case running do
      nil ->
        :no_test

      test ->
        # 50/50 split
        variant = if :rand.uniform() < 0.5, do: :control, else: :treatment
        {:ok, test[:id], variant}
    end
  end

  # Private Functions

  defp apply_improvement(improvement) do
    # Delegate to main SelfImprovement module
    improvement_with_file =
      Map.merge(improvement, %{
        file: "delegation/rules.md",
        change: %{
          action: :append_rule,
          content: "\n\n## Auto-applied: #{improvement[:description]}\n#{improvement[:rationale]}"
        }
      })

    case HAL.SelfImprovement.apply_improvement(improvement_with_file) do
      {:ok, _msg} ->
        applied =
          Map.merge(improvement, %{
            applied_at: DateTime.utc_now() |> DateTime.to_iso8601(),
            status: "active"
          })

        {:ok, applied}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp evaluate_test(test) do
    control = test[:metrics]["control"] || test[:metrics][:control] || %{}
    treatment = test[:metrics]["treatment"] || test[:metrics][:treatment] || %{}

    control_rate = calculate_success_rate(control)
    treatment_rate = calculate_success_rate(treatment)

    # Require at least 10 interactions per variant for valid test
    min_interactions = 10

    winner =
      cond do
        control[:interactions] < min_interactions or treatment[:interactions] < min_interactions ->
          :inconclusive

        treatment_rate > control_rate + 5 ->
          # Treatment is at least 5% better
          :treatment

        control_rate > treatment_rate + 5 ->
          # Control is at least 5% better
          :control

        true ->
          :inconclusive
      end

    %{
      winner: winner,
      control_rate: control_rate,
      treatment_rate: treatment_rate,
      control_interactions: control[:interactions] || 0,
      treatment_interactions: treatment[:interactions] || 0
    }
  end

  defp calculate_success_rate(%{interactions: 0}), do: 0

  defp calculate_success_rate(%{interactions: total, successes: successes}) do
    round(successes / total * 100)
  end

  defp calculate_success_rate(_), do: 0

  defp update_success_failure(metrics, true), do: Map.update(metrics, :successes, 1, &(&1 + 1))
  defp update_success_failure(metrics, false), do: Map.update(metrics, :failures, 1, &(&1 + 1))
  defp update_success_failure(metrics, _), do: metrics

  defp update_avg_duration(metrics, nil), do: metrics

  defp update_avg_duration(metrics, duration_ms) do
    n = metrics[:interactions] || 1
    old_avg = metrics[:avg_duration_ms] || 0
    # Running average
    new_avg = old_avg + (duration_ms - old_avg) / n
    Map.put(metrics, :avg_duration_ms, round(new_avg))
  end

  defp load_json(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content, keys: :atoms) do
          {:ok, list} when is_list(list) -> list
          _ -> []
        end

      {:error, _} ->
        []
    end
  end

  defp save_json(path, data) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(data, pretty: true))
  end
end
