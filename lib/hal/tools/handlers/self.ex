defmodule Hal.Tools.Handlers.Self do
  @moduledoc """
  Handlers for HAL's self-modification tools.

  These tools allow HAL to evolve based on user feedback and self-reflection,
  within safety constraints:
  - Personality changes are rate-limited (3/day)
  - All changes are logged for audit
  - Prime directives cannot be modified

  ## Available Tools

  - `update_personality` - Adjust a personality trait
  - `update_preference` - Store a learned preference
  - `set_goal` - Create a new goal
  - `update_goal` - Update goal progress/status
  - `reflect` - Log a learning for self-improvement
  - `get_status` - Get current configuration
  """

  require Logger

  alias Hal.Tools.Executor
  alias HAL.Identity.Personality
  alias HAL.Goals.Manager, as: GoalManager

  @doc """
  Update a personality trait.
  Rate limited to 3 changes per day.
  """
  def update_personality(args, opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    trait = String.to_existing_atom(args["trait"])
    new_value = args["new_value"]
    reason = args["reason"]

    personality = Personality.get_for_user(user_id)
    remaining = Personality.remaining_modifications(personality)

    if remaining == 0 do
      Executor.return_error(
        "Rate limited: You've made 3 personality changes today. Try again tomorrow.",
        %{remaining_today: 0}
      )
    else
      case Personality.update_trait(personality, trait, new_value, reason) do
        {:ok, _updated} ->
          old_value = Map.get(personality, trait)

          Logger.info(
            "Personality updated: #{trait} #{format_pct(old_value)} -> #{format_pct(new_value)}"
          )

          Executor.return_success(
            "Updated #{trait} from #{format_pct(old_value)} to #{format_pct(new_value)}",
            %{
              trait: trait,
              old_value: old_value,
              new_value: new_value,
              reason: reason,
              remaining_modifications_today: remaining - 1
            }
          )

        {:error, :rate_limited} ->
          Executor.return_error("Rate limited: Maximum 3 personality changes per day")

        {:error, changeset} ->
          Executor.return_error("Invalid update", %{errors: format_errors(changeset)})
      end
    end
  rescue
    ArgumentError ->
      Executor.return_error("Invalid trait: #{args["trait"]}")
  end

  @doc """
  Update a learned preference (no rate limiting).
  """
  def update_preference(args, opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    key = args["key"]
    value = args["value"]

    personality = Personality.get_for_user(user_id)

    case Personality.update_preference(personality, key, value) do
      {:ok, _updated} ->
        Logger.info("Preference updated: #{key} = #{value}")
        Executor.return_success("Stored preference: #{key}", %{key: key, value: value})

      {:error, changeset} ->
        Executor.return_error("Failed to store preference", %{errors: format_errors(changeset)})
    end
  end

  @doc """
  Create a new goal.
  """
  def set_goal(args, opts) do
    user_id = Keyword.fetch!(opts, :user_id)

    goal_attrs = %{
      title: args["title"],
      description: args["description"],
      type: String.to_existing_atom(args["type"] || "short_term"),
      success_criteria: args["success_criteria"] || [],
      target_date: parse_datetime(args["target_date"]),
      parent_id: args["parent_id"],
      priority: args["priority"] || 50
    }

    case GoalManager.create_goal(user_id, goal_attrs) do
      {:ok, goal} ->
        Logger.info("Goal created: #{goal.title} (#{goal.type})")

        Executor.return_success(
          "Created goal: #{goal.title}",
          %{
            goal_id: goal.id,
            title: goal.title,
            type: goal.type,
            priority: goal.priority
          }
        )

      {:error, changeset} ->
        Executor.return_error("Failed to create goal", %{errors: format_errors(changeset)})
    end
  rescue
    ArgumentError ->
      Executor.return_error("Invalid goal type: #{args["type"]}")
  end

  @doc """
  Update goal progress or status.
  """
  def update_goal(args, opts) do
    goal_id = args["goal_id"]

    case GoalManager.get_goal(goal_id) do
      nil ->
        Executor.return_error("Goal not found: #{goal_id}")

      goal ->
        do_update_goal(goal, args, opts)
    end
  end

  defp do_update_goal(goal, args, opts) do
    cond do
      # Update progress
      args["progress"] != nil ->
        summary = args["summary"] || "Progress updated"
        session_id = Keyword.get(opts, :session_id)

        case GoalManager.update_progress(goal, args["progress"], summary, session_id: session_id) do
          {:ok, _updated} ->
            Logger.info("Goal progress: #{goal.title} -> #{round(args["progress"] * 100)}%")

            Executor.return_success(
              "Updated progress for '#{goal.title}'",
              %{
                goal_id: goal.id,
                previous_progress: goal.progress,
                new_progress: args["progress"],
                summary: summary
              }
            )

          {:error, reason} ->
            Executor.return_error("Failed to update progress", %{reason: inspect(reason)})
        end

      # Update status
      args["status"] != nil ->
        status = String.to_existing_atom(args["status"])

        result =
          case status do
            :completed -> GoalManager.complete_goal(goal)
            :paused -> GoalManager.pause_goal(goal)
            :abandoned -> GoalManager.abandon_goal(goal, args["summary"] || "")
            :active -> GoalManager.update_goal(goal, %{status: :active})
          end

        case result do
          {:ok, updated} ->
            Logger.info("Goal status: #{goal.title} -> #{status}")

            Executor.return_success(
              "Updated status for '#{goal.title}' to #{status}",
              %{goal_id: goal.id, status: updated.status}
            )

          {:error, reason} ->
            Executor.return_error("Failed to update status", %{reason: inspect(reason)})
        end

      true ->
        Executor.return_error("Nothing to update - provide progress or status")
    end
  rescue
    ArgumentError ->
      Executor.return_error("Invalid status: #{args["status"]}")
  end

  @doc """
  Log a reflection/learning for self-improvement.
  """
  def reflect(args, _opts) do
    observation = %{
      type: args["type"] || "other",
      observation: args["observation"],
      impact: args["impact"],
      confidence: args["confidence"] || "medium"
    }

    case HAL.Observations.log(observation) do
      :ok ->
        Logger.info("Reflection logged: #{args["observation"]}")

        Executor.return_success(
          "Logged reflection",
          %{type: observation.type, observation: observation.observation}
        )

      {:error, reason} ->
        Executor.return_error("Failed to log reflection", %{reason: inspect(reason)})
    end
  end

  @doc """
  Get current self status (personality, goals, observations).
  """
  def get_status(args, opts) do
    user_id = Keyword.fetch!(opts, :user_id)

    include_personality = Map.get(args, "include_personality", true)
    include_goals = Map.get(args, "include_goals", true)
    include_observations = Map.get(args, "include_observations", true)
    observation_limit = Map.get(args, "observation_limit", 5)

    result = %{}

    # Personality
    result =
      if include_personality do
        personality = Personality.get_for_user(user_id)

        Map.put(result, :personality, %{
          assertiveness: personality.assertiveness,
          warmth: personality.warmth,
          verbosity: personality.verbosity,
          proactivity: personality.proactivity,
          risk_tolerance: personality.risk_tolerance,
          humor: personality.humor,
          formality: personality.formality,
          learned_preferences: personality.learned_preferences,
          remaining_modifications_today: Personality.remaining_modifications(personality)
        })
      else
        result
      end

    # Goals
    result =
      if include_goals do
        {:ok, goals} = GoalManager.get_active_goals(user_id)

        goals_summary =
          Enum.map(goals, fn g ->
            %{
              id: g.id,
              title: g.title,
              type: g.type,
              progress: g.progress,
              priority: g.priority
            }
          end)

        Map.put(result, :goals, goals_summary)
      else
        result
      end

    # Observations
    result =
      if include_observations do
        observations = HAL.Observations.read_recent_list(".", observation_limit)
        Map.put(result, :observations, observations)
      else
        result
      end

    Executor.return_success("Current self status", result)
  end

  # Helper functions

  defp format_pct(value), do: "#{round(value * 100)}%"

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp format_errors(other), do: inspect(other)

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
