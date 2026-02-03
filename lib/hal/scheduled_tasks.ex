defmodule HAL.ScheduledTasks do
  @moduledoc """
  User-configured scheduled tasks that run at specific times.

  These are definite, time-based tasks where the user knows
  they want something to happen (daily briefing, weekly review, etc.).
  """

  require Logger

  alias Hal.Habits
  alias Hal.Tasks
  alias Hal.Knowledge
  alias Hal.Notifications.Proactive
  alias HAL.Autonomy.Brain

  @doc """
  Morning briefing sent via Telegram at 9am daily.

  Gives overview of:
  - Today's calendar
  - Habit progress and streaks
  - Pending autonomous tasks
  - Knowledge base activity
  - Recent notifications
  - Important emails
  """
  def morning_briefing do
    Logger.info("Running morning briefing")

    # Get the primary user (web chat user for now)
    user = get_briefing_user()

    if user do
      run_briefing_for_user(user)
    else
      Logger.warning("No user found for morning briefing")
      :error
    end
  end

  defp run_briefing_for_user(user) do
    session_id = "morning-briefing-#{Date.utc_today()}"

    # Gather real data from all systems
    context = gather_briefing_context(user.id)

    message = """
    Generate my morning briefing based on this real data:

    ## Habits Today
    #{context.habits_summary}

    ## Autonomous Tasks
    #{context.tasks_summary}

    ## Knowledge Base
    #{context.knowledge_summary}

    ## Recent Notifications
    #{context.notifications_summary}

    ## Instructions
    Create a concise, actionable morning briefing. Prioritize:
    1. Habits at risk of breaking streaks (urgent!)
    2. Running tasks that need attention
    3. Calendar events (check my calendar)
    4. Important emails

    Be encouraging about habits but honest about what needs doing.
    Keep it under 300 words. Send via Telegram.
    """

    case Brain.prompt(message,
           session_id: session_id,
           timeout: 180_000,
           user_id: user.id,
           channel_type: "telegram"
         ) do
      {:ok, _response} ->
        :ok

      {:error, {:budget_exceeded, _remaining}} ->
        Logger.info("Morning briefing skipped: budget exceeded")
        :ok

      {:error, reason} ->
        Logger.error("Morning briefing failed: #{inspect(reason)}")
        :error
    end
  end

  @doc """
  Gathers context from all HAL systems for the briefing.
  """
  def gather_briefing_context(user_id) do
    %{
      habits_summary: get_habits_summary(user_id),
      tasks_summary: get_tasks_summary(user_id),
      knowledge_summary: get_knowledge_summary(user_id),
      notifications_summary: get_notifications_summary(user_id)
    }
  end

  defp get_habits_summary(user_id) do
    progress = Habits.today_progress(user_id)

    if progress.total_due == 0 do
      "No habits scheduled for today."
    else
      pending = progress.habits |> Enum.filter(&(!&1.completed))
      at_risk = pending |> Enum.filter(&(&1.current_streak > 3))

      lines = [
        "- #{progress.completed}/#{progress.total_due} completed (#{Float.round(progress.completion_rate, 0)}%)"
      ]

      lines =
        if length(at_risk) > 0 do
          streak_warnings =
            Enum.map(at_risk, fn h ->
              "  ⚠️ #{h.name} (#{h.current_streak}-day streak at risk!)"
            end)

          lines ++ ["- Streaks at risk:"] ++ streak_warnings
        else
          lines
        end

      lines =
        if length(pending) > 0 do
          pending_names = Enum.map(pending, & &1.name) |> Enum.join(", ")
          lines ++ ["- Still to do: #{pending_names}"]
        else
          lines ++ ["- All habits complete! 🎉"]
        end

      Enum.join(lines, "\n")
    end
  end

  defp get_tasks_summary(user_id) do
    running = Tasks.list(user_id, status: "running")
    pending = Tasks.list(user_id, status: "pending")

    cond do
      length(running) > 0 ->
        task_list =
          Enum.map(running, fn t ->
            progress = Tasks.AutoTask.progress(t)
            "  - #{t.title} (#{progress}% complete)"
          end)
          |> Enum.join("\n")

        "- #{length(running)} task(s) running:\n#{task_list}\n- #{length(pending)} pending"

      length(pending) > 0 ->
        "- #{length(pending)} task(s) waiting to start"

      true ->
        "No autonomous tasks active."
    end
  end

  defp get_knowledge_summary(user_id) do
    stats = Knowledge.stats(user_id)

    if stats.total_documents == 0 do
      "Knowledge base is empty. Upload documents to build your second brain!"
    else
      "- #{stats.total_documents} documents (#{stats.total_chunks} chunks indexed)\n" <>
        "- Categories: #{Map.keys(stats.by_category) |> Enum.join(", ")}"
    end
  end

  defp get_notifications_summary(user_id) do
    recent = Proactive.recent_notifications(user_id, limit: 5)

    if length(recent) == 0 do
      "No recent notifications."
    else
      items =
        Enum.map(recent, fn n ->
          "  - [#{n.trigger_type}] #{n.title}"
        end)
        |> Enum.take(3)
        |> Enum.join("\n")

      "Recent (last 24h):\n#{items}"
    end
  end

  defp get_briefing_user do
    Hal.Accounts.DefaultUser.get()
  end

  @doc """
  Weekly review sent Friday evening.

  Summarizes the week and prepares for next week.
  """
  def weekly_review do
    Logger.info("Running weekly review")

    user = get_briefing_user()

    if user do
      run_weekly_review_for_user(user)
    else
      Logger.warning("No user found for weekly review")
      :error
    end
  end

  defp run_weekly_review_for_user(user) do
    session_id = "weekly-review-#{Date.utc_today()}"

    # Gather week's data
    context = gather_weekly_context(user.id)

    message = """
    Generate my weekly review based on this real data:

    ## Habit Performance This Week
    #{context.habits_week_summary}

    ## Completed Tasks
    #{context.completed_tasks_summary}

    ## Knowledge Base Growth
    #{context.knowledge_growth}

    ## Self-Improvement Insights
    #{context.improvement_summary}

    ## Instructions
    Create a thoughtful weekly review:
    1. Celebrate wins (completed tasks, habit streaks)
    2. Identify patterns (what's working, what's not)
    3. Suggest focus areas for next week
    4. Be encouraging but honest

    Keep it actionable. Send via Telegram.
    """

    case Brain.prompt(message,
           session_id: session_id,
           timeout: 240_000,
           user_id: user.id,
           channel_type: "telegram"
         ) do
      {:ok, _response} ->
        :ok

      {:error, {:budget_exceeded, _remaining}} ->
        Logger.info("Weekly review skipped: budget exceeded")
        :ok

      {:error, reason} ->
        Logger.error("Weekly review failed: #{inspect(reason)}")
        :error
    end
  end

  defp gather_weekly_context(user_id) do
    %{
      habits_week_summary: get_habits_week_summary(user_id),
      completed_tasks_summary: get_completed_tasks_summary(user_id),
      knowledge_growth: get_knowledge_growth(user_id),
      improvement_summary: get_improvement_summary()
    }
  end

  defp get_habits_week_summary(user_id) do
    habits = Habits.list(user_id)

    if length(habits) == 0 do
      "No habits tracked yet."
    else
      summaries =
        Enum.map(habits, fn habit ->
          stats = Habits.stats(habit.id, days: 7)

          "- #{habit.name}: #{stats.completed_count}/7 days (#{Float.round(stats.completion_rate, 0)}%), streak: #{habit.current_streak}"
        end)

      Enum.join(summaries, "\n")
    end
  end

  defp get_completed_tasks_summary(user_id) do
    completed = Tasks.list(user_id, status: "completed")
    week_ago = DateTime.add(DateTime.utc_now(), -7, :day)

    this_week =
      Enum.filter(completed, fn t ->
        DateTime.compare(t.completed_at || t.updated_at, week_ago) == :gt
      end)

    if length(this_week) == 0 do
      "No autonomous tasks completed this week."
    else
      task_list = Enum.map(this_week, fn t -> "- #{t.title}" end) |> Enum.join("\n")
      "#{length(this_week)} task(s) completed:\n#{task_list}"
    end
  end

  defp get_knowledge_growth(user_id) do
    stats = Knowledge.stats(user_id)

    # Note: We'd need to track this over time for real growth metrics
    # For now, just show current state
    "Current: #{stats.total_documents} documents, #{stats.total_chunks} chunks"
  end

  defp get_improvement_summary do
    # Check for pending improvements from self-improvement system
    proposals_path = ".claude/pending_improvements.json"

    case File.read(proposals_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, proposals} when is_list(proposals) and length(proposals) > 0 ->
            pending = Enum.filter(proposals, fn p -> p["status"] == "pending" end)
            "#{length(pending)} improvement proposals pending review"

          _ ->
            "No pending improvements."
        end

      {:error, _} ->
        "Self-improvement system active, no proposals yet."
    end
  end
end
