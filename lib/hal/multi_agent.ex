defmodule HAL.MultiAgent do
  @moduledoc """
  Multi-agent coordination for complex parallel tasks.

  Provides a simple interface for HAL to spawn specialized sub-agents
  that work in parallel and have their results aggregated.

  ## Use Cases

  1. **Multi-source Research**
     ```
     MultiAgent.research(user_id, "AI trends 2024", sources: [:academic, :news, :blogs])
     ```

  2. **Multi-perspective Analysis**
     ```
     MultiAgent.analyze(user_id, document, perspectives: [:technical, :business, :user])
     ```

  3. **Parallel Code Review**
     ```
     MultiAgent.review_code(user_id, code, aspects: [:security, :performance, :style])
     ```

  ## How It Works

  1. You specify a task and the agents/perspectives you want
  2. Sub-agents are spawned in parallel
  3. Each agent works on its assigned piece
  4. Results are aggregated (synthesis, vote, list, or best)
  5. You get a unified response

  ## Cost Tracking

  Each job tracks token usage across all agents. Use `status/1` to check:
  - Total tokens used
  - Per-agent token breakdown
  - Execution duration
  """

  alias HAL.MultiAgent.Orchestrator

  @doc """
  Executes a multi-agent research task.

  Spawns researcher agents to gather information from multiple angles.

  ## Options

    * `:sources` - Types of sources to research (default: general)
    * `:depth` - How deep to research (:quick, :normal, :thorough)
    * `:aggregate` - How to combine results (:synthesis, :list)

  ## Examples

      MultiAgent.research(user_id, "Latest Elixir developments")
      MultiAgent.research(user_id, "AI safety", sources: [:academic, :industry])
  """
  @spec research(binary(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def research(user_id, topic, opts \\ []) do
    sources = Keyword.get(opts, :sources, [:general])
    depth = Keyword.get(opts, :depth, :normal)

    agents = build_research_agents(topic, sources, depth)

    case Orchestrator.create_job(user_id, %{
           task: "Research: #{topic}",
           agents: agents,
           aggregation: :synthesis
         }) do
      {:ok, job} -> Orchestrator.execute(job.id)
      error -> error
    end
  end

  @doc """
  Executes a multi-perspective analysis.

  Spawns analyst agents that examine the subject from different angles.

  ## Options

    * `:perspectives` - Analysis perspectives (default: [:technical, :practical])
    * `:include_critic` - Add a critic to evaluate findings (default: true)

  ## Examples

      MultiAgent.analyze(user_id, "Our API design", perspectives: [:security, :usability])
  """
  @spec analyze(binary(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def analyze(user_id, subject, opts \\ []) do
    perspectives = Keyword.get(opts, :perspectives, [:technical, :practical])
    include_critic = Keyword.get(opts, :include_critic, true)

    agents = build_analysis_agents(subject, perspectives, include_critic)

    case Orchestrator.create_job(user_id, %{
           task: "Analysis: #{String.slice(subject, 0, 50)}",
           agents: agents,
           aggregation: :synthesis
         }) do
      {:ok, job} -> Orchestrator.execute(job.id)
      error -> error
    end
  end

  @doc """
  Executes parallel code review.

  Spawns specialized reviewers for different aspects of the code.

  ## Options

    * `:aspects` - Review aspects (default: [:correctness, :style])
    * `:language` - Programming language hint

  ## Examples

      MultiAgent.review_code(user_id, code, aspects: [:security, :performance])
  """
  @spec review_code(binary(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def review_code(user_id, code, opts \\ []) do
    aspects = Keyword.get(opts, :aspects, [:correctness, :style])
    language = Keyword.get(opts, :language)

    agents = build_code_review_agents(code, aspects, language)

    case Orchestrator.create_job(user_id, %{
           task: "Code Review",
           agents: agents,
           aggregation: :list
         }) do
      {:ok, job} -> Orchestrator.execute(job.id)
      error -> error
    end
  end

  @doc """
  Executes a custom multi-agent job.

  For when you need full control over agents and aggregation.

  ## Example

      MultiAgent.custom(user_id, %{
        task: "Evaluate startup idea",
        agents: [
          %{role: :analyst, prompt: "Evaluate market size"},
          %{role: :critic, prompt: "Identify risks"},
          %{role: :custom, prompt: "Compare to competitors", persona: "VC analyst"}
        ],
        aggregation: :synthesis
      })
  """
  @spec custom(binary(), map()) :: {:ok, map()} | {:error, term()}
  def custom(user_id, job_spec) do
    case Orchestrator.create_job(user_id, job_spec) do
      {:ok, job} -> Orchestrator.execute(job.id)
      error -> error
    end
  end

  @doc """
  Gets the status and results of a job.
  """
  @spec status(String.t()) :: map() | nil
  def status(job_id) do
    Orchestrator.status(job_id)
  end

  @doc """
  Lists recent jobs for a user.
  """
  @spec list_jobs(binary()) :: [map()]
  def list_jobs(user_id) do
    Orchestrator.list_jobs(user_id)
  end

  @doc """
  Cancels a running job.
  """
  @spec cancel(String.t()) :: :ok | {:error, term()}
  def cancel(job_id) do
    Orchestrator.cancel(job_id)
  end

  # ============================================
  # Private Helpers - AI-Driven Agent Selection
  # ============================================

  defp build_research_agents(topic, sources, depth) do
    # If sources are explicitly provided, use them as hints
    # Otherwise, let Claude decide
    source_hints = if sources == [:general], do: nil, else: sources

    case design_agents_with_ai(:research, topic, depth: depth, hints: source_hints) do
      {:ok, agents} -> agents
      {:error, _} -> fallback_research_agents(topic, depth)
    end
  end

  defp build_analysis_agents(subject, perspectives, include_critic) do
    # Let Claude decide the best perspectives if only defaults provided
    perspective_hints = if perspectives == [:technical, :practical], do: nil, else: perspectives

    case design_agents_with_ai(:analysis, subject,
           hints: perspective_hints,
           include_critic: include_critic
         ) do
      {:ok, agents} -> agents
      {:error, _} -> fallback_analysis_agents(subject, include_critic)
    end
  end

  defp build_code_review_agents(code, aspects, language) do
    # Let Claude decide what aspects to review
    aspect_hints = if aspects == [:correctness, :style], do: nil, else: aspects

    case design_agents_with_ai(:code_review, code, hints: aspect_hints, language: language) do
      {:ok, agents} -> agents
      {:error, _} -> fallback_code_review_agents(code, language)
    end
  end

  @doc false
  # Use Claude to design the optimal set of agents for a task
  defp design_agents_with_ai(task_type, subject, opts) do
    hints = Keyword.get(opts, :hints)
    depth = Keyword.get(opts, :depth, :normal)
    include_critic = Keyword.get(opts, :include_critic, true)
    language = Keyword.get(opts, :language)

    prompt = """
    Design a team of AI agents to #{describe_task(task_type)} this subject:

    Subject: #{String.slice(to_string(subject), 0, 1000)}
    #{if hints, do: "User hints: #{inspect(hints)}", else: ""}
    #{if language, do: "Language: #{language}", else: ""}
    #{if task_type == :research, do: "Depth: #{depth}", else: ""}
    #{if task_type == :analysis and include_critic, do: "Include a critic agent.", else: ""}

    Design 2-4 specialized agents. Each agent should have a unique perspective that adds value.
    Consider: What angles would a human expert team cover? What's often overlooked?

    Respond with JSON array:
    [
      {"role": "researcher|analyst|coder|critic", "prompt": "specific task for this agent", "persona": "expert identity"}
    ]

    Return ONLY the JSON array, no explanation.
    """

    case Hal.AI.Gemini.prompt(nil, prompt, stream: false, max_tokens: 500) do
      {:ok, response, _session_id} ->
        parse_agent_design(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp describe_task(:research), do: "research and gather information about"
  defp describe_task(:analysis), do: "analyze from multiple perspectives"
  defp describe_task(:code_review), do: "review and evaluate"

  defp parse_agent_design(response) do
    case Regex.run(~r/\[[\s\S]*\]/s, response) do
      [json | _] ->
        case Jason.decode(json, keys: :atoms) do
          {:ok, agents} when is_list(agents) ->
            valid_agents =
              Enum.filter(agents, fn a ->
                is_map(a) and Map.has_key?(a, :prompt)
              end)

            if length(valid_agents) > 0 do
              {:ok, valid_agents}
            else
              {:error, :no_valid_agents}
            end

          _ ->
            {:error, :parse_failed}
        end

      nil ->
        {:error, :no_json}
    end
  end

  # Fallback agents if AI design fails
  defp fallback_research_agents(topic, depth) do
    base = if depth == :thorough, do: "Conduct comprehensive research on", else: "Research"

    [
      %{
        role: :researcher,
        prompt: "#{base} #{topic} covering key facts, developments, and expert opinions.",
        persona: "Research specialist"
      },
      %{
        role: :researcher,
        prompt: "#{base} #{topic} focusing on practical applications and real-world examples.",
        persona: "Practical analyst"
      }
    ]
  end

  defp fallback_analysis_agents(subject, include_critic) do
    agents = [
      %{
        role: :analyst,
        prompt: "Analyze the strengths, opportunities, and potential of: #{subject}",
        persona: "Optimistic strategist"
      },
      %{
        role: :analyst,
        prompt: "Analyze the challenges, risks, and practical concerns of: #{subject}",
        persona: "Pragmatic evaluator"
      }
    ]

    if include_critic do
      agents ++
        [
          %{
            role: :critic,
            prompt: "Critically evaluate weaknesses and areas for improvement: #{subject}",
            persona: "Constructive critic"
          }
        ]
    else
      agents
    end
  end

  defp fallback_code_review_agents(code, language) do
    lang = if language, do: " (#{language})", else: ""

    [
      %{
        role: :coder,
        prompt:
          "Review this code#{lang} for correctness and potential bugs:\n\n```\n#{code}\n```",
        persona: "Code reviewer"
      },
      %{
        role: :coder,
        prompt:
          "Review this code#{lang} for security, performance, and best practices:\n\n```\n#{code}\n```",
        persona: "Senior engineer"
      }
    ]
  end
end
