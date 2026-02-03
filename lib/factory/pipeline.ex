defmodule Factory.Pipeline do
  @moduledoc """
  Orchestrates the automated startup experiment pipeline.
  
  The pipeline:
  1. Monitors an idea queue (from various sources)
  2. Picks the most promising hypothesis
  3. Runs experiment lifecycle automatically
  4. Reports results to Telegram
  5. Makes scale/pivot/kill decisions
  
  Runs autonomously but respects budget constraints.
  """
  use GenServer
  require Logger

  alias Factory.{Experiment, Wallet, Critic}

  @check_interval_ms 60_000  # Check every minute
  @max_concurrent_experiments 3

  defstruct [
    :idea_queue,
    :active_experiments,
    :completed_experiments,
    :telegram_chat_id
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Add an idea to the queue"
  def queue_idea(idea) when is_map(idea) do
    GenServer.cast(__MODULE__, {:queue_idea, idea})
  end

  @doc "Add multiple ideas"
  def queue_ideas(ideas) when is_list(ideas) do
    Enum.each(ideas, &queue_idea/1)
  end

  @doc "Get pipeline status"
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc "Pause the pipeline"
  def pause do
    GenServer.call(__MODULE__, :pause)
  end

  @doc "Resume the pipeline"
  def resume do
    GenServer.call(__MODULE__, :resume)
  end

  @doc "Manually trigger next experiment"
  def trigger_next do
    GenServer.call(__MODULE__, :trigger_next, 120_000)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      idea_queue: :queue.new(),
      active_experiments: [],
      completed_experiments: [],
      telegram_chat_id: Keyword.get(opts, :telegram_chat_id)
    }
    
    # Start the check loop
    schedule_check()
    
    Logger.info("[Pipeline] Started. Max concurrent: #{@max_concurrent_experiments}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:queue_idea, idea}, state) do
    # Validate idea structure
    idea = normalize_idea(idea)
    new_queue = :queue.in(idea, state.idea_queue)
    
    Logger.info("[Pipeline] Queued idea: #{idea.hypothesis |> String.slice(0, 50)}...")
    {:noreply, %{state | idea_queue: new_queue}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    wallet_status = Wallet.status()
    
    status = %{
      queued_ideas: :queue.len(state.idea_queue),
      active_experiments: length(state.active_experiments),
      completed_experiments: length(state.completed_experiments),
      budget_remaining_cents: wallet_status.daily_remaining_cents,
      next_ideas: :queue.to_list(state.idea_queue) |> Enum.take(5) |> Enum.map(& &1.hypothesis)
    }
    
    {:reply, status, state}
  end

  @impl true
  def handle_call(:trigger_next, _from, state) do
    case maybe_start_experiment(state) do
      {:ok, experiment_id, new_state} ->
        {:reply, {:ok, experiment_id}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:check, state) do
    # Check and advance existing experiments
    state = check_experiments(state)
    
    # Maybe start new experiments
    state = case maybe_start_experiment(state) do
      {:ok, _id, new_state} -> new_state
      {:error, _} -> state
    end
    
    schedule_check()
    {:noreply, state}
  end

  @impl true
  def handle_info({:experiment_complete, experiment_id, result}, state) do
    Logger.info("[Pipeline] Experiment #{experiment_id} complete: #{inspect(result)}")
    
    # Move from active to completed
    new_active = Enum.reject(state.active_experiments, & &1 == experiment_id)
    new_completed = [{experiment_id, result, DateTime.utc_now()} | state.completed_experiments]
    
    # Notify
    notify_result(experiment_id, result, state.telegram_chat_id)
    
    {:noreply, %{state | active_experiments: new_active, completed_experiments: new_completed}}
  end

  # Private functions

  defp schedule_check do
    Process.send_after(self(), :check, @check_interval_ms)
  end

  defp normalize_idea(idea) when is_binary(idea) do
    %{hypothesis: idea, priority: 5}
  end

  defp normalize_idea(idea) when is_map(idea) do
    %{
      hypothesis: idea[:hypothesis] || idea["hypothesis"],
      target_audience: idea[:target_audience] || idea["target_audience"],
      problem: idea[:problem] || idea["problem"],
      solution: idea[:solution] || idea["solution"],
      priority: idea[:priority] || idea["priority"] || 5
    }
  end

  defp maybe_start_experiment(state) do
    cond do
      # At capacity
      length(state.active_experiments) >= @max_concurrent_experiments ->
        {:error, "At max concurrent experiments (#{@max_concurrent_experiments})"}
      
      # No ideas
      :queue.is_empty(state.idea_queue) ->
        {:error, "No ideas in queue"}
      
      # Not enough budget
      Wallet.remaining_today() < 500 ->
        {:error, "Daily budget exhausted"}
      
      true ->
        {{:value, idea}, new_queue} = :queue.out(state.idea_queue)
        
        # Run through Critic first
        case Critic.prescreen(idea.hypothesis) do
          {:reject, reasons} ->
            Logger.warning("[Pipeline] Idea rejected by prescreen: #{inspect(reasons)}")
            # Remove from queue but don't start experiment
            {:error, "Rejected by prescreen: #{Enum.join(reasons, ", ")}"}
          
          :ok ->
            # Full evaluation
            case Critic.evaluate(idea.hypothesis,
                   target_audience: idea.target_audience,
                   problem: idea.problem,
                   solution: idea.solution) do
              {:ok, %{pass: false, score: score, feedback: feedback}} ->
                Logger.warning("[Pipeline] Idea scored #{score}/100 (below threshold). Feedback: #{inspect(feedback)}")
                {:error, "Critic score too low: #{score}/100"}
              
              {:ok, %{pass: true, score: score}} ->
                Logger.info("[Pipeline] Idea passed critic with score #{score}/100")
                
                case Experiment.create(idea.hypothesis,
                       target_audience: idea.target_audience,
                       problem: idea.problem,
                       solution: idea.solution) do
                  {:ok, pid} ->
                    experiment_id = Experiment.get(pid).id
                    Logger.info("[Pipeline] Started experiment: #{experiment_id}")
                    
                    new_state = %{state |
                      idea_queue: new_queue,
                      active_experiments: [experiment_id | state.active_experiments]
                    }
                    
                    {:ok, experiment_id, new_state}
                  
                  {:error, reason} ->
                    {:error, reason}
                end
              
              {:error, reason} ->
                {:error, "Critic evaluation failed: #{reason}"}
            end
        end
    end
  end

  defp check_experiments(state) do
    # Check each active experiment and advance if possible
    Enum.each(state.active_experiments, fn experiment_id ->
      try do
        case Experiment.get(experiment_id) do
          %{stage: stage} = exp when stage in [:ideation, :generation, :deployment] ->
            # Auto-advance through these stages
            case Experiment.advance(experiment_id) do
              {:ok, new_stage} ->
                Logger.info("[Pipeline] #{experiment_id} advanced to #{new_stage}")
              {:error, reason} ->
                Logger.warning("[Pipeline] #{experiment_id} failed to advance: #{reason}")
            end
          
          %{stage: :validation} = exp ->
            # Check if ready for analysis
            if exp.metrics.signups >= 10 do
              Experiment.advance(experiment_id)
            end
          
          %{stage: :analysis} ->
            # Auto-advance to decision
            case Experiment.advance(experiment_id) do
              {:ok, :decision, decision} ->
                send(self(), {:experiment_complete, experiment_id, decision})
              _ -> :ok
            end
          
          _ -> :ok
        end
      rescue
        e ->
          Logger.error("[Pipeline] Error checking #{experiment_id}: #{inspect(e)}")
      end
    end)
    
    state
  end

  defp notify_result(experiment_id, result, chat_id) do
    message = """
    🧪 Experiment Complete: #{experiment_id}
    
    📊 Decision: #{result |> Atom.to_string() |> String.upcase()}
    
    #{decision_emoji(result)} #{decision_message(result)}
    """
    
    # If Telegram is configured, send notification
    if chat_id do
      # HAL.Channels.Telegram.send_message(chat_id, message)
      Logger.info("[Pipeline] Would notify Telegram: #{message}")
    else
      Logger.info(message)
    end
  end

  defp decision_emoji(:scale), do: "🚀"
  defp decision_emoji(:pivot), do: "🔄"
  defp decision_emoji(:kill), do: "💀"
  defp decision_emoji(:continue), do: "⏳"

  defp decision_message(:scale), do: "Strong signal! Time to double down."
  defp decision_message(:pivot), do: "Some traction. Worth exploring variations."
  defp decision_message(:kill), do: "No market fit. Moving on."
  defp decision_message(:continue), do: "Needs more data."
end
