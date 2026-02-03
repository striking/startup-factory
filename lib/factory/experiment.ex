defmodule Factory.Experiment do
  @moduledoc """
  GenServer managing a single experiment lifecycle.
  
  Experiment stages:
  1. :ideation - Problem/solution hypothesis
  2. :generation - Creating landing page with v0
  3. :deployment - Deploying to Vercel
  4. :validation - Collecting signups, testing conversion
  5. :analysis - Evaluating results
  6. :decision - Scale, pivot, or kill
  
  Each experiment runs as its own supervised process.
  """
  use GenServer
  require Logger

  alias Factory.{Wallet, V0Client, Deployer}

  @max_runtime_hours 72  # Kill experiments after 72 hours max
  @min_signups_to_validate 10

  defstruct [
    :id,
    :name,
    :hypothesis,
    :target_audience,
    :problem,
    :solution,
    :stage,
    :landing_page_code,
    :deployment_url,
    :variants,
    :metrics,
    :created_at,
    :updated_at,
    :budget_cents,
    :ad_config
  ]

  # Client API

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(id))
  end

  def via_tuple(id), do: {:via, Registry, {Factory.ExperimentRegistry, id}}

  @doc "Create a new experiment from a hypothesis"
  def create(hypothesis, opts \\ []) do
    id = generate_id()
    budget = Keyword.get(opts, :budget_cents, 2000)  # $20 default
    
    case Wallet.allocate(id, budget) do
      {:ok, ^id} ->
        experiment_opts = [
          id: id,
          hypothesis: hypothesis,
          budget_cents: budget
        ] ++ opts
        
        DynamicSupervisor.start_child(Factory.ExperimentSupervisor, {__MODULE__, experiment_opts})
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Get experiment state"
  def get(id) do
    GenServer.call(via_tuple(id), :get)
  end

  @doc "Advance to next stage"
  def advance(id) do
    GenServer.call(via_tuple(id), :advance, 120_000)  # 2 min timeout for v0
  end

  @doc "Record a signup/conversion"
  def record_signup(id, data \\ %{}) do
    GenServer.cast(via_tuple(id), {:signup, data})
  end

  @doc "Record revenue"
  def record_revenue(id, amount_cents, source) do
    GenServer.call(via_tuple(id), {:revenue, amount_cents, source})
  end

  @doc "Kill the experiment"
  def kill(id, reason \\ "Manual termination") do
    GenServer.call(via_tuple(id), {:kill, reason})
  end

  @doc "List all active experiments"
  def list_all do
    Registry.select(Factory.ExperimentRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    hypothesis = Keyword.fetch!(opts, :hypothesis)
    
    state = %__MODULE__{
      id: id,
      name: Keyword.get(opts, :name, generate_name(hypothesis)),
      hypothesis: hypothesis,
      target_audience: Keyword.get(opts, :target_audience),
      problem: Keyword.get(opts, :problem),
      solution: Keyword.get(opts, :solution),
      stage: :ideation,
      metrics: %{
        signups: 0,
        page_views: 0,
        conversions: 0,
        revenue_cents: 0,
        ad_spend_cents: 0
      },
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      budget_cents: Keyword.get(opts, :budget_cents, 2000),
      variants: []
    }
    
    Logger.info("[Experiment:#{id}] Created: #{state.name}")
    
    # Schedule auto-kill after max runtime
    Process.send_after(self(), :auto_kill, @max_runtime_hours * 60 * 60 * 1000)
    
    {:ok, state}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:advance, _from, %{stage: :ideation} = state) do
    Logger.info("[Experiment:#{state.id}] Advancing to generation...")
    
    # Generate landing page with v0
    prompt = build_v0_prompt(state)
    
    case V0Client.generate(prompt) do
      {:ok, %{code: code}} ->
        # Track spend
        Wallet.spend(state.id, 50, "v0 generation")  # Approximate cost
        
        new_state = %{state |
          stage: :generation,
          landing_page_code: code,
          updated_at: DateTime.utc_now()
        }
        
        {:reply, {:ok, :generation}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:advance, _from, %{stage: :generation} = state) do
    Logger.info("[Experiment:#{state.id}] Advancing to deployment...")
    
    case Deployer.deploy(state.id, state.landing_page_code, state.name) do
      {:ok, url} ->
        Wallet.spend(state.id, 0, "Vercel deployment (free tier)")
        
        new_state = %{state |
          stage: :deployment,
          deployment_url: url,
          updated_at: DateTime.utc_now()
        }
        
        {:reply, {:ok, :deployment}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:advance, _from, %{stage: :deployment} = state) do
    Logger.info("[Experiment:#{state.id}] Advancing to validation...")
    
    # Start validation phase - ads would be configured here
    new_state = %{state |
      stage: :validation,
      updated_at: DateTime.utc_now()
    }
    
    {:reply, {:ok, :validation}, new_state}
  end

  @impl true
  def handle_call(:advance, _from, %{stage: :validation} = state) do
    # Check if we have enough data
    if state.metrics.signups >= @min_signups_to_validate do
      Logger.info("[Experiment:#{state.id}] Advancing to analysis...")
      
      analysis = analyze_results(state)
      
      new_state = %{state |
        stage: :analysis,
        updated_at: DateTime.utc_now()
      }
      
      {:reply, {:ok, :analysis, analysis}, new_state}
    else
      {:reply, {:error, "Need at least #{@min_signups_to_validate} signups (have #{state.metrics.signups})"}, state}
    end
  end

  @impl true
  def handle_call(:advance, _from, %{stage: :analysis} = state) do
    analysis = analyze_results(state)
    
    decision = make_decision(analysis)
    Logger.info("[Experiment:#{state.id}] Decision: #{decision}")
    
    new_state = %{state |
      stage: :decision,
      updated_at: DateTime.utc_now()
    }
    
    {:reply, {:ok, :decision, decision}, new_state}
  end

  @impl true
  def handle_call(:advance, _from, %{stage: :decision} = state) do
    {:reply, {:error, "Experiment complete. Start a new one."}, state}
  end

  @impl true
  def handle_call({:revenue, amount_cents, source}, _from, state) do
    Wallet.revenue(state.id, amount_cents, source)
    
    new_metrics = %{state.metrics | revenue_cents: state.metrics.revenue_cents + amount_cents}
    new_state = %{state | metrics: new_metrics, updated_at: DateTime.utc_now()}
    
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:kill, reason}, _from, state) do
    Logger.info("[Experiment:#{state.id}] Killed: #{reason}")
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_cast({:signup, data}, state) do
    new_metrics = %{state.metrics |
      signups: state.metrics.signups + 1,
      conversions: state.metrics.conversions + 1
    }
    
    Logger.info("[Experiment:#{state.id}] New signup! Total: #{new_metrics.signups}")
    
    new_state = %{state | metrics: new_metrics, updated_at: DateTime.utc_now()}
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:auto_kill, state) do
    Logger.warning("[Experiment:#{state.id}] Auto-killed after #{@max_runtime_hours}h")
    {:stop, :normal, state}
  end

  # Private functions

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp generate_name(hypothesis) do
    # Extract key words for a short name
    words = String.split(hypothesis)
    |> Enum.reject(&String.match?(&1, ~r/^(a|an|the|for|to|of|and|or|with)$/i))
    |> Enum.take(3)
    |> Enum.join("-")
    |> String.downcase()
    
    "#{words}-#{:rand.uniform(999)}"
  end

  defp build_v0_prompt(state) do
    """
    Create a landing page for:
    
    Target: #{state.target_audience || "Small business owners"}
    Problem: #{state.problem || extract_problem(state.hypothesis)}
    Solution: #{state.solution || extract_solution(state.hypothesis)}
    
    Requirements:
    - Hero section with compelling headline
    - 3-4 key benefits with icons
    - Social proof section (testimonials or stats)
    - Simple pricing (or "Join waitlist" if no price)
    - Email capture form (primary CTA)
    - FAQ section (3-4 questions)
    - Footer with minimal links
    
    Style: Modern, clean, professional. Use blues and whites.
    Make it convert.
    """
  end

  defp extract_problem(hypothesis) do
    # Simple extraction - can be enhanced with AI
    if String.contains?(hypothesis, "struggle") or String.contains?(hypothesis, "problem") do
      hypothesis
    else
      "Inefficiency in their workflow"
    end
  end

  defp extract_solution(hypothesis) do
    if String.contains?(hypothesis, "tool") or String.contains?(hypothesis, "app") do
      hypothesis
    else
      "An automated solution"
    end
  end

  defp analyze_results(state) do
    metrics = state.metrics
    runtime_hours = DateTime.diff(DateTime.utc_now(), state.created_at, :hour)
    
    cac = if metrics.signups > 0 do
      Float.round(metrics.ad_spend_cents / metrics.signups / 100, 2)
    else
      nil
    end
    
    conversion_rate = if metrics.page_views > 0 do
      Float.round(metrics.conversions / metrics.page_views * 100, 2)
    else
      0
    end
    
    %{
      signups: metrics.signups,
      page_views: metrics.page_views,
      conversion_rate: conversion_rate,
      cac_dollars: cac,
      revenue_cents: metrics.revenue_cents,
      ad_spend_cents: metrics.ad_spend_cents,
      roi_percent: if(metrics.ad_spend_cents > 0, 
        do: Float.round((metrics.revenue_cents - metrics.ad_spend_cents) / metrics.ad_spend_cents * 100, 1),
        else: nil),
      runtime_hours: runtime_hours
    }
  end

  defp make_decision(analysis) do
    cond do
      # Great conversion, positive ROI → Scale
      analysis.conversion_rate > 5 and (analysis.roi_percent || 0) > 0 ->
        :scale
      
      # Some traction but not profitable → Pivot
      analysis.signups > 5 and analysis.conversion_rate > 1 ->
        :pivot
      
      # No traction → Kill
      analysis.signups < 3 or analysis.conversion_rate < 0.5 ->
        :kill
      
      # Inconclusive → Need more data
      true ->
        :continue
    end
  end
end
