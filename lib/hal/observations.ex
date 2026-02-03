defmodule HAL.Observations do
  @moduledoc """
  Simple observation logging for agent self-improvement.

  Philosophy: Keep it simple. Agent reads observations and decides how to improve.
  No complex analysis code - agent intelligence > hardcoded logic.

  ## Usage

      # Log an observation
      HAL.Observations.log(%{
        type: "delegation_success",
        observation: "Gemini handled bulk file processing 10x faster",
        impact: "Should prefer Gemini for >10 file operations",
        confidence: "high"
      })

      # Read recent observations
      HAL.Observations.read_recent(limit: 10)

      # Read all observations
      HAL.Observations.read_all()
  """

  require Logger

  @claude_dir ".claude"
  @observations_dir "observations"
  @learnings_file "learnings.jsonl"

  @doc """
  Log an observation to learnings.jsonl

  Observations help HAL improve over time. Log when you:
  - Successfully delegate to a cheaper model
  - Learn a user preference
  - Discover a pattern that works well
  - Make a mistake worth remembering
  """
  @spec log(map(), String.t()) :: :ok | {:error, term()}
  def log(observation, working_dir \\ ".") when is_map(observation) do
    learnings_path = Path.join([working_dir, @claude_dir, @observations_dir, @learnings_file])

    # Ensure directory exists
    File.mkdir_p!(Path.dirname(learnings_path))

    # Add timestamp if not present
    entry =
      observation
      |> Map.put_new(:timestamp, DateTime.utc_now() |> DateTime.to_iso8601())
      |> Map.put_new(:type, "observation")

    # Append to JSONL file
    case File.open(learnings_path, [:append, :utf8]) do
      {:ok, file} ->
        IO.puts(file, Jason.encode!(entry))
        File.close(file)
        Logger.debug("Logged observation: #{entry[:type]} - #{entry[:observation]}")
        :ok

      {:error, reason} ->
        Logger.error("Could not log observation: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Read all observations from learnings.jsonl

  Returns list of maps. Agent interprets and decides what to do with them.
  """
  @spec read_all(String.t()) :: [map()]
  def read_all(working_dir \\ ".") do
    learnings_path = Path.join([working_dir, @claude_dir, @observations_dir, @learnings_file])

    case File.read(learnings_path) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(fn line ->
          case Jason.decode(line, keys: :atoms) do
            {:ok, observation} -> observation
            {:error, _} -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      {:error, _} ->
        []
    end
  end

  @doc """
  Read recent N observations

  Simpler than read_all for including in system prompt.
  Returns observations as formatted text for context.
  """
  @spec read_recent(String.t(), keyword()) :: String.t()
  def read_recent(working_dir \\ ".", opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)

    observations =
      read_all(working_dir)
      |> Enum.take(-limit)

    if Enum.empty?(observations) do
      "No observations yet."
    else
      observations
      |> Enum.map(&format_observation/1)
      |> Enum.join("\n")
    end
  end

  @doc """
  Read recent observations as list of maps (for programmatic use)
  """
  @spec read_recent_list(String.t(), integer()) :: [map()]
  def read_recent_list(working_dir \\ ".", limit \\ 10) do
    read_all(working_dir)
    |> Enum.take(-limit)
  end

  @doc """
  Count total observations
  """
  @spec count(String.t()) :: non_neg_integer()
  def count(working_dir \\ ".") do
    read_all(working_dir) |> length()
  end

  @doc """
  Get observations by type
  """
  @spec by_type(String.t(), String.t()) :: [map()]
  def by_type(type, working_dir \\ ".") do
    read_all(working_dir)
    |> Enum.filter(&(&1[:type] == type))
  end

  # Format a single observation for inclusion in prompts
  defp format_observation(obs) do
    timestamp = obs[:timestamp] || "unknown"
    type = obs[:type] || "observation"
    observation = obs[:observation] || ""
    impact = obs[:impact]
    confidence = obs[:confidence]

    parts = ["[#{timestamp}] (#{type}) #{observation}"]

    parts = if impact, do: parts ++ ["  Impact: #{impact}"], else: parts
    parts = if confidence, do: parts ++ ["  Confidence: #{confidence}"], else: parts

    Enum.join(parts, "\n")
  end
end
