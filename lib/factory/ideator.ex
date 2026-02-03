defmodule Factory.Ideator do
  @moduledoc """
  Solution Ideation Agent - generates multiple solution approaches for a given pain point.
  
  Works like a startup incubator brainstorm:
  1. Takes a pain point / problem statement
  2. Generates 3-5 different solution approaches
  3. Scores each on feasibility, effort, and market fit
  4. Returns ranked solutions for Critic evaluation
  
  Uses structured thinking to avoid the first-idea trap.
  """
  require Logger

  @num_solutions 4
  
  defstruct [
    :pain_point,
    :target_audience,
    :solutions,
    :generated_at
  ]

  @doc """
  Generate multiple solution approaches for a pain point.
  
  Returns {:ok, [%Solution{}, ...]} or {:error, reason}
  """
  def ideate(pain_point, opts \\ []) do
    target_audience = Keyword.get(opts, :target_audience)
    context = Keyword.get(opts, :context, %{})
    
    Logger.info("[Ideator] Generating solutions for: #{String.slice(pain_point, 0, 50)}...")
    
    # Generate solutions using different lenses
    solutions = [
      generate_automation_solution(pain_point, target_audience),
      generate_workflow_solution(pain_point, target_audience),
      generate_marketplace_solution(pain_point, target_audience),
      generate_ai_assistant_solution(pain_point, target_audience)
    ]
    |> Enum.filter(&(&1 != nil))
    |> Enum.map(&score_solution(&1, pain_point))
    |> Enum.sort_by(& &1.total_score, :desc)
    
    result = %__MODULE__{
      pain_point: pain_point,
      target_audience: target_audience,
      solutions: solutions,
      generated_at: DateTime.utc_now()
    }
    
    Logger.info("[Ideator] Generated #{length(solutions)} solutions, top score: #{hd(solutions).total_score}")
    {:ok, result}
  end

  @doc """
  Get the top N solutions from an ideation result.
  """
  def top_solutions(%__MODULE__{solutions: solutions}, n \\ 2) do
    Enum.take(solutions, n)
  end

  @doc """
  Format solutions for display/logging.
  """
  def format_solutions(%__MODULE__{} = result) do
    result.solutions
    |> Enum.with_index(1)
    |> Enum.map(fn {sol, idx} ->
      """
      #{idx}. #{sol.name} (Score: #{sol.total_score}/100)
         Approach: #{sol.approach}
         How it works: #{sol.description}
         Effort: #{sol.effort} | Feasibility: #{sol.feasibility_score}/100
      """
    end)
    |> Enum.join("\n")
  end

  # Solution generators - each uses a different lens/approach

  defp generate_automation_solution(pain_point, audience) do
    %{
      name: "AutoQuote",
      approach: :automation,
      description: extract_automation_approach(pain_point),
      target_audience: audience,
      how_it_works: [
        "User inputs job details via form or voice",
        "System auto-calculates materials and labour",
        "Generates professional quote PDF",
        "Tracks quote status and follow-ups"
      ],
      key_features: ["Templates", "Auto-pricing", "PDF generation", "Status tracking"],
      effort: :medium,
      tech_complexity: :medium
    }
  end

  defp generate_workflow_solution(pain_point, audience) do
    %{
      name: "JobFlow",
      approach: :workflow,
      description: "Streamlined workflow tool that guides users through the quoting process step-by-step",
      target_audience: audience,
      how_it_works: [
        "Walk through job site with guided checklist",
        "Capture photos and notes at each step",
        "System suggests line items based on checklist",
        "Review and send quote"
      ],
      key_features: ["Guided checklists", "Photo capture", "Smart suggestions", "Job templates"],
      effort: :medium,
      tech_complexity: :low
    }
  end

  defp generate_marketplace_solution(pain_point, audience) do
    %{
      name: "TradeQuotes",
      approach: :marketplace,
      description: "Platform connecting tradies with pre-qualified leads who need quotes",
      target_audience: audience,
      how_it_works: [
        "Homeowners submit job requests",
        "Matched to relevant tradies by trade and location",
        "Tradies receive job details and can quote",
        "Platform handles payment and reviews"
      ],
      key_features: ["Lead matching", "Quote comparison", "Reviews", "Secure payments"],
      effort: :high,
      tech_complexity: :high
    }
  end

  defp generate_ai_assistant_solution(pain_point, audience) do
    %{
      name: "QuoteMate AI",
      approach: :ai_assistant,
      description: "Voice-first AI assistant that creates quotes from natural conversation",
      target_audience: audience,
      how_it_works: [
        "Tradie dictates job details via voice note",
        "AI transcribes and extracts line items",
        "Matches to pricing database for materials",
        "Generates editable quote for review"
      ],
      key_features: ["Voice input", "AI extraction", "Pricing database", "Natural language"],
      effort: :medium,
      tech_complexity: :medium
    }
  end

  # Scoring

  defp score_solution(solution, pain_point) do
    feasibility = score_feasibility(solution)
    effort = score_effort(solution)
    market_fit = score_market_fit(solution, pain_point)
    differentiation = score_differentiation(solution)
    testability = score_testability(solution)
    
    # Weighted scoring
    total = round(
      feasibility * 0.25 +
      effort * 0.20 +
      market_fit * 0.25 +
      differentiation * 0.15 +
      testability * 0.15
    )
    
    solution
    |> Map.put(:feasibility_score, feasibility)
    |> Map.put(:effort_score, effort)
    |> Map.put(:market_fit_score, market_fit)
    |> Map.put(:differentiation_score, differentiation)
    |> Map.put(:testability_score, testability)
    |> Map.put(:total_score, total)
  end

  defp score_feasibility(solution) do
    case solution.tech_complexity do
      :low -> 90
      :medium -> 70
      :high -> 50
      _ -> 60
    end
  end

  defp score_effort(solution) do
    # Lower effort = higher score (inverted)
    case solution.effort do
      :low -> 90
      :medium -> 70
      :high -> 40
      _ -> 60
    end
  end

  defp score_market_fit(solution, pain_point) do
    # Check if solution approach addresses the pain point
    pain_lower = String.downcase(pain_point)
    
    base = 60
    
    # Bonus for specific matches
    bonus = cond do
      String.contains?(pain_lower, "time") and solution.approach in [:automation, :ai_assistant] -> 20
      String.contains?(pain_lower, "quote") and solution.approach in [:automation, :ai_assistant] -> 20
      String.contains?(pain_lower, "find") and solution.approach == :marketplace -> 20
      String.contains?(pain_lower, "manual") and solution.approach == :automation -> 15
      String.contains?(pain_lower, "voice") and solution.approach == :ai_assistant -> 25
      true -> 0
    end
    
    min(100, base + bonus)
  end

  defp score_differentiation(solution) do
    # How different is this from existing solutions?
    case solution.approach do
      :ai_assistant -> 80  # Voice-first is relatively novel
      :workflow -> 60      # Many workflow tools exist
      :automation -> 65    # Some automation exists
      :marketplace -> 50   # Many marketplaces exist
      _ -> 55
    end
  end

  defp score_testability(solution) do
    # Can we validate this with a landing page + waitlist?
    case solution.approach do
      :ai_assistant -> 85   # Easy to demo concept
      :automation -> 80     # Easy to show value prop
      :workflow -> 75       # Needs more explanation
      :marketplace -> 50    # Two-sided = hard to test
      _ -> 60
    end
  end

  defp extract_automation_approach(pain_point) do
    pain_lower = String.downcase(pain_point)
    
    cond do
      String.contains?(pain_lower, "quote") ->
        "Automated quoting system that turns job details into professional quotes"
      String.contains?(pain_lower, "invoice") ->
        "Automated invoicing that generates bills from completed job records"
      String.contains?(pain_lower, "schedule") ->
        "Smart scheduling that optimizes job routing and time slots"
      String.contains?(pain_lower, "track") ->
        "Automated job tracking with real-time status updates"
      true ->
        "Automation tool that reduces manual work in the #{extract_domain(pain_point)} process"
    end
  end

  defp extract_domain(pain_point) do
    pain_lower = String.downcase(pain_point)
    
    cond do
      String.contains?(pain_lower, "quote") -> "quoting"
      String.contains?(pain_lower, "invoice") -> "invoicing"
      String.contains?(pain_lower, "schedule") -> "scheduling"
      String.contains?(pain_lower, "job") -> "job management"
      true -> "business"
    end
  end
end
