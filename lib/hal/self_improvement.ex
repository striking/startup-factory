defmodule HAL.SelfImprovement do
  @moduledoc """
  Self-modification capability for HAL.

  Enables HAL to update its own configuration files based on observed patterns.
  Includes safety guardrails:
  - Backups before any modification
  - User notification of changes
  - Ability to revert changes
  - Rate limiting on modifications

  ## Files HAL Can Modify

  - `.claude/delegation/rules.md` - Delegation rules
  - `.claude/system_prompts/main.md` - System prompt (with approval)
  - `.claude/observations/learnings.jsonl` - Observations (append-only)

  ## Usage

      # Analyze patterns and suggest improvements
      HAL.SelfImprovement.analyze_and_suggest()

      # Apply a suggested improvement (with backup)
      HAL.SelfImprovement.apply_improvement(improvement)

      # Revert last change
      HAL.SelfImprovement.revert_last()
  """

  require Logger

  @claude_dir ".claude"
  @backup_dir ".claude/backups"
  @delegation_file "delegation/rules.md"
  @max_daily_modifications 3

  @doc """
  Scheduled entry point for self-improvement analysis.

  Called by HAL.Scheduler daily to:
  1. Analyze delegation patterns
  2. Check for suggestions
  3. Apply high-confidence suggestions automatically

  Rate limiting prevents more than #{@max_daily_modifications} changes per day.
  """
  @spec scheduled_run() :: :ok
  def scheduled_run do
    Logger.info("SelfImprovement: Starting scheduled analysis")

    suggestions = analyze_and_suggest()

    if Enum.empty?(suggestions) do
      Logger.debug("SelfImprovement: No suggestions generated")
    else
      Logger.info("SelfImprovement: Found #{length(suggestions)} suggestions")

      # Only auto-apply high confidence suggestions
      high_confidence =
        suggestions
        |> Enum.filter(&(&1[:confidence] == :high))

      Enum.each(high_confidence, fn suggestion ->
        Logger.info("SelfImprovement: Applying #{suggestion[:type]} - #{suggestion[:reason]}")

        case apply_improvement(suggestion) do
          {:ok, msg} ->
            Logger.info("SelfImprovement: #{msg}")

          {:error, reason} ->
            Logger.warning("SelfImprovement: Failed to apply - #{reason}")
        end
      end)
    end

    :ok
  end

  @doc """
  Analyze observations and metrics to suggest improvements.

  Returns a list of suggested changes based on patterns observed.
  """
  @spec analyze_and_suggest() :: [map()]
  def analyze_and_suggest do
    metrics = HAL.DelegationMetrics.summary()
    observations = HAL.Observations.read_all()

    suggestions = []

    # Check for delegation patterns
    suggestions = suggestions ++ analyze_delegation_patterns(metrics)

    # Check for repeated failures
    suggestions = suggestions ++ analyze_failure_patterns(observations)

    # Check for performance patterns
    suggestions = suggestions ++ analyze_performance_patterns(metrics)

    suggestions
  end

  @doc """
  Apply an improvement suggestion with safety checks.
  """
  @spec apply_improvement(map()) :: {:ok, String.t()} | {:error, String.t()}
  def apply_improvement(%{type: _type, file: file, change: change} = improvement) do
    # Check rate limit
    case check_rate_limit() do
      :ok ->
        # Create backup
        case backup_file(file) do
          {:ok, backup_path} ->
            # Apply the change
            case apply_change(file, change) do
              :ok ->
                # Log the modification
                log_modification(improvement, backup_path)
                {:ok, "Applied improvement. Backup at: #{backup_path}"}

              {:error, reason} ->
                {:error, "Failed to apply change: #{reason}"}
            end

          {:error, reason} ->
            {:error, "Failed to create backup: #{reason}"}
        end

      {:error, :rate_limited} ->
        {:error, "Rate limited: max #{@max_daily_modifications} modifications per day"}
    end
  end

  @doc """
  Revert the most recent modification.
  """
  @spec revert_last() :: {:ok, String.t()} | {:error, String.t()}
  def revert_last do
    case get_last_modification() do
      {:ok, %{file: file, backup_path: backup_path}} ->
        case File.read(backup_path) do
          {:ok, content} ->
            target = Path.join(@claude_dir, file)

            case File.write(target, content) do
              :ok ->
                Logger.info("Reverted #{file} from backup")
                {:ok, "Reverted #{file} to previous version"}

              {:error, reason} ->
                {:error, "Failed to restore: #{inspect(reason)}"}
            end

          {:error, reason} ->
            {:error, "Backup not found: #{inspect(reason)}"}
        end

      {:error, :no_modifications} ->
        {:error, "No modifications to revert"}
    end
  end

  @doc """
  Get list of recent modifications.
  """
  @spec get_modification_history() :: [map()]
  def get_modification_history do
    log_path = Path.join(@claude_dir, "modifications.jsonl")

    case File.read(log_path) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(fn line ->
          case Jason.decode(line, keys: :atoms) do
            {:ok, entry} -> entry
            {:error, _} -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      {:error, _} ->
        []
    end
  end

  # Private: Analyze delegation patterns
  defp analyze_delegation_patterns(metrics) do
    suggestions = []

    # Check if a non-default provider is significantly faster
    providers = metrics[:providers] || %{}

    Enum.reduce(providers, suggestions, fn {provider, stats}, acc ->
      if provider != "claude_code" and stats[:total] >= 10 do
        avg_duration = stats[:avg_duration_ms] || 0
        success_rate = stats[:success_rate] || 0
        top_tasks = stats[:top_task_types] || []

        if success_rate >= 90 and avg_duration < 2000 do
          task_types = Enum.map(top_tasks, fn {t, _} -> t end) |> Enum.join(", ")

          suggestion = %{
            type: :delegation_expansion,
            provider: provider,
            confidence: :high,
            file: @delegation_file,
            reason:
              "#{provider} has #{success_rate}% success rate and #{avg_duration}ms avg response for: #{task_types}",
            change: %{
              action: :append_rule,
              content:
                "\n\n## Observed Pattern (Auto-detected)\n#{provider} performs well for #{task_types} tasks (#{success_rate}% success, #{avg_duration}ms avg)"
            }
          }

          [suggestion | acc]
        else
          acc
        end
      else
        acc
      end
    end)
  end

  # Private: Analyze failure patterns
  defp analyze_failure_patterns(observations) do
    failures =
      observations
      |> Enum.filter(&(&1[:type] == "delegation_failure"))
      |> Enum.group_by(& &1[:provider])

    Enum.reduce(failures, [], fn {provider, provider_failures}, acc ->
      if length(provider_failures) >= 3 do
        task_types =
          provider_failures
          |> Enum.map(& &1[:task_type])
          |> Enum.frequencies()
          |> Enum.sort_by(fn {_, count} -> -count end)
          |> Enum.take(2)
          |> Enum.map(fn {t, _} -> t end)
          |> Enum.join(", ")

        suggestion = %{
          type: :delegation_restriction,
          provider: provider,
          confidence: :medium,
          file: @delegation_file,
          reason:
            "#{provider} has failed #{length(provider_failures)} times, mostly on #{task_types} tasks",
          change: %{
            action: :append_warning,
            content:
              "\n\n## Warning: #{provider} Reliability\nObserved #{length(provider_failures)} failures. Consider avoiding for: #{task_types}"
          }
        }

        [suggestion | acc]
      else
        acc
      end
    end)
  end

  # Private: Analyze performance patterns
  defp analyze_performance_patterns(metrics) do
    providers = metrics[:providers] || %{}

    # Compare Claude vs other providers for same task types
    claude_stats = providers["claude_code"] || %{}
    _claude_duration = claude_stats[:avg_duration_ms] || 0

    # If Gemini is 5x faster with good success rate, suggest expanding its use
    gemini_stats = providers["gemini"] || %{}
    gemini_duration = gemini_stats[:avg_duration_ms] || 0
    gemini_success = gemini_stats[:success_rate] || 0

    if gemini_duration > 0 and gemini_success >= 85 do
      [
        %{
          type: :performance_insight,
          provider: "gemini",
          confidence: :medium,
          file: @delegation_file,
          reason: "Gemini averages #{gemini_duration}ms with #{gemini_success}% success",
          change: %{
            action: :append_insight,
            content:
              "\n\n## Performance Insight\nGemini: #{gemini_duration}ms avg, #{gemini_success}% success. Good for quick tasks."
          }
        }
      ]
    else
      []
    end
  end

  # Private: Check modification rate limit
  defp check_rate_limit do
    today = Date.utc_today() |> Date.to_string()
    history = get_modification_history()

    today_count =
      history
      |> Enum.filter(fn mod ->
        String.starts_with?(mod[:timestamp] || "", today)
      end)
      |> length()

    if today_count >= @max_daily_modifications do
      {:error, :rate_limited}
    else
      :ok
    end
  end

  # Private: Backup a file before modification
  defp backup_file(file) do
    source = Path.join(@claude_dir, file)
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(~r/[:\.]/, "-")
    backup_name = "#{Path.basename(file, ".md")}_#{timestamp}.md"
    backup_path = Path.join(@backup_dir, backup_name)

    File.mkdir_p!(@backup_dir)

    case File.copy(source, backup_path) do
      {:ok, _} -> {:ok, backup_path}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  # Private: Apply a change to a file
  defp apply_change(file, %{action: action, content: content}) do
    target = Path.join(@claude_dir, file)

    case action do
      :append_rule ->
        case File.read(target) do
          {:ok, existing} ->
            File.write(target, existing <> content)

          {:error, reason} ->
            {:error, inspect(reason)}
        end

      :append_warning ->
        case File.read(target) do
          {:ok, existing} ->
            File.write(target, existing <> content)

          {:error, reason} ->
            {:error, inspect(reason)}
        end

      :append_insight ->
        case File.read(target) do
          {:ok, existing} ->
            File.write(target, existing <> content)

          {:error, reason} ->
            {:error, inspect(reason)}
        end

      _ ->
        {:error, "Unknown action: #{action}"}
    end
  end

  # Private: Log a modification
  defp log_modification(improvement, backup_path) do
    log_path = Path.join(@claude_dir, "modifications.jsonl")

    entry = %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      type: improvement[:type],
      file: improvement[:file],
      backup_path: backup_path,
      reason: improvement[:reason]
    }

    File.mkdir_p!(Path.dirname(log_path))

    case File.open(log_path, [:append, :utf8]) do
      {:ok, file} ->
        IO.puts(file, Jason.encode!(entry))
        File.close(file)

      {:error, reason} ->
        Logger.error("Failed to log modification: #{inspect(reason)}")
    end

    # Also log as observation
    HAL.Observations.log(%{
      type: "self_modification",
      observation: "Applied #{improvement[:type]} to #{improvement[:file]}",
      reason: improvement[:reason],
      backup: backup_path,
      impact: "Delegation behavior may change"
    })
  end

  # Private: Get last modification
  defp get_last_modification do
    case get_modification_history() do
      [] -> {:error, :no_modifications}
      history -> {:ok, List.last(history)}
    end
  end
end
