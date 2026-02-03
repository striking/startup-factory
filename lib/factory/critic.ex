defmodule Factory.Critic do
  @moduledoc """
  Critic agent that evaluates experiment hypotheses before execution.
  
  Scores ideas on multiple dimensions and provides actionable feedback.
  Runs as a gate before experiments consume budget.
  """
  require Logger

  @passing_threshold 60  # Minimum score to proceed

  @doc """
  Evaluate a hypothesis and return a scored assessment.
  
  Returns {:ok, %{score: int, pass: bool, feedback: map}} or {:error, reason}
  """
  def evaluate(hypothesis, opts \\ []) do
    target_audience = Keyword.get(opts, :target_audience)
    problem = Keyword.get(opts, :problem)
    solution = Keyword.get(opts, :solution)
    
    # Score each dimension
    scores = %{
      realism: score_realism(hypothesis, solution),
      market_size: score_market_size(target_audience),
      pain_severity: score_pain_severity(problem),
      solution_fit: score_solution_fit(problem, solution),
      testability: score_testability(solution),
      ethics: score_ethics(hypothesis, solution)
    }
    
    # Calculate weighted total
    weights = %{
      realism: 25,
      market_size: 15,
      pain_severity: 20,
      solution_fit: 20,
      testability: 10,
      ethics: 10
    }
    
    total_score = Enum.reduce(scores, 0, fn {dim, score}, acc ->
      acc + (score * weights[dim] / 100)
    end) |> round()
    
    feedback = generate_feedback(scores, hypothesis, solution)
    
    result = %{
      score: total_score,
      pass: total_score >= @passing_threshold,
      dimensions: scores,
      feedback: feedback,
      suggestions: generate_suggestions(scores, hypothesis)
    }
    
    Logger.info("[Critic] Evaluated hypothesis: score=#{total_score}, pass=#{result.pass}")
    {:ok, result}
  end

  @doc """
  Quick check for disqualifying factors (blocks experiment immediately).
  """
  def prescreen(hypothesis) do
    checks = [
      {&contains_false_claims?/1, "Contains potentially false claims (fake backing, unverified stats)"},
      {&technically_impossible?/1, "Core value prop is technically unrealistic"},
      {&illegal_or_harmful?/1, "Potentially illegal or harmful"},
      {&already_saturated?/1, "Market is completely saturated with identical solutions"}
    ]
    
    failures = Enum.filter(checks, fn {check_fn, _reason} ->
      check_fn.(hypothesis)
    end)
    
    if Enum.empty?(failures) do
      :ok
    else
      reasons = Enum.map(failures, fn {_, reason} -> reason end)
      {:reject, reasons}
    end
  end

  # Scoring functions (0-100 scale)

  defp score_realism(hypothesis, solution) do
    red_flags = [
      {"instantly", -20},
      {"seconds", -15},
      {"automatically", -10},
      {"no effort", -20},
      {"magic", -25},
      {"ai will", -5},
      {"snap a photo", -15},  # Often oversimplified
      {"just take a picture", -15}
    ]
    
    base_score = 70
    
    text = String.downcase("#{hypothesis} #{solution}")
    
    penalty = Enum.reduce(red_flags, 0, fn {flag, points}, acc ->
      if String.contains?(text, flag), do: acc + points, else: acc
    end)
    
    max(0, min(100, base_score + penalty))
  end

  defp score_market_size(nil), do: 50  # Unknown
  defp score_market_size(audience) do
    # Larger, more defined audiences score higher
    audience_lower = String.downcase(audience)
    
    cond do
      String.contains?(audience_lower, "small business") -> 75
      String.contains?(audience_lower, "enterprise") -> 60
      String.contains?(audience_lower, "consumer") -> 80
      String.contains?(audience_lower, ["tradie", "plumber", "electrician"]) -> 65
      String.contains?(audience_lower, "australia") -> 55  # Geographic limit
      true -> 50
    end
  end

  defp score_pain_severity(nil), do: 50
  defp score_pain_severity(problem) do
    high_pain_indicators = [
      {"waste", 15},
      {"lose money", 20},
      {"hours", 10},
      {"compliance", 15},
      {"fine", 15},
      {"risk", 10},
      {"manual", 10},
      {"tedious", 10},
      {"hate", 15}
    ]
    
    problem_lower = String.downcase(problem)
    
    base = 40
    bonus = Enum.reduce(high_pain_indicators, 0, fn {indicator, points}, acc ->
      if String.contains?(problem_lower, indicator), do: acc + points, else: acc
    end)
    
    min(100, base + bonus)
  end

  defp score_solution_fit(nil, _), do: 50
  defp score_solution_fit(_, nil), do: 50
  defp score_solution_fit(problem, solution) do
    # Check if solution keywords relate to problem keywords
    problem_words = problem |> String.downcase() |> String.split(~r/\W+/) |> MapSet.new()
    solution_words = solution |> String.downcase() |> String.split(~r/\W+/) |> MapSet.new()
    
    overlap = MapSet.intersection(problem_words, solution_words) |> MapSet.size()
    
    cond do
      overlap >= 3 -> 80
      overlap >= 2 -> 70
      overlap >= 1 -> 60
      true -> 40
    end
  end

  defp score_testability(nil), do: 50
  defp score_testability(solution) do
    # Can we test this with a landing page + waitlist?
    solution_lower = String.downcase(solution)
    
    # Easy to test with landing page
    easy_tests = ["app", "tool", "platform", "software", "service", "subscription"]
    
    # Hard to test (needs actual product)
    hard_tests = ["hardware", "physical", "device", "robot", "install"]
    
    cond do
      Enum.any?(hard_tests, &String.contains?(solution_lower, &1)) -> 40
      Enum.any?(easy_tests, &String.contains?(solution_lower, &1)) -> 80
      true -> 60
    end
  end

  defp score_ethics(_hypothesis, solution) do
    # Check for ethical red flags
    red_flags = [
      "fake",
      "trick",
      "mislead",
      "spam",
      "scrape",
      "bypass"
    ]
    
    solution_lower = String.downcase("#{solution}")
    
    if Enum.any?(red_flags, &String.contains?(solution_lower, &1)) do
      30
    else
      85
    end
  end

  # Feedback generation

  defp generate_feedback(scores, hypothesis, solution) do
    feedback = %{}
    
    feedback = if scores.realism < 60 do
      Map.put(feedback, :realism, 
        "The value proposition may be oversimplified. Consider: How does this actually work step-by-step for a real user? What's the realistic workflow?")
    else
      feedback
    end
    
    feedback = if scores.pain_severity < 50 do
      Map.put(feedback, :pain, 
        "The problem doesn't seem severe enough. Would someone pay to solve this? How much time/money does it cost them today?")
    else
      feedback
    end
    
    feedback = if scores.testability < 50 do
      Map.put(feedback, :testability,
        "This may be hard to validate with just a landing page. Consider what minimum proof you could show.")
    else
      feedback
    end
    
    feedback
  end

  defp generate_suggestions(scores, hypothesis) do
    suggestions = []
    
    suggestions = if scores.realism < 60 do
      ["Reframe the value prop around a realistic user workflow" | suggestions]
    else
      suggestions
    end
    
    suggestions = if scores.market_size < 50 do
      ["Consider broadening the target audience or validating niche size" | suggestions]
    else
      suggestions
    end
    
    suggestions = if scores.solution_fit < 60 do
      ["Ensure the solution directly addresses the stated problem" | suggestions]
    else
      suggestions
    end
    
    suggestions
  end

  # Prescreen checks

  defp contains_false_claims?(hypothesis) do
    false_claim_patterns = [
      "backed by",
      "funded by", 
      "invested",
      "as seen on",
      "featured in",
      "100% guaranteed",
      "proven to"
    ]
    
    hypothesis_lower = String.downcase(hypothesis)
    Enum.any?(false_claim_patterns, &String.contains?(hypothesis_lower, &1))
  end

  defp technically_impossible?(hypothesis) do
    # Very basic check - would need AI to properly evaluate
    impossible_patterns = [
      "read minds",
      "predict the future",
      "100% accurate",
      "never fails"
    ]
    
    hypothesis_lower = String.downcase(hypothesis)
    Enum.any?(impossible_patterns, &String.contains?(hypothesis_lower, &1))
  end

  defp illegal_or_harmful?(hypothesis) do
    harmful_patterns = [
      "hack",
      "steal",
      "pirate",
      "illegal",
      "bypass security"
    ]
    
    hypothesis_lower = String.downcase(hypothesis)
    Enum.any?(harmful_patterns, &String.contains?(hypothesis_lower, &1))
  end

  defp already_saturated?(_hypothesis) do
    # Would need market research to properly evaluate
    # For now, assume not saturated
    false
  end
end
