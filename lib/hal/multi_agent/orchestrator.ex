defmodule HAL.MultiAgent.Orchestrator do
  @moduledoc """
  Orchestrates multiple specialized sub-agents for parallel task execution.

  Enables HAL to spawn sub-agents for:
  - Parallel research from multiple sources
  - Multi-perspective analysis
  - Concurrent code review
  - Distributed task execution

  ## Architecture

  ```
  ┌─────────────────────────────────────────────────────────┐
  │                    Orchestrator                          │
  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐   │
  │  │ Agent 1 │  │ Agent 2 │  │ Agent 3 │  │ Agent N │   │
  │  │ Research│  │ Analysis│  │ Critique│  │ ...     │   │
  │  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘   │
  │       │            │            │            │          │
  │       └────────────┴──────────┬─┴────────────┘          │
  │                               │                          │
  │                     ┌─────────▼─────────┐               │
  │                     │ Result Aggregation │               │
  │                     └───────────────────┘               │
  └─────────────────────────────────────────────────────────┘
  ```

  ## Usage

      # Define a parallel task
      {:ok, job} = Orchestrator.create_job(user_id, %{
        task: "Research AI trends",
        agents: [
          %{role: :researcher, prompt: "Find recent AI papers"},
          %{role: :researcher, prompt: "Find AI startup news"},
          %{role: :critic, prompt: "Evaluate importance of findings"}
        ],
        aggregation: :synthesis  # How to combine results
      })

      # Start execution
      Orchestrator.execute(job.id)

      # Check status
      Orchestrator.status(job.id)
  """

  use GenServer
  require Logger

  alias HAL.AgentRegistry
  alias HAL.Autonomy.Brain

  @type job_id :: String.t()
  @type agent_role :: :researcher | :analyst | :critic | :coder | :writer | :custom

  defstruct [
    :id,
    :user_id,
    :task,
    :agents,
    :aggregation,
    :status,
    :results,
    :aggregated_result,
    :cost_tokens,
    :max_tokens,
    :timeout_ms,
    :started_at,
    :completed_at,
    :error
  ]

  # ============================================
  # Client API
  # ============================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates a new multi-agent job.

  ## Options

    * `:task` - Description of the overall task
    * `:agents` - List of agent specs (role, prompt, optional persona)
    * `:aggregation` - How to combine results (:synthesis, :vote, :list, :best)
    * `:max_tokens` - Token budget (default: 10000)
    * `:timeout` - Execution timeout in ms (default: 60000)
  """
  @spec create_job(binary(), map()) :: {:ok, %__MODULE__{}} | {:error, term()}
  def create_job(user_id, opts) do
    GenServer.call(__MODULE__, {:create_job, user_id, opts})
  end

  @doc """
  Executes a job, spawning sub-agents in parallel.
  """
  @spec execute(job_id()) :: {:ok, %__MODULE__{}} | {:error, term()}
  def execute(job_id) do
    GenServer.call(__MODULE__, {:execute, job_id}, 120_000)
  end

  @doc """
  Gets the status of a job.
  """
  @spec status(job_id()) :: %__MODULE__{} | nil
  def status(job_id) do
    GenServer.call(__MODULE__, {:status, job_id})
  end

  @doc """
  Lists all jobs for a user.
  """
  @spec list_jobs(binary()) :: [%__MODULE__{}]
  def list_jobs(user_id) do
    GenServer.call(__MODULE__, {:list_jobs, user_id})
  end

  @doc """
  Cancels a running job.
  """
  @spec cancel(job_id()) :: :ok | {:error, term()}
  def cancel(job_id) do
    GenServer.call(__MODULE__, {:cancel, job_id})
  end

  # ============================================
  # Server Callbacks
  # ============================================

  @impl true
  def init(_opts) do
    {:ok, %{jobs: %{}}}
  end

  @impl true
  def handle_call({:create_job, user_id, opts}, _from, state) do
    job = %__MODULE__{
      id: Ecto.UUID.generate(),
      user_id: user_id,
      task: opts[:task],
      agents: normalize_agents(opts[:agents] || []),
      aggregation: opts[:aggregation] || :synthesis,
      status: :pending,
      results: %{},
      aggregated_result: nil,
      cost_tokens: 0,
      max_tokens: opts[:max_tokens] || 10_000,
      timeout_ms: opts[:timeout] || 60_000,
      started_at: nil,
      completed_at: nil,
      error: nil
    }

    new_state = put_in(state, [:jobs, job.id], job)
    {:reply, {:ok, job}, new_state}
  end

  @impl true
  def handle_call({:execute, job_id}, _from, state) do
    case get_in(state, [:jobs, job_id]) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{status: status} when status != :pending ->
        {:reply, {:error, :already_executed}, state}

      job ->
        # Update status
        job = %{job | status: :running, started_at: DateTime.utc_now()}
        state = put_in(state, [:jobs, job_id], job)

        # Execute agents in parallel
        result = execute_parallel(job)

        # Update with results
        job =
          case result do
            {:ok, results, tokens} ->
              # Aggregate results
              aggregated = aggregate_results(job, results)

              %{
                job
                | status: :completed,
                  results: results,
                  aggregated_result: aggregated,
                  cost_tokens: tokens,
                  completed_at: DateTime.utc_now()
              }

            {:error, reason} ->
              %{
                job
                | status: :failed,
                  error: inspect(reason),
                  completed_at: DateTime.utc_now()
              }
          end

        state = put_in(state, [:jobs, job_id], job)
        {:reply, {:ok, job}, state}
    end
  end

  @impl true
  def handle_call({:status, job_id}, _from, state) do
    job = get_in(state, [:jobs, job_id])
    {:reply, job, state}
  end

  @impl true
  def handle_call({:list_jobs, user_id}, _from, state) do
    jobs =
      state.jobs
      |> Map.values()
      |> Enum.filter(&(&1.user_id == user_id))
      |> Enum.sort_by(& &1.started_at, {:desc, DateTime})

    {:reply, jobs, state}
  end

  @impl true
  def handle_call({:cancel, job_id}, _from, state) do
    case get_in(state, [:jobs, job_id]) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{status: :running} = job ->
        job = %{job | status: :cancelled, completed_at: DateTime.utc_now()}
        state = put_in(state, [:jobs, job_id], job)
        {:reply, :ok, state}

      _ ->
        {:reply, {:error, :not_running}, state}
    end
  end

  # ============================================
  # Private Functions
  # ============================================

  defp normalize_agents(agents) do
    Enum.map(agents, fn agent ->
      %{
        id: Ecto.UUID.generate(),
        role: agent[:role] || :custom,
        prompt: agent[:prompt],
        persona: agent[:persona] || default_persona(agent[:role]),
        status: :pending,
        result: nil,
        tokens: 0,
        duration_ms: 0
      }
    end)
  end

  defp default_persona(:researcher),
    do: "You are a thorough researcher who finds accurate, well-sourced information."

  defp default_persona(:analyst),
    do: "You are an analytical thinker who identifies patterns and insights."

  defp default_persona(:critic),
    do: "You are a constructive critic who identifies weaknesses and suggests improvements."

  defp default_persona(:coder),
    do: "You are an expert programmer who writes clean, efficient code."

  defp default_persona(:writer),
    do: "You are a skilled writer who communicates clearly and engagingly."

  defp default_persona(_), do: "You are a helpful assistant."

  defp execute_parallel(job) do
    # Spawn tasks for each agent
    tasks =
      Enum.map(job.agents, fn agent ->
        Task.async(fn ->
          execute_agent(job, agent)
        end)
      end)

    # Wait for all with timeout
    results =
      Task.yield_many(tasks, (job.timeout_ms || 60_000) + 10_000)
      |> Enum.zip(job.agents)
      |> Enum.map(fn {{task, result}, agent} ->
        case result do
          {:ok, agent_result} ->
            agent_result

          {:exit, reason} ->
            %{agent | status: :failed, result: "Failed: #{inspect(reason)}"}

          nil ->
            Task.shutdown(task, :brutal_kill)
            %{agent | status: :timeout, result: "Timed out"}
        end
      end)

    # Check if any failed critically
    failures = Enum.count(results, &(&1.status in [:failed, :timeout]))

    if failures == length(results) do
      {:error, :all_agents_failed}
    else
      total_tokens = Enum.reduce(results, 0, &(&1.tokens + &2))
      results_map = Map.new(results, &{&1.id, &1})
      {:ok, results_map, total_tokens}
    end
  end

  defp execute_agent(job, agent) do
    Logger.info("Executing agent #{agent.role}: #{String.slice(agent.prompt, 0, 50)}...")

    # Register agent
    agent_id = "sub_#{agent.id}"
    AgentRegistry.join(agent_id, %{role: agent.role, job_id: job.id, status: "running"})

    start_time = System.monotonic_time(:millisecond)

    # Build prompt with persona and context
    prompt = build_agent_prompt(job, agent)

    turn_id = "multi-agent:#{job.id}:#{agent.id}"
    channel_id = "multi_agent:#{job.id}"

    result =
      case Brain.prompt(prompt,
             user_id: job.user_id,
             hal_session_id: turn_id,
             channel_type: "terminal",
             channel_id: channel_id,
             timeout: job.timeout_ms || 60_000
           ) do
        {:ok, response} ->
          %{
            agent
            | status: :completed,
              result: response,
              tokens: estimate_tokens(prompt, response)
          }

        {:error, reason} ->
          %{agent | status: :failed, result: "Error: #{inspect(reason)}"}
      end

    duration = System.monotonic_time(:millisecond) - start_time
    result = %{result | duration_ms: duration}

    # Unregister agent
    AgentRegistry.leave(agent_id)

    Logger.info("Agent #{agent.role} completed in #{duration}ms")
    result
  end

  defp build_agent_prompt(job, agent) do
    """
    #{agent.persona}

    ## Task Context
    Overall task: #{job.task}

    ## Your Specific Assignment
    #{agent.prompt}

    ## Instructions
    - Focus only on your specific assignment
    - Be thorough but concise
    - Your output will be combined with other agents' work
    - Provide clear, actionable information
    """
  end

  defp aggregate_results(job, results) do
    completed_results =
      results
      |> Map.values()
      |> Enum.filter(&(&1.status == :completed))
      |> Enum.map(&{&1.role, &1.result})

    case job.aggregation do
      :synthesis -> synthesize_results(job, completed_results)
      :list -> list_results(completed_results)
      :vote -> vote_results(completed_results)
      :best -> best_result(completed_results)
      _ -> list_results(completed_results)
    end
  end

  defp synthesize_results(job, results) do
    results_text =
      Enum.map(results, fn {role, result} ->
        "## #{role}\n#{result}"
      end)
      |> Enum.join("\n\n")

    prompt = """
    Synthesize the following perspectives into a coherent response.

    Original task: #{job.task}

    Agent outputs:
    #{results_text}

    Provide a unified synthesis that:
    - Combines key insights from all perspectives
    - Resolves any contradictions
    - Presents a clear, actionable conclusion
    """

    turn_id = "multi-agent:#{job.id}:synthesis"
    channel_id = "multi_agent:#{job.id}"

    case Brain.prompt(prompt,
           user_id: job.user_id,
           hal_session_id: turn_id,
           channel_type: "terminal",
           channel_id: channel_id,
           timeout: job.timeout_ms || 60_000
         ) do
      {:ok, response} -> response
      {:error, _} -> "Synthesis failed. Individual results:\n\n#{results_text}"
    end
  end

  defp list_results(results) do
    Enum.map(results, fn {role, result} ->
      "## #{role}\n#{result}"
    end)
    |> Enum.join("\n\n---\n\n")
  end

  defp vote_results(results) do
    # Simple majority vote - find most common conclusion
    # This is a simplified implementation
    list_results(results)
  end

  defp best_result(results) do
    # Return the longest/most detailed result
    results
    |> Enum.max_by(fn {_role, result} -> String.length(result || "") end, fn -> {nil, ""} end)
    |> elem(1)
  end

  defp estimate_tokens(prompt, response) do
    # Rough estimate: 1 token ≈ 4 characters
    div(String.length(prompt) + String.length(response || ""), 4)
  end
end
