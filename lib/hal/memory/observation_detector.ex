defmodule HAL.Memory.ObservationDetector do
  @moduledoc """
  Automatic detection and logging of observations from conversations.

  Runs async after each message to detect patterns worth remembering:
  - Explicit statements: "I'll remember that", "Noted", "Good to know"
  - Preferences: "I prefer X", "I never want Y", "I always like Z"
  - Project info: "We're building X", "The stack is Y"
  - Corrections: "Actually, it's X not Y", "That's wrong, it should be"

  ## Usage

      # Process a message for observations (async)
      ObservationDetector.process_async(message, context)

      # Process synchronously (for testing)
      ObservationDetector.detect(message)
  """

  require Logger

  # Pattern categories with regex patterns
  @patterns %{
    explicit_remember: [
      ~r/(?:I'll|I will|going to)\s+remember\s+(?:that|this)/i,
      ~r/\bnoted\b/i,
      ~r/\bgood to know\b/i,
      ~r/\bkeep that in mind\b/i,
      ~r/\bI'll note that\b/i
    ],
    preference: [
      ~r/(?:I|we)\s+(?:prefer|like|love|enjoy|want)\s+(.+?)(?:\.|,|$)/i,
      ~r/(?:I|we)\s+(?:don't like|hate|avoid|never want)\s+(.+?)(?:\.|,|$)/i,
      ~r/(?:I|we)\s+always\s+(.+?)(?:\.|,|$)/i,
      ~r/(?:I|we)\s+never\s+(.+?)(?:\.|,|$)/i,
      ~r/my\s+(?:preferred|favorite)\s+(.+?)\s+is\s+(.+?)(?:\.|,|$)/i
    ],
    project_info: [
      ~r/(?:we're|we are|I'm|I am)\s+(?:building|creating|working on)\s+(.+?)(?:\.|,|$)/i,
      ~r/(?:the|our)\s+(?:stack|tech stack|technology)\s+(?:is|includes)\s+(.+?)(?:\.|,|$)/i,
      ~r/(?:the|this)\s+project\s+(?:is|uses|involves)\s+(.+?)(?:\.|,|$)/i,
      ~r/using\s+(.+?)\s+(?:for|as)\s+(.+?)(?:\.|,|$)/i
    ],
    correction: [
      ~r/(?:actually|no,|wait,)\s+(?:it's|it should be|that's)\s+(.+?)(?:\.|,|$)/i,
      ~r/(?:that's|this is)\s+(?:wrong|incorrect|not right)/i,
      ~r/correction:\s*(.+?)(?:\.|$)/i
    ],
    important_fact: [
      ~r/(?:important|remember|note):\s*(.+?)(?:\.|$)/i,
      ~r/(?:FYI|for your information|heads up)[:,]?\s*(.+?)(?:\.|$)/i,
      ~r/(?:my|our)\s+(?:email|phone|timezone|location)\s+is\s+(.+?)(?:\.|,|$)/i
    ]
  }

  @doc """
  Process a message asynchronously for observation detection.

  Spawns a task to avoid blocking the main conversation flow.
  """
  @spec process_async(String.t(), map()) :: {:ok, reference()}
  def process_async(message, context \\ %{}) do
    task =
      Task.async(fn ->
        detect_and_log(message, context)
      end)

    {:ok, task.ref}
  end

  @doc """
  Detect observations in a message.

  Returns a list of detected observations without logging them.
  """
  @spec detect(String.t()) :: [map()]
  def detect(message) do
    @patterns
    |> Enum.flat_map(fn {category, patterns} ->
      patterns
      |> Enum.flat_map(fn pattern ->
        case Regex.run(pattern, message, capture: :all) do
          nil ->
            []

          [match | captures] ->
            [
              %{
                category: category,
                match: match,
                captures: captures,
                confidence: calculate_confidence(category, match)
              }
            ]
        end
      end)
    end)
    |> Enum.uniq_by(& &1.match)
  end

  @doc """
  Detect and log observations from a message.
  """
  @spec detect_and_log(String.t(), map()) :: :ok
  def detect_and_log(message, context \\ %{}) do
    observations = detect(message)

    Enum.each(observations, fn obs ->
      log_observation(obs, message, context)
    end)

    :ok
  end

  # Private functions

  defp calculate_confidence(category, match) do
    # Base confidence by category
    base =
      case category do
        :explicit_remember -> 0.9
        :correction -> 0.85
        :preference -> 0.75
        :important_fact -> 0.7
        :project_info -> 0.65
      end

    # Adjust based on match length (longer = more specific = higher confidence)
    length_bonus = min(String.length(match) / 200, 0.1)

    min(base + length_bonus, 1.0)
  end

  defp log_observation(obs, original_message, context) do
    observation_map = %{
      type: to_string(obs.category),
      observation: obs.match,
      captures: obs.captures,
      confidence: confidence_label(obs.confidence),
      source: "auto_detection",
      original_message_preview: String.slice(original_message, 0, 100),
      context: context
    }

    case HAL.Observations.log(observation_map) do
      :ok ->
        Logger.debug(
          "Auto-detected observation: #{obs.category} - #{String.slice(obs.match, 0, 50)}"
        )

      {:error, reason} ->
        Logger.warning("Failed to log observation: #{inspect(reason)}")
    end
  end

  defp confidence_label(score) when score >= 0.8, do: "high"
  defp confidence_label(score) when score >= 0.6, do: "medium"
  defp confidence_label(_), do: "low"
end
