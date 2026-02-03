defmodule HAL.Heartbeat do
  @moduledoc """
  Autonomous work heartbeat (Moltbot pattern) with enhanced autonomy.

  Combines the Moltbot HEARTBEAT.md pattern with HAL's autonomy system:
  - **Time Awareness** - Respects quiet hours and user context
  - **State Tracking** - Prevents redundant checks via rotation
  - **Soul Loading** - Provides identity context for decisions

  ## How It Works

  1. Check if appropriate to work (TimeAwareness)
  2. Get next due task (HeartbeatState rotation)
  3. Load identity context (SoulLoader)
  4. Send to Claude with full context
  5. Record check completion (HeartbeatState)

  ## HEARTBEAT.md Format

  ```markdown
  # HEARTBEAT.md

  - [ ] Check email inbox (urgent only)
  - [ ] Check calendar (next 24h)
  - [ ] Review memory/YYYY-MM-DD.md from today
  ```

  Empty HEARTBEAT.md = skip heartbeat (save tokens).

  ## Tracking

  Last check times stored in workspace/heartbeat-state.json:
  ```json
  {
    "lastChecks": {
      "email": 1703275200,
      "calendar": 1703260800
    }
  }
  ```
  """

  require Logger

  alias HAL.Autonomy
  alias HAL.Autonomy.{Brain, TimeAwareness, HeartbeatState}
  alias HAL.Goals.Manager, as: GoalManager
  @workspace_dir Application.compile_env(:hal, :workspace_dir, "workspace")

  @doc """
  Check for autonomous work using the full autonomy system.

  Returns:
  - :ok if work was done or HEARTBEAT_OK received
  - :skip if not appropriate to work or nothing to do
  - :error if heartbeat failed
  """
  def check_for_work do
    # Use the new autonomy system for decision making
    case Autonomy.should_work?() do
      {:no, reason} ->
        Logger.debug("Heartbeat: Skipping - #{reason}")
        :skip

      {:yes, _} ->
        do_heartbeat_check()
    end
  end

  defp do_heartbeat_check do
    heartbeat_content = read_heartbeat_file()

    cond do
      # Empty HEARTBEAT.md - use rotation-based checks
      heartbeat_content == "" or is_empty_checklist?(heartbeat_content) ->
        Logger.debug("HEARTBEAT.md empty, checking for due rotation tasks")
        run_rotation_based_heartbeat()

      # Has HEARTBEAT.md content - use that
      true ->
        run_heartbeat(heartbeat_content)
    end
  end

  @doc """
  Run heartbeat using rotation-based task selection.

  When HEARTBEAT.md is empty, uses HeartbeatState to determine
  what check is due based on configured intervals.
  """
  def run_rotation_based_heartbeat do
    case HeartbeatState.get_next_due_check() do
      nil ->
        Logger.debug("Heartbeat: No checks due")
        :skip

      {check_type, hours_since} ->
        Logger.info(
          "Heartbeat: Running due check - #{check_type} (#{Float.round(hours_since, 1)}h since last)"
        )

        run_specific_check(check_type)
    end
  end

  defp run_specific_check(:goals) do
    # Special handling for user-created goals
    run_goals_check()
  end

  defp run_specific_check(check_type) do
    session_id = "heartbeat-#{check_type}-#{DateTime.utc_now() |> DateTime.to_unix()}"

    message = build_check_prompt(check_type)

    case Brain.prompt(message, session_id: session_id, timeout: 120_000, channel_type: "telegram") do
      {:ok, response} ->
        HeartbeatState.record_check(check_type, %{result: "completed"})
        handle_heartbeat_response(response)
        :ok

      {:error, {:budget_exceeded, _remaining}} ->
        Logger.info("Heartbeat: Budget exceeded, skipping #{check_type} check")
        HeartbeatState.record_check(check_type, %{result: "budget_exceeded"})
        :skip

      {:error, reason} ->
        Logger.warning("Heartbeat check #{check_type} failed: #{inspect(reason)}")
        :error
    end
  end

  # Goal Processing
  # ================

  defp run_goals_check do
    user = Hal.Accounts.DefaultUser.get()

    if is_nil(user) do
      Logger.debug("Heartbeat: No default user configured")
      HeartbeatState.record_check(:goals, %{result: "no_user"})
      :skip
    else
      {:ok, goals} = GoalManager.get_active_goals(user.id)

      case goals do
        [] ->
          Logger.debug("Heartbeat: No active goals")
          HeartbeatState.record_check(:goals, %{result: "no_goals"})
          :skip

        goals ->
          # Pick highest priority actionable goal
          goal =
            goals
            |> Enum.filter(&HAL.Goals.Goal.actionable?/1)
            |> Enum.sort_by(& &1.priority, :desc)
            |> List.first()

          if goal do
            work_on_goal(goal, user_id: user.id)
          else
            Logger.debug("Heartbeat: No actionable goals")
            HeartbeatState.record_check(:goals, %{result: "none_actionable"})
            :skip
          end
      end
    end
  end

  defp work_on_goal(goal, opts) do
    Logger.info("Heartbeat: Working on goal - #{goal.title}")
    session_id = "goal-#{goal.id}-#{DateTime.utc_now() |> DateTime.to_unix()}"

    user_id = Keyword.fetch!(opts, :user_id)
    message = build_goal_prompt(goal)

    case Brain.prompt(message,
           session_id: session_id,
           timeout: 300_000,
           user_id: user_id,
           channel_type: "telegram"
         ) do
      {:ok, response} ->
        HeartbeatState.record_check(:goals, %{
          result: "worked",
          goal_id: goal.id,
          goal_title: goal.title
        })

        handle_goal_response(goal, response)
        :ok

      {:error, {:budget_exceeded, _remaining}} ->
        Logger.info("Heartbeat: Budget exceeded, skipping goal work")
        HeartbeatState.record_check(:goals, %{result: "budget_exceeded", goal_id: goal.id})
        :skip

      {:error, reason} ->
        Logger.warning("Heartbeat: Goal work failed - #{inspect(reason)}")
        :error
    end
  end

  defp build_goal_prompt(goal) do
    """
    # Autonomous Goal Work

    You are working on a goal you previously committed to.

    ## Goal Details

    **Title:** #{goal.title}
    **Description:** #{goal.description || "No description"}
    **Type:** #{goal.type}
    **Priority:** #{goal.priority}/100
    **Current Progress:** #{round((goal.progress || 0) * 100)}%

    #{if goal.success_criteria && length(goal.success_criteria) > 0 do
      "**Success Criteria:**\n#{Enum.map(goal.success_criteria, &"- #{&1}") |> Enum.join("\n")}"
    else
      ""
    end}

    ## Instructions

    1. Make meaningful progress on this goal
    2. Use your tools as needed (research, memory, etc.)
    3. Log your work to memory/#{Date.utc_today()}.md
    4. When done, call `hal_self_update_goal` to update progress
    5. Be honest about what you accomplished

    ## Boundaries

    - You can: research, read files, search web, use browser, update memory
    - Ask first: send emails, post publicly, make purchases
    - Time budget: ~5 minutes of work

    What progress did you make?
    """
  end

  defp handle_goal_response(goal, response) when is_binary(response) do
    Logger.info("Heartbeat: Goal '#{goal.title}' work completed")
    Logger.debug("Goal response: #{String.slice(response, 0, 200)}...")
  end

  defp handle_goal_response(goal, %{result: result}) when is_binary(result) do
    handle_goal_response(goal, result)
  end

  defp handle_goal_response(_goal, _response), do: :ok

  defp build_check_prompt(check_type) do
    """
    # Heartbeat Check: #{check_type}

    You are performing a scheduled #{check_type} check as part of your autonomous operation.

    ## Instructions

    1. Check #{check_type} for anything requiring attention
    2. If something needs action, take it (within your autonomous boundaries)
    3. Log any findings to memory/#{Date.utc_today()}.md
    4. If nothing needs attention, reply exactly: "HEARTBEAT_OK"

    ## Current Context

    - Time: #{DateTime.utc_now() |> Calendar.strftime("%H:%M %Z")}
    - Period: #{TimeAwareness.get_current_period().period}
    - Can reach out: #{TimeAwareness.appropriate_to_reach_out?(:normal)}

    ## Boundaries

    You can freely: read files, search web, check status, log to memory
    Ask first: send emails, post publicly, modify user code

    What did you find?
    """
  end

  defp run_heartbeat(heartbeat_content) do
    Logger.info("Heartbeat: Checking for autonomous work using HEARTBEAT.md")

    session_id = "heartbeat-#{DateTime.utc_now() |> DateTime.to_unix()}"

    time_context = TimeAwareness.get_current_period()

    message = build_heartbeat_prompt(heartbeat_content, time_context)

    case Brain.prompt(message, session_id: session_id, timeout: 120_000, channel_type: "telegram") do
      {:ok, response} ->
        # Record that we ran a general heartbeat
        HeartbeatState.record_check(:heartbeat, %{type: :checklist})
        handle_heartbeat_response(response)
        :ok

      {:error, {:budget_exceeded, _remaining}} ->
        Logger.info("Heartbeat: Budget exceeded, skipping checklist heartbeat")
        HeartbeatState.record_check(:heartbeat, %{type: :checklist, result: "budget_exceeded"})
        :skip

      {:error, reason} ->
        Logger.warning("Heartbeat failed: #{inspect(reason)}")
        :error
    end
  end

  defp build_heartbeat_prompt(heartbeat_content, time_context) do
    """
    # Heartbeat Poll

    Read the checklist below and follow it strictly. Do not infer or repeat tasks from prior chats.

    ## HEARTBEAT CHECKLIST
    #{heartbeat_content}

    ## Current Context

    - Time: #{DateTime.utc_now() |> Calendar.strftime("%H:%M %Z")}
    - Period: #{time_context.period}
    - Day: #{if time_context.is_weekend, do: "Weekend", else: "Weekday"}
    - Can reach out: #{time_context.can_reach_out}

    ## Guidelines

    - Check each item in the checklist
    - Track what you've checked in heartbeat-state.json
    - Only work on things that need attention
    - If nothing needs attention, reply exactly: "HEARTBEAT_OK"
    - Work silently (don't interrupt the user unless important)
    - Respect quiet hours (#{time_context.period == :quiet_hours})

    ## Workspace Files

    - Daily log: memory/#{Date.utc_today() |> Date.to_string()}.md
    - Long-term memory: MEMORY.md
    - State tracking: heartbeat-state.json

    What needs attention?
    """
  end

  defp handle_heartbeat_response(%{result: result}) when is_binary(result) do
    if String.trim(result) == "HEARTBEAT_OK" do
      Logger.debug("Heartbeat: Nothing to do")
    else
      Logger.info("Heartbeat: Work completed - #{String.slice(result, 0, 100)}...")
    end
  end

  defp handle_heartbeat_response(response) when is_binary(response) do
    if String.trim(response) == "HEARTBEAT_OK" do
      Logger.debug("Heartbeat: Nothing to do")
    else
      Logger.info("Heartbeat: Work completed - #{String.slice(response, 0, 100)}...")
    end
  end

  defp handle_heartbeat_response(_), do: :ok

  @doc """
  Check if autonomous work can be done.

  Uses the full autonomy system to check:
  - Time of day (quiet hours)
  - User status (busy, focus mode)
  - Active sessions (user chatting)
  - Running heartbeats (prevent overlap)

  Returns false if any condition blocks autonomous work.
  """
  def can_work_autonomously? do
    case Autonomy.should_work?() do
      {:no, _reason} ->
        false

      {:yes, _} ->
        # Also check if another heartbeat is running
        not heartbeat_already_running?()
    end
  end

  defp heartbeat_already_running? do
    try do
      case Registry.lookup(Hal.SessionRegistry, "heartbeat") do
        [] -> false
        _running -> true
      end
    catch
      :exit, _ -> false
    end
  end

  @doc """
  Get current heartbeat status for dashboard.
  """
  def get_status do
    %{
      can_work: can_work_autonomously?(),
      time_status: TimeAwareness.get_current_period(),
      due_checks: HeartbeatState.get_due_checks(),
      heartbeat_state: HeartbeatState.get_state()
    }
  end

  defp read_heartbeat_file do
    heartbeat_path = Path.join(@workspace_dir, "HEARTBEAT.md")

    case File.read(heartbeat_path) do
      {:ok, content} ->
        content

      {:error, :enoent} ->
        ""

      {:error, reason} ->
        Logger.warning("Failed to read HEARTBEAT.md: #{inspect(reason)}")
        ""
    end
  end

  defp is_empty_checklist?(content) do
    # Check if file only contains comments or whitespace
    content
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == "" or String.starts_with?(String.trim(&1), "#")))
    |> Enum.empty?()
  end
end
