defmodule HAL.AutonomousAgent do
  @moduledoc """
  Autonomous agent that uses event log history to make intelligent decisions.

  This module combines event sourcing with the new autonomy system:
  - **Event Sourcing** - Learn from past actions via event log
  - **Time Awareness** - Respect quiet hours and user context
  - **Heartbeat State** - Rotation-based task selection
  - **Soul Loading** - Consistent identity across sessions
  - **Authorization** - Clear boundaries on autonomous actions

  ## Workflow

  1. **Check Autonomy** - Should we work? (TimeAwareness)
  2. **Load Context** - Get state from ETS + identity from SoulLoader
  3. **Analyze History** - What was I doing? What failed? What did I learn?
  4. **Decide Action** - Use rotation + priorities to select task
  5. **Execute & Log** - Perform action, log outcome to event log
  6. **Learn** - Extract lessons from outcome, log to event log

  ## Usage

      # Heartbeat calls this periodically
      AutonomousAgent.work_cycle()

      # Or manually trigger
      AutonomousAgent.decide_next_action()
      AutonomousAgent.resume_interrupted_work()

      # Use the main Autonomy module for most operations
      HAL.Autonomy.work_cycle()
  """

  require Logger

  alias HAL.AgentState
  alias HAL.EventLog
  alias HAL.Autonomy
  alias HAL.Autonomy.{TimeAwareness, HeartbeatState, SoulLoader}

  # Check instructions for heartbeat checks - module attribute for DRY lookup
  @check_instructions %{
    email: """
    **Email Check:**
    - Check for urgent unread emails (just scan subjects/headers)
    - Don't open or read full emails unless urgent
    - Look for: important sender, urgent keywords, time-sensitive content
    - Report only if something needs Chris's attention
    """,
    calendar: """
    **Calendar Check:**
    - Check for events in the next 24-48 hours
    - Look for: meetings, deadlines, reminders
    - Note any conflicts or preparation needed
    - Report if there's something Chris should know about
    """,
    projects: """
    **Project Health Check:**
    - Run `mix compile` to check for errors
    - Run `git status` in workspace to see changes
    - Look for uncommitted work that should be saved
    - Report any compile errors or issues found
    """,
    memory_maintenance: """
    **Memory Maintenance (Daily):**
    - Read recent memory/YYYY-MM-DD.md files
    - Extract significant items worth keeping long-term
    - Update MEMORY.md with curated learnings
    - Remove outdated entries from MEMORY.md
    - This is like reviewing your journal and updating your mental model
    """,
    weather: """
    **Weather Check:**
    - Check weather for Sydney, Australia
    - Note if anything unusual (extreme heat, rain, storms)
    - Only report if relevant to outdoor activities or unusual
    """,
    notifications: """
    **Notifications Check:**
    - Check for any pending notifications
    - Review system alerts or messages
    - Only report if something needs attention
    """
  }

  @default_check_instruction """
  **General Check:**
  - Look for anything requiring attention
  - Report only significant findings
  """

  @doc """
  Execute one autonomous work cycle.

  This is called by the heartbeat to let HAL work on tasks autonomously.
  Now integrates with the full autonomy system for time awareness and rotation.

  Returns:
  - `{:ok, action_taken}` - Successfully did work
  - `{:skip, reason}` - No work needed or not appropriate time
  - `{:error, reason}` - Something went wrong
  """
  @spec work_cycle() :: {:ok, String.t()} | {:skip, String.t()} | {:error, term()}
  def work_cycle do
    Logger.info("AutonomousAgent: Starting work cycle")

    # First check if we should work (time awareness)
    case Autonomy.should_work?() do
      {:no, reason} ->
        Logger.info("AutonomousAgent: Skipping - #{reason}")
        {:skip, to_string(reason)}

      {:yes, _} ->
        execute_work_cycle()
    end
  end

  defp execute_work_cycle do
    # Get full context from event log
    context = AgentState.get_context()

    # Check if there's work to do
    case decide_next_action(context) do
      {:ok, action} ->
        execute_action(action)

      {:skip, reason} ->
        Logger.info("AutonomousAgent: Skipping - #{reason}")
        {:skip, reason}
    end
  end

  @doc """
  Decide what to work on next based on context.

  Uses event log history + autonomy system to make informed decisions.
  Implements a priority-based pipeline pattern where each check function
  is evaluated in order until one returns an action.

  ## Priority Order
  1. Resume interrupted tasks (highest priority)
  2. Due heartbeat checks (rotation-based)
  3. Learning-based skip (avoid actions we learned to skip)
  4. Work toward active goals
  5. Periodic maintenance

  ## Check Function Contract
  Each check function returns:
  - `{:ok, action_map}` - Action to take (halts pipeline)
  - `{:skip, reason}` - Skip work entirely (halts pipeline)
  - `nil` - No opinion, continue to next check
  """
  @spec decide_next_action(map()) :: {:ok, map()} | {:skip, String.t()} | {:error, term()}
  def decide_next_action(context) do
    checks = [
      &check_interrupted_tasks/1,
      &check_due_heartbeat/1,
      &check_learning_skip/1,
      &check_active_goals/1,
      &check_maintenance/1
    ]

    Enum.reduce_while(checks, {:skip, "No work needed"}, fn check, default ->
      case check.(context) do
        {:skip, _reason} = skip -> {:halt, skip}
        nil -> {:cont, default}
        {:ok, _action} = result -> {:halt, result}
      end
    end)
  end

  # --- Priority Check Functions ---
  # Each returns {:ok, action}, {:skip, reason}, or nil

  # Priority 1: Resume interrupted work first
  defp check_interrupted_tasks(context) do
    current_tasks = context.current_tasks
    learned_facts = context.learned_facts

    case current_tasks do
      [task | _rest] when is_binary(task) ->
        if should_avoid?(task, learned_facts) do
          nil
        else
          strategy = AgentState.get_strategy(task)

          {:ok,
           %{
             type: :resume,
             task: task,
             strategy: strategy || "determine best approach",
             reason: "Resume interrupted task"
           }}
        end

      _ ->
        nil
    end
  end

  # Priority 2: Due heartbeat checks (rotation)
  defp check_due_heartbeat(_context) do
    case HeartbeatState.get_next_due_check() do
      {check_type, hours_since} ->
        {:ok,
         %{
           type: :heartbeat_check,
           check: check_type,
           hours_since: hours_since,
           reason: "Scheduled check due (#{Float.round(hours_since, 1)}h since last)"
         }}

      nil ->
        nil
    end
  end

  # Priority 3: Check if we should skip due to learned facts
  defp check_learning_skip(context) do
    if should_skip_due_to_learning?(context.learned_facts) do
      {:skip, "Learned to avoid this action at this time"}
    else
      nil
    end
  end

  # Priority 4: Work on goals if we have any
  defp check_active_goals(context) do
    case context.goals do
      [_ | _] = goals ->
        goal = select_best_goal(goals)

        {:ok,
         %{
           type: :goal,
           goal: goal.goal,
           priority: goal.priority,
           reason: "Work toward active goal"
         }}

      _ ->
        nil
    end
  end

  # Priority 5: Check for maintenance tasks
  defp check_maintenance(context) do
    if should_do_maintenance?(context) do
      {:ok,
       %{
         type: :maintenance,
         task: "system maintenance",
         reason: "Periodic cleanup needed"
       }}
    else
      nil
    end
  end

  # --- Helper Functions for Priority Checks ---

  defp should_avoid?(task, learned_facts) do
    # Check if we learned this task fails at current conditions
    Enum.any?(learned_facts, fn fact ->
      is_binary(fact) and
        String.contains?(String.downcase(fact), String.downcase(task)) and
        String.contains?(String.downcase(fact), "avoid")
    end)
  end

  defp select_best_goal(goals) do
    # Simple: pick highest priority (lowest number)
    Enum.min_by(goals, & &1.priority, fn -> hd(goals) end)
  end

  @doc """
  Resume interrupted work after restart.

  Loads current tasks from event log and continues where we left off.
  """
  @spec resume_interrupted_work() :: {:ok, String.t()} | {:skip, String.t()}
  def resume_interrupted_work do
    current_tasks = AgentState.get_current_tasks()

    case current_tasks do
      [] ->
        {:skip, "No interrupted work to resume"}

      [task | _rest] ->
        Logger.info("AutonomousAgent: Resuming interrupted task: #{task}")

        strategy = AgentState.get_strategy(task)
        learned_facts = AgentState.get_learned_facts()

        # Build prompt for Claude with context
        prompt = build_resume_prompt(task, strategy, learned_facts)

        # Execute via Claude Code (simplified for now)
        result = execute_with_claude(prompt)

        case result do
          {:ok, outcome} ->
            AgentState.task_completed(task, outcome)
            AgentState.learned("Successfully resumed #{task} after restart", confidence: 0.9)
            {:ok, "Resumed and completed: #{task}"}

          {:error, reason} ->
            AgentState.action_failed("resume #{task}", reason, retry_count: 1)
            {:skip, "Failed to resume: #{reason}"}
        end
    end
  end

  @doc """
  Learn from recent events to improve future decisions.

  Analyzes recent failures to extract lessons:
  - Patterns in failures (time of day, resource constraints)
  - Successful strategies for different task types
  - Environmental factors (load, availability)
  """
  @spec analyze_and_learn() :: :ok
  def analyze_and_learn do
    # Get recent failures
    failures = AgentState.get_failed_tasks(limit: 10)

    # Look for patterns
    patterns = detect_failure_patterns(failures)

    # Log learned facts
    Enum.each(patterns, fn pattern ->
      AgentState.learned(pattern.fact, confidence: pattern.confidence)
    end)

    # Get recent successes
    successes = AgentState.get_completed_tasks(limit: 10)

    # Extract successful strategies
    strategies = extract_strategies(successes)

    Enum.each(strategies, fn {task_type, strategy} ->
      Logger.info("Learned strategy for #{task_type}: #{strategy}")
    end)

    :ok
  end

  @doc """
  Get summary of what HAL has been doing.

  Useful for reporting to user or debugging.
  """
  @spec get_activity_summary(keyword()) :: String.t()
  def get_activity_summary(opts \\ []) do
    days_back = Keyword.get(opts, :days_back, 1)

    events = EventLog.recent(days_back: days_back)

    completed = Enum.count(events, fn e -> e["event"] == "task_completed" end)
    failed = Enum.count(events, fn e -> e["event"] == "task_failed" end)
    learned = Enum.count(events, fn e -> e["event"] == "learned" end)

    """
    **HAL Activity Summary (last #{days_back} day(s)):**

    - Tasks completed: #{completed}
    - Tasks failed: #{failed}
    - Facts learned: #{learned}
    - Total events: #{length(events)}

    **Current State:**
    - Active tasks: #{length(AgentState.get_current_tasks())}
    - Active goals: #{length(AgentState.get_goals())}
    - Learned facts: #{length(AgentState.get_learned_facts())}
    """
  end

  # Private Functions

  defp execute_action(action) do
    Logger.info("AutonomousAgent: Executing action - #{action.type}")

    AgentState.decision_made(
      "Decided to work on: #{action[:task] || action[:goal] || action[:check]}",
      action.reason
    )

    case action.type do
      :resume ->
        resume_task(action)

      :heartbeat_check ->
        execute_heartbeat_check(action)

      :goal ->
        work_on_goal(action)

      :maintenance ->
        do_maintenance(action)

      _ ->
        {:error, :unknown_action_type}
    end
  end

  defp execute_heartbeat_check(action) do
    check_type = action.check
    hours_since = action.hours_since || 0

    Logger.info(
      "Executing heartbeat check: #{check_type} (#{Float.round(hours_since, 1)}h since last)"
    )

    AgentState.action_taken("Heartbeat check: #{check_type}", %{
      hours_since: hours_since
    })

    # Build prompt with identity context
    identity = SoulLoader.load_identity_context()
    time_context = TimeAwareness.get_current_period()

    prompt = build_check_prompt(check_type, identity, time_context, hours_since)

    # Execute check via Claude
    case execute_check_with_claude(check_type, prompt) do
      {:ok, result} ->
        # Record that we did this check
        HeartbeatState.record_check(check_type, %{result: result})

        # Log to daily memory if not just HEARTBEAT_OK
        if result != "HEARTBEAT_OK" do
          log_to_daily_memory(check_type, result)
        end

        {:ok, "Completed #{check_type} check: #{summarize_result(result)}"}

      {:error, reason} ->
        AgentState.action_failed("heartbeat_check_#{check_type}", reason)
        {:error, reason}
    end
  end

  defp build_check_prompt(check_type, identity, time_context, hours_since) do
    check_instructions = get_check_instructions(check_type)

    """
    #{identity}

    ---

    # Heartbeat Check: #{check_type}

    You are HAL performing a scheduled #{check_type} check as part of your autonomous operation.

    ## Current Context
    - Local time: #{format_local_time(time_context)}
    - Period: #{time_context.period} (#{if time_context.can_work, do: "can work", else: "should be quiet"})
    - Day: #{if time_context.is_weekend, do: "Weekend", else: "Weekday"}
    - Hours since last #{check_type} check: #{Float.round(hours_since, 1)}

    ## Check Instructions
    #{check_instructions}

    ## General Guidelines
    - Work within workspace/ directory
    - Log findings to memory/#{Date.utc_today()}.md
    - If nothing needs attention, reply exactly: HEARTBEAT_OK
    - Keep responses concise (save tokens)
    - Only notify Chris if something is truly important

    ## Your Response
    Either perform the check and report findings, or reply HEARTBEAT_OK if nothing needs attention.
    """
  end

  defp get_check_instructions(check_type) do
    Map.get(@check_instructions, check_type, @default_check_instruction)
  end

  defp execute_check_with_claude(check_type, prompt) do
    execute_with_claude(prompt,
      session_prefix: "heartbeat-#{check_type}",
      timeout: 120_000,
      log_message: "Executing heartbeat check: #{check_type}..."
    )
  end

  defp extract_result(%{result: result}) when is_binary(result), do: String.trim(result)
  defp extract_result(result) when is_binary(result), do: String.trim(result)
  defp extract_result(result), do: inspect(result)

  defp summarize_result("HEARTBEAT_OK"), do: "nothing to report"

  defp summarize_result(result) when byte_size(result) > 100 do
    String.slice(result, 0, 100) <> "..."
  end

  defp summarize_result(result), do: result

  defp log_to_daily_memory(check_type, result) do
    entry =
      "[#{DateTime.utc_now() |> Calendar.strftime("%H:%M")}] Heartbeat #{check_type}: #{summarize_result(result)}"

    case HAL.Autonomy.SelfModification.append_to_daily_log(entry) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to log to daily memory: #{inspect(reason)}")
    end
  end

  defp format_local_time(time_context) do
    "#{time_context.hour}:#{String.pad_leading(to_string(time_context.minute), 2, "0")}"
  end

  defp resume_task(action) do
    task = action.task
    strategy = action.strategy

    AgentState.action_taken("Resume task: #{task}", %{strategy: strategy})

    # Build context-aware prompt
    prompt = build_resume_prompt(task, strategy, AgentState.get_learned_facts())

    case execute_with_claude(prompt) do
      {:ok, outcome} ->
        AgentState.task_completed(task, outcome)
        {:ok, "Completed: #{task}"}

      {:error, reason} ->
        AgentState.action_failed("resume #{task}", reason)
        {:error, reason}
    end
  end

  defp work_on_goal(action) do
    goal = action.goal

    AgentState.action_taken("Work on goal: #{goal}", %{priority: action.priority})

    # For now, just log it
    # In real implementation, would break down goal into tasks
    AgentState.learned("Started work on goal: #{goal}", confidence: 0.7)

    {:ok, "Working on goal: #{goal}"}
  end

  defp do_maintenance(_action) do
    Logger.info("Executing system maintenance...")

    AgentState.action_taken("System maintenance", %{type: "cleanup"})

    # Build maintenance prompt with identity
    identity = SoulLoader.load_identity_context()

    prompt = """
    #{identity}

    ---

    # System Maintenance

    You are HAL performing periodic system maintenance.

    ## Tasks to Perform

    1. **Event Log Cleanup**
       - Check workspace/agent-log.jsonl size
       - If very large (>10MB), suggest archiving old entries

    2. **Memory Review**
       - Read workspace/MEMORY.md
       - Remove any obviously outdated entries
       - Ensure formatting is clean

    3. **Heartbeat State**
       - Check workspace/heartbeat-state.json
       - Remove any stale entries older than 7 days

    4. **Daily Logs**
       - Check workspace/memory/ directory
       - Note any logs older than 30 days that could be archived

    ## Guidelines
    - Don't delete anything important
    - Log any changes made
    - If nothing needs maintenance, reply: HEARTBEAT_OK

    What maintenance was performed?
    """

    case execute_with_claude(prompt) do
      {:ok, result} ->
        if result != "HEARTBEAT_OK" do
          log_to_daily_memory(:maintenance, result)
        end

        AgentState.learned("Completed routine maintenance", confidence: 0.9)
        {:ok, "Maintenance completed: #{summarize_result(result)}"}

      {:error, reason} ->
        AgentState.action_failed("maintenance", reason)
        {:error, reason}
    end
  end

  defp build_resume_prompt(task, strategy, learned_facts) do
    """
    You are HAL, an autonomous agent. You were working on this task but got interrupted:

    **Task:** #{task}
    **Strategy:** #{strategy || "determine best approach"}

    **What I've learned:**
    #{Enum.map_join(learned_facts, "\n", &"- #{&1}")}

    **Your job:**
    Resume this task and complete it. Consider what I've learned to avoid past mistakes.

    What's your next action?
    """
  end

  # Unified Claude execution function
  #
  # Options:
  #   - :session_prefix - Prefix for the session ID (default: "autonomous")
  #   - :timeout - Timeout in milliseconds (default: 180_000)
  #   - :log_message - Custom log message (default: "Executing via Claude Code...")
  #
  # Examples:
  #   execute_with_claude(prompt)
  #   execute_with_claude(prompt, session_prefix: "heartbeat-email", timeout: 120_000)
  #
  defp execute_with_claude(prompt, opts \\ []) do
    session_prefix = Keyword.get(opts, :session_prefix, "autonomous")
    timeout = Keyword.get(opts, :timeout, 180_000)
    log_message = Keyword.get(opts, :log_message, "Executing via Claude Code...")

    session_id = generate_session_id(session_prefix)
    Logger.info(log_message)

    case HAL.Autonomy.Brain.prompt(prompt,
           session_id: session_id,
           timeout: timeout,
           channel_type: "telegram"
         ) do
      {:ok, response} ->
        {:ok, extract_result(response)}

      {:error, reason} ->
        Logger.warning("Claude execution failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp generate_session_id(prefix) do
    "#{prefix}-#{DateTime.utc_now() |> DateTime.to_unix()}"
  end

  defp should_skip_due_to_learning?(learned_facts) do
    current_hour = DateTime.utc_now().hour

    # Check if we learned to avoid this time
    Enum.any?(learned_facts, fn fact ->
      String.contains?(String.downcase(fact), "at #{current_hour}")
    end)
  end

  defp should_do_maintenance?(context) do
    # Do maintenance if we haven't done anything recently
    last_action = context.last_action

    if last_action do
      hours_since = DateTime.diff(DateTime.utc_now(), last_action, :hour)
      hours_since > 24
    else
      true
    end
  end

  defp detect_failure_patterns(failures) do
    # Group failures by error type
    by_error =
      failures
      |> Enum.group_by(fn f -> f[:reason] end)
      |> Enum.filter(fn {_error, occurrences} -> length(occurrences) >= 2 end)

    # Convert to learned facts
    Enum.map(by_error, fn {error, occurrences} ->
      %{
        fact: "Pattern detected: '#{error}' failed #{length(occurrences)} times",
        confidence: min(0.5 + length(occurrences) * 0.1, 0.95)
      }
    end)
  end

  defp extract_strategies(successes) do
    # Extract task -> strategy mapping from successful completions
    # This is simplified - real implementation would use ML or pattern matching

    successes
    |> Enum.map(fn success ->
      task = success[:task]
      # Extract strategy from metadata if available
      strategy = get_in(success, [:metadata, :strategy]) || "unknown"
      {task, strategy}
    end)
    |> Enum.filter(fn {_task, strategy} -> strategy != "unknown" end)
    |> Map.new()
  end
end
