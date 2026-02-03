defmodule HAL.Autonomy do
  @moduledoc """
  Main entry point for HAL's autonomy system.

  Combines all autonomy components:
  - **HeartbeatState** - Track when checks were last performed
  - **TimeAwareness** - Respect quiet hours and user context
  - **SoulLoader** - Load identity and memory context
  - **Authorization** - Define what HAL can do autonomously
  - **SelfModification** - Allow HAL to update its own files

  ## Philosophy

  HAL's autonomy is based on the Moltbot pattern:
  1. **Prompt-driven identity** - SOUL.md defines who HAL is
  2. **Workspace-as-memory** - Markdown files provide continuity
  3. **Heartbeat polling** - Periodic wake-ups for autonomous work
  4. **Clear boundaries** - Authorization system prevents unwanted actions

  ## Quick Start

      # Check if HAL should do work now
      iex> Autonomy.should_work?()
      {:yes, :clear_to_work}

      # Get the next task to work on
      iex> Autonomy.get_next_task()
      {:ok, %{type: :heartbeat_check, check: :email}}

      # Execute an autonomous work cycle
      iex> Autonomy.work_cycle()
      {:ok, "Checked email - nothing urgent"}

  ## Integration

  The autonomy system is called by:
  - `HAL.Heartbeat` - For periodic checks
  - `HAL.AutonomousAgent` - For decision making
  - `HAL.Gateway.SessionServer` - For session context loading
  """

  require Logger

  alias HAL.Autonomy.{
    Brain,
    HeartbeatState,
    TimeAwareness,
    SoulLoader,
    Authorization,
    SelfModification
  }

  alias HAL.AgentState
  alias HAL.Credentials
  alias HAL.Costs.Budget
  alias Hal.Accounts.DefaultUser
  alias HAL.Integrations.Calendar
  alias HAL.Integrations.Email

  @doc """
  Check if HAL should do autonomous work right now.

  Considers:
  - Time of day (quiet hours)
  - User status (busy, focus mode)
  - Active sessions (user chatting)

  ## Returns
    - {:yes, reason} if clear to work
    - {:no, reason} if should stay quiet
  """
  @spec should_work?() :: {:yes, atom()} | {:no, atom()}
  def should_work? do
    # First check time awareness
    case TimeAwareness.appropriate_to_work?() do
      {:no, reason} ->
        {:no, reason}

      {:yes, _} ->
        # Then check if user is actively chatting
        if user_actively_chatting?() do
          {:no, :active_session}
        else
          if budget_allows_autonomy?() do
            {:yes, :clear_to_work}
          else
            {:no, :budget_exceeded}
          end
        end
    end
  end

  @doc """
  Get the next task HAL should work on.

  Priority order:
  1. Resume interrupted tasks
  2. Due heartbeat checks (rotation)
  3. Active goals
  4. Proactive maintenance

  ## Returns
    - {:ok, task_map} if there's work to do
    - {:skip, reason} if nothing to do
  """
  @spec get_next_task() :: {:ok, map()} | {:skip, String.t()}
  def get_next_task do
    context = get_decision_context()

    cond do
      # Priority 1: Resume interrupted tasks
      length(context.current_tasks) > 0 and
          not should_avoid?(hd(context.current_tasks), context.learned_facts) ->
        task = hd(context.current_tasks)
        strategy = AgentState.get_strategy(task)
        {:ok, %{type: :resume, task: task, strategy: strategy, reason: "Resume interrupted work"}}

      # Priority 2: Due heartbeat check
      (due_check = HeartbeatState.get_next_due_check()) != nil ->
        {check_type, hours_since} = due_check

        {:ok,
         %{
           type: :heartbeat_check,
           check: check_type,
           hours_since: hours_since,
           reason: "Scheduled check due"
         }}

      # Priority 3: Active goals
      length(context.goals) > 0 ->
        goal = select_best_goal(context.goals, context.learned_facts)

        {:ok,
         %{type: :goal, goal: goal.goal, priority: goal.priority, reason: "Work toward goal"}}

      # Priority 4: Memory maintenance (if not done recently)
      HeartbeatState.should_check?(:memory_maintenance, 24) ->
        {:ok, %{type: :maintenance, task: :memory_maintenance, reason: "Daily memory review"}}

      # Nothing to do
      true ->
        {:skip, "No work needed"}
    end
  end

  @doc """
  Execute one autonomous work cycle.

  This is the main entry point called by Heartbeat.

  ## Returns
    - {:ok, result} if work was done
    - {:skip, reason} if no work needed
    - {:error, reason} if something failed
  """
  @spec work_cycle() :: {:ok, String.t()} | {:skip, String.t()} | {:error, term()}
  def work_cycle do
    Logger.info("Autonomy: Starting work cycle")

    # Check if we should work
    case should_work?() do
      {:no, reason} ->
        Logger.debug("Autonomy: Skipping work - #{reason}")
        {:skip, to_string(reason)}

      {:yes, _} ->
        execute_work_cycle()
    end
  end

  @doc """
  Build system prompt for a session with full context.

  ## Parameters
    - session_type: :main (includes MEMORY.md) or :shared (excludes personal memory)
    - opts: Additional options passed to SoulLoader
  """
  @spec build_session_prompt(atom(), keyword()) :: String.t()
  def build_session_prompt(session_type \\ :main, opts \\ []) do
    SoulLoader.build_system_prompt(session_type, opts)
  end

  @doc """
  Get current autonomy status for dashboard/debugging.
  """
  @spec get_status() :: map()
  def get_status do
    time_period = TimeAwareness.get_current_period()
    due_checks = HeartbeatState.get_due_checks()
    heartbeat_state = HeartbeatState.get_state()

    %{
      time: %{
        period: time_period.period,
        hour: time_period.hour,
        can_work: time_period.can_work,
        can_reach_out: time_period.can_reach_out,
        is_weekend: time_period.is_weekend
      },
      heartbeat: %{
        due_checks: due_checks,
        last_checks: heartbeat_state["lastChecks"] || %{}
      },
      identity: %{
        files_present: SoulLoader.check_identity_files(),
        soul_loaded: SoulLoader.load_soul() != ""
      },
      work_status: should_work?()
    }
  end

  @doc """
  Initialize the autonomy system.

  Should be called on application start.
  """
  @spec init() :: :ok
  def init do
    Logger.info("Initializing HAL Autonomy system...")

    # Ensure identity files exist
    SoulLoader.ensure_identity_files!()

    # Log initial status
    status = get_status()

    Logger.info(
      "Autonomy initialized - Period: #{status.time.period}, Can work: #{status.time.can_work}"
    )

    :ok
  end

  # Convenience aliases for sub-modules

  @doc "Record that a heartbeat check was performed."
  defdelegate record_check(check_type, metadata \\ %{}), to: HeartbeatState

  @doc "Check if a specific check is due."
  defdelegate should_check?(check_type, interval \\ nil), to: HeartbeatState

  @doc "Check if action can be done autonomously."
  defdelegate can_do_autonomously?(action), to: Authorization

  @doc "Update a workspace file."
  defdelegate update_file(path, content, opts \\ []), to: SelfModification

  @doc "Append to daily log."
  defdelegate log(content), to: SelfModification, as: :append_to_daily_log

  @doc "Add a memory."
  defdelegate remember(content, type \\ :knowledge), to: SelfModification, as: :add_memory

  @doc "Load identity context."
  defdelegate load_identity(), to: SoulLoader, as: :load_identity_context

  @doc "Enable focus mode."
  defdelegate focus(minutes \\ 120), to: TimeAwareness, as: :enable_focus_mode

  @doc "Disable focus mode."
  defdelegate unfocus(), to: TimeAwareness, as: :disable_focus_mode

  # Private Functions

  defp execute_work_cycle do
    case get_next_task() do
      {:skip, reason} ->
        {:skip, reason}

      {:ok, task} ->
        Logger.info(
          "Autonomy: Executing task - #{task.type}: #{task[:task] || task[:check] || task[:goal]}"
        )

        # Log decision
        AgentState.decision_made(
          "Working on: #{inspect(task.type)}",
          task.reason
        )

        result = execute_task(task)

        # Analyze and learn after work
        analyze_and_learn()

        result
    end
  end

  defp execute_task(%{type: :heartbeat_check, check: check_type} = _task) do
    Logger.info("Executing heartbeat check: #{check_type}")

    # Execute the check
    result = perform_check(check_type)

    # Record that we did this check (convert result to JSON-friendly format)
    HeartbeatState.record_check(check_type, result_to_metadata(result))

    {:ok, "Completed #{check_type} check: #{inspect(result)}"}
  end

  defp execute_task(%{type: :resume, task: task, strategy: strategy} = _task) do
    Logger.info("Resuming task: #{task}")

    # Build context-aware prompt
    learned_facts = AgentState.get_learned_facts()
    prompt = build_resume_prompt(task, strategy, learned_facts)

    # Execute via Claude Code
    session_id = "resume-task-#{:erlang.phash2(task)}-#{DateTime.utc_now() |> DateTime.to_unix()}"

    case Brain.prompt(prompt, session_id: session_id, timeout: 300_000, channel_type: "telegram") do
      {:ok, response} ->
        outcome = extract_task_outcome(response)
        AgentState.task_completed(task, outcome)
        {:ok, "Completed: #{task} - #{String.slice(outcome, 0, 100)}"}

      {:error, reason} ->
        Logger.warning("Resume task failed: #{inspect(reason)}")
        AgentState.task_failed(task, inspect(reason))
        {:error, reason}
    end
  end

  defp execute_task(%{type: :goal, goal: goal} = task) do
    Logger.info("Working on goal: #{goal}")

    # Build goal-focused prompt
    prompt = build_goal_prompt(goal, task)

    session_id = "goal-#{:erlang.phash2(goal)}-#{DateTime.utc_now() |> DateTime.to_unix()}"

    case Brain.prompt(prompt, session_id: session_id, timeout: 300_000, channel_type: "telegram") do
      {:ok, response} ->
        outcome = extract_task_outcome(response)
        AgentState.action_taken("Worked on goal: #{goal}", %{outcome: outcome})
        {:ok, "Goal progress: #{goal} - #{String.slice(outcome, 0, 100)}"}

      {:error, reason} ->
        Logger.warning("Goal work failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp execute_task(%{type: :maintenance, task: :memory_maintenance} = _task) do
    Logger.info("Performing memory maintenance")

    # Build maintenance prompt
    prompt = build_maintenance_prompt()
    session_id = "maintenance-#{DateTime.utc_now() |> DateTime.to_unix()}"

    case Brain.prompt(prompt, session_id: session_id, timeout: 180_000, channel_type: "telegram") do
      {:ok, response} ->
        outcome = extract_task_outcome(response)
        HeartbeatState.record_check(:memory_maintenance, %{completed: true, summary: outcome})
        {:ok, "Memory maintenance completed: #{String.slice(outcome, 0, 100)}"}

      {:error, reason} ->
        Logger.warning("Memory maintenance failed: #{inspect(reason)}")

        HeartbeatState.record_check(:memory_maintenance, %{
          completed: false,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  defp execute_task(%{type: type} = task) do
    Logger.warning("Unknown task type: #{type}")
    {:error, {:unknown_task_type, task}}
  end

  defp perform_check(:email) do
    Logger.debug("Checking email...")

    case Credentials.get_google_token() do
      {:ok, token} ->
        check_email_with_token(token)

      {:error, :not_found} ->
        Logger.info(
          "Email check skipped: Google credentials not configured at ~/.hal/credentials/google.json"
        )

        {:skipped, :not_configured}

      {:error, reason} ->
        Logger.warning("Email check failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp perform_check(:calendar) do
    Logger.debug("Checking calendar...")

    case Credentials.get_google_token() do
      {:ok, token} ->
        check_calendar_with_token(token)

      {:error, :not_found} ->
        Logger.info(
          "Calendar check skipped: Google credentials not configured at ~/.hal/credentials/google.json"
        )

        {:skipped, :not_configured}

      {:error, reason} ->
        Logger.warning("Calendar check failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp perform_check(:projects) do
    Logger.debug("Checking projects...")
    check_local_projects()
  end

  defp perform_check(:weather) do
    Logger.debug("Checking weather...")
    # Weather is low priority and optional - skip if not configured
    {:skipped, :not_configured}
  end

  defp perform_check(other) do
    Logger.debug("Unknown check type: #{other}")
    {:skipped, :unknown_check_type}
  end

  # Real email check implementation
  defp check_email_with_token(token) do
    # Check unread emails from the last hour
    case Email.get_unread_emails(token, max_results: 10) do
      {:ok, messages} when is_list(messages) ->
        unread_count = length(messages)

        if unread_count > 0 do
          # Check for urgent patterns (from VIPs, contains "urgent", etc.)
          urgent = Enum.any?(messages, &email_looks_urgent?/1)

          if urgent do
            Logger.info("Email check: #{unread_count} unread, URGENT found")
            {:urgent, unread_count}
          else
            Logger.info("Email check: #{unread_count} unread, nothing urgent")
            {:has_unread, unread_count}
          end
        else
          Logger.info("Email check: No unread emails")
          :nothing_urgent
        end

      {:ok, _} ->
        :nothing_urgent

      {:error, reason} ->
        Logger.warning("Email check failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Real calendar check implementation
  defp check_calendar_with_token(token) do
    now = DateTime.utc_now()
    # Check events in the next 2 hours
    two_hours_later = DateTime.add(now, 7200, :second)

    case Calendar.list_events(token, time_min: now, time_max: two_hours_later, max_results: 5) do
      {:ok, events} when is_list(events) ->
        if length(events) > 0 do
          next_event = hd(events)
          summary = next_event["summary"] || "Untitled event"
          start_time = get_event_start_time(next_event)

          Logger.info("Calendar check: Next event '#{summary}' at #{start_time}")
          {:upcoming, length(events), summary}
        else
          Logger.info("Calendar check: No upcoming events in next 2 hours")
          :no_upcoming_events
        end

      {:ok, _} ->
        :no_upcoming_events

      {:error, reason} ->
        Logger.warning("Calendar check failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Check local project directories for activity
  defp check_local_projects do
    projects_dir = Path.expand("~/dev")

    if File.dir?(projects_dir) do
      # Look for recently modified files in key project areas
      recent_activity =
        Path.wildcard("#{projects_dir}/**/CLAUDE.md")
        |> Enum.filter(&file_modified_recently?(&1, 24))
        |> length()

      if recent_activity > 0 do
        Logger.info("Projects check: #{recent_activity} projects with recent activity")
        {:active_projects, recent_activity}
      else
        Logger.info("Projects check: No recent project activity")
        :all_good
      end
    else
      :all_good
    end
  end

  defp email_looks_urgent?(message) do
    subject = get_in(message, ["payload", "headers"]) |> find_header("Subject") || ""
    from = get_in(message, ["payload", "headers"]) |> find_header("From") || ""

    urgent_patterns = ~w(urgent asap important action required deadline emergency)
    subject_lower = String.downcase(subject)
    from_lower = String.downcase(from)

    # Check for urgent keywords in subject
    # Check for VIP senders (could be configured)
    Enum.any?(urgent_patterns, &String.contains?(subject_lower, &1)) or
      String.contains?(from_lower, "chris")
  end

  defp find_header(nil, _name), do: nil

  defp find_header(headers, name) when is_list(headers) do
    case Enum.find(headers, &(&1["name"] == name)) do
      %{"value" => value} -> value
      _ -> nil
    end
  end

  defp get_event_start_time(event) do
    case event["start"] do
      %{"dateTime" => dt} -> dt
      %{"date" => d} -> d
      _ -> "unknown"
    end
  end

  defp file_modified_recently?(path, hours) do
    case File.stat(path) do
      {:ok, %{mtime: mtime}} ->
        modified = NaiveDateTime.from_erl!(mtime)
        now = NaiveDateTime.utc_now()
        diff_hours = NaiveDateTime.diff(now, modified, :hour)
        diff_hours <= hours

      _ ->
        false
    end
  end

  # Convert check results to JSON-friendly metadata format
  defp result_to_metadata(result) do
    case result do
      # Simple atoms
      :nothing_urgent -> %{status: "ok", result: "nothing_urgent"}
      :no_upcoming_events -> %{status: "ok", result: "no_upcoming_events"}
      :all_good -> %{status: "ok", result: "all_good"}
      # Tuples with data
      {:skipped, reason} -> %{status: "skipped", reason: to_string(reason)}
      {:error, reason} -> %{status: "error", reason: inspect(reason)}
      {:urgent, count} -> %{status: "urgent", unread_count: count}
      {:has_unread, count} -> %{status: "ok", unread_count: count}
      {:upcoming, count, summary} -> %{status: "ok", event_count: count, next_event: summary}
      {:active_projects, count} -> %{status: "ok", active_projects: count}
      # Fallback for any other format
      other when is_atom(other) -> %{status: "ok", result: to_string(other)}
      other -> %{status: "unknown", raw: inspect(other)}
    end
  end

  defp get_decision_context do
    AgentState.get_context()
  end

  defp should_avoid?(task, learned_facts) do
    # Check if we learned this task fails at current conditions
    Enum.any?(learned_facts, fn fact ->
      is_binary(fact) and
        String.contains?(String.downcase(fact), String.downcase(task)) and
        String.contains?(String.downcase(fact), "avoid")
    end)
  end

  defp select_best_goal(goals, _learned_facts) do
    # Simple: just pick highest priority
    # Could be smarter based on learned facts
    Enum.min_by(goals, fn g -> g.priority end, fn -> hd(goals) end)
  end

  defp build_resume_prompt(task, strategy, learned_facts) do
    facts_text =
      learned_facts
      |> Enum.take(5)
      |> Enum.map_join("\n", &"- #{&1}")

    """
    You are HAL, resuming interrupted work.

    **Task:** #{task}
    **Strategy:** #{strategy || "determine best approach"}

    **Learned facts:**
    #{facts_text}

    Resume and complete this task. Use your available tools (Bash, Read, Write, etc.) to actually perform the work.
    Report what you accomplished clearly.
    """
  end

  defp build_goal_prompt(goal, task) do
    priority = Map.get(task, :priority, 5)

    """
    You are HAL working autonomously on a goal.

    **Goal:** #{goal}
    **Priority:** #{priority}/10

    Take concrete action toward this goal. Use your available tools to make real progress:
    - Search for information if needed
    - Read relevant files
    - Execute commands
    - Write or update files

    Report what specific progress you made.
    """
  end

  defp build_maintenance_prompt do
    """
    You are HAL performing memory maintenance.

    Review the recent activity and update the workspace appropriately:

    1. Check workspace/memory/ for recent notes
    2. Check workspace/agent-log.jsonl for patterns
    3. Update MEMORY.md with any important learnings
    4. Clean up outdated information

    Be concise - summarize what you cleaned up or learned.
    """
  end

  defp extract_task_outcome(response) when is_map(response) do
    # Handle JSON response from Claude Code
    Map.get(response, :result, Map.get(response, "result", "Task completed"))
  end

  defp extract_task_outcome(response) when is_binary(response) do
    # Handle text response
    String.trim(response)
  end

  defp extract_task_outcome(_), do: "Task completed"

  defp analyze_and_learn do
    # Get recent failures and look for patterns
    failures = AgentState.get_failed_tasks(limit: 5)

    if length(failures) >= 2 do
      # Look for repeated errors
      by_error =
        failures
        |> Enum.group_by(fn f -> f[:reason] end)
        |> Enum.filter(fn {_error, occurrences} -> length(occurrences) >= 2 end)

      Enum.each(by_error, fn {error, occurrences} ->
        fact = "Pattern: '#{error}' failed #{length(occurrences)} times - consider avoiding"
        AgentState.learned(fact, confidence: 0.8)
      end)
    end

    :ok
  end

  defp user_actively_chatting? do
    # Check if any active sessions
    try do
      Hal.Gateway.SessionManager.count_active_sessions() > 0
    rescue
      _ -> false
    catch
      :exit, _ -> false
    end
  end

  defp budget_allows_autonomy? do
    enforce? =
      Application.get_env(:hal, Budget, [])
      |> Keyword.get(:enforce_autonomy, true)

    if not enforce? do
      true
    else
      case DefaultUser.get() do
        %{} = user -> Budget.within_budget?(user.id)
        nil -> true
      end
    end
  rescue
    _ -> true
  end
end
