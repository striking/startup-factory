defmodule HAL.SelfImprovement.AnalyzerWorker do
  @moduledoc """
  Oban worker that periodically analyzes HAL's behavior and proposes improvements.

  Uses Claude to intelligently analyze:
  - Failure patterns from event log
  - Response quality trends
  - Tool usage patterns
  - User satisfaction signals

  Runs daily during maintenance hours.
  """

  use Oban.Worker,
    queue: :scheduled,
    max_attempts: 1

  require Logger

  alias HAL.EventLog
  alias HAL.AgentState
  alias HAL.DelegationMetrics
  alias HAL.Autonomy.Brain
  alias Hal.Accounts.DefaultUser
  alias Hal.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Self-improvement analyzer starting...")

    # Gather data for analysis
    context = gather_analysis_context()

    # Use Claude to analyze and propose improvements
    case analyze_with_claude(context) do
      {:ok, analysis} ->
        process_analysis(analysis)

      {:error, reason} ->
        Logger.warning("Self-improvement analysis failed: #{inspect(reason)}")
    end

    :ok
  end

  @doc """
  Manually trigger analysis (for testing or on-demand).
  """
  @spec run_analysis() :: {:ok, map()} | {:error, term()}
  def run_analysis do
    context = gather_analysis_context()
    analyze_with_claude(context)
  end

  # Private Functions

  defp gather_analysis_context do
    # Get recent events from log
    recent_events = EventLog.recent(limit: 100)

    # Get agent state
    state = AgentState.get_context()

    # Get delegation metrics
    metrics = DelegationMetrics.summary()

    # Get recent failures
    failures = AgentState.get_failed_tasks(limit: 20)

    # Get learned facts
    learned = state.learned_facts

    %{
      events: summarize_events(recent_events),
      failures: format_failures(failures),
      metrics: metrics,
      learned_facts: learned,
      current_tasks: state.current_tasks,
      completed_tasks: length(state.recent_completions)
    }
  end

  defp summarize_events(events) do
    events
    |> Enum.group_by(&(&1["event"] || "unknown"))
    |> Enum.map(fn {type, items} ->
      %{type: type, count: length(items)}
    end)
  end

  defp format_failures(failures) do
    Enum.map(failures, fn f ->
      %{
        task: f[:task] || f["task"],
        reason: f[:reason] || f["reason"],
        timestamp: f[:timestamp] || f["timestamp"]
      }
    end)
  end

  defp analyze_with_claude(context) do
    prompt = build_analysis_prompt(context)

    case DefaultUser.get() do
      %{} = user ->
        case Brain.prompt(prompt,
               user_id: user.id,
               hal_session_id: "self-improvement",
               channel_type: "terminal",
               channel_id: "self:improvement",
               timeout: 180_000
             ) do
          {:ok, response} -> parse_analysis(response)
          {:error, reason} -> {:error, reason}
        end

      nil ->
        {:error, :no_user}
    end
  end

  defp build_analysis_prompt(context) do
    """
    You are HAL's self-improvement analyzer. Analyze recent behavior and propose improvements.

    ## Recent Activity Summary
    - Event types: #{Jason.encode!(context.events)}
    - Completed tasks: #{context.completed_tasks}
    - Current tasks: #{inspect(context.current_tasks)}

    ## Recent Failures
    #{format_failures_for_prompt(context.failures)}

    ## Delegation Metrics
    #{format_metrics_for_prompt(context.metrics)}

    ## Learned Facts
    #{Enum.join(context.learned_facts, "\n")}

    ## Analysis Task

    Analyze this data and identify:

    1. **Failure Patterns**: What types of tasks or situations consistently fail?
    2. **Performance Issues**: Are there slow or inefficient patterns?
    3. **Improvement Opportunities**: Concrete changes that could help.
    4. **Positive Patterns**: What's working well that should continue?

    Respond with JSON in this exact format:
    {
      "failure_patterns": [
        {"pattern": "description", "frequency": "high/medium/low", "suggested_fix": "action"}
      ],
      "performance_issues": [
        {"issue": "description", "impact": "high/medium/low", "suggested_fix": "action"}
      ],
      "improvements": [
        {
          "type": "delegation_rule|prompt_refinement|error_handling|tool_usage",
          "description": "what to change",
          "rationale": "why this helps",
          "confidence": "high/medium/low",
          "priority": 1-5
        }
      ],
      "positive_patterns": ["pattern1", "pattern2"],
      "summary": "2-3 sentence summary of overall health"
    }
    """
  end

  defp format_failures_for_prompt([]), do: "No recent failures recorded."

  defp format_failures_for_prompt(failures) do
    failures
    |> Enum.take(10)
    |> Enum.map(fn f -> "- #{f.task}: #{f.reason}" end)
    |> Enum.join("\n")
  end

  defp format_metrics_for_prompt(nil), do: "No metrics available."

  defp format_metrics_for_prompt(metrics) do
    providers = metrics[:providers] || %{}

    providers
    |> Enum.map(fn {name, stats} ->
      "- #{name}: #{stats[:total] || 0} calls, #{stats[:success_rate] || 0}% success, #{stats[:avg_duration_ms] || 0}ms avg"
    end)
    |> Enum.join("\n")
  end

  defp parse_analysis(response) do
    # Extract JSON from response
    case Regex.run(~r/\{[\s\S]*\}/s, response) do
      [json | _] ->
        case Jason.decode(json, keys: :atoms) do
          {:ok, analysis} -> {:ok, analysis}
          {:error, _} -> {:error, :json_parse_failed}
        end

      nil ->
        {:error, :no_json_found}
    end
  end

  defp process_analysis(analysis) do
    Logger.info("Self-improvement analysis complete: #{analysis[:summary]}")

    # Log the analysis
    HAL.Observations.log(%{
      type: "self_improvement_analysis",
      summary: analysis[:summary],
      failure_patterns: length(analysis[:failure_patterns] || []),
      improvements_found: length(analysis[:improvements] || []),
      positive_patterns: analysis[:positive_patterns]
    })

    # Process high-confidence improvements
    improvements = analysis[:improvements] || []

    high_priority =
      improvements
      |> Enum.filter(fn i -> i[:confidence] == "high" and (i[:priority] || 5) <= 2 end)

    if length(high_priority) > 0 do
      # Generate improvement suggestions and store for review
      store_improvement_proposals(high_priority)

      # Notify about pending improvements (if user wants notifications)
      notify_pending_improvements(length(high_priority))
    end

    # Learn from positive patterns
    Enum.each(analysis[:positive_patterns] || [], fn pattern ->
      AgentState.learned("Positive pattern: #{pattern}", confidence: 0.8)
    end)

    # Learn from failure patterns
    Enum.each(analysis[:failure_patterns] || [], fn pattern ->
      if pattern[:frequency] == "high" do
        AgentState.learned("Avoid: #{pattern[:pattern]} - #{pattern[:suggested_fix]}",
          confidence: 0.9
        )
      end
    end)

    :ok
  end

  defp store_improvement_proposals(improvements) do
    proposals_path = ".claude/pending_improvements.json"

    existing =
      case File.read(proposals_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, list} when is_list(list) -> list
            _ -> []
          end

        {:error, _} ->
          []
      end

    # Add new proposals with timestamp
    new_proposals =
      Enum.map(improvements, fn imp ->
        Map.merge(imp, %{
          proposed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          status: "pending"
        })
      end)

    all_proposals = existing ++ new_proposals

    File.mkdir_p!(Path.dirname(proposals_path))
    File.write!(proposals_path, Jason.encode!(all_proposals, pretty: true))

    Logger.info("Stored #{length(new_proposals)} improvement proposals for review")
  end

  defp notify_pending_improvements(count) do
    # Find a web user to notify (or use admin notification)
    case Hal.Repo.get_by(Hal.Accounts.User, external_id: "web-chat-user") do
      nil ->
        Logger.info("No web user found for improvement notification")

      user ->
        message = """
        🔧 *HAL Self-Improvement*

        I've analyzed my recent behavior and identified #{count} potential improvement(s).

        View pending improvements at /dashboard or ask me "show pending improvements".
        """

        Notifications.send(user, message, fallback: true)
    end
  end
end
