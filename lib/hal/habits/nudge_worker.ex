defmodule Hal.Habits.NudgeWorker do
  @moduledoc """
  Oban worker for sending habit nudges.

  Runs every 5 minutes to check for habits that:
  - Have reminder_enabled = true
  - Have a reminder_time within the current window
  - Haven't been completed today
  - Are due today based on frequency

  Uses AI to craft personalized, motivating nudges.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1

  require Logger

  alias HAL.Autonomy.Brain
  alias Hal.Habits
  alias Hal.Notifications.Proactive

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Checking for habit nudges...")

    habits_due = Habits.due_for_nudge()

    if length(habits_due) > 0 do
      Logger.info("Found #{length(habits_due)} habits to nudge")
      Enum.each(habits_due, &send_nudge/1)
    end

    :ok
  end

  defp send_nudge(%{habit: habit, user: user, streak: streak}) do
    # Use AI to craft a personalized nudge
    nudge_text = generate_nudge(habit, streak)

    # Send via notification system
    Proactive.send(user.id, %{
      type: :habit_reminder,
      title: "Habit Reminder: #{habit.name}",
      message: nudge_text,
      data: %{
        habit_id: habit.id,
        habit_name: habit.name,
        current_streak: streak
      }
    })

    Logger.info("Sent nudge for habit #{habit.name} to user #{user.id}")
  end

  defp generate_nudge(habit, streak) do
    prompt = """
    Generate a brief, friendly reminder for this habit. Be encouraging but not annoying.
    Keep it to 1-2 sentences max.

    Habit: #{habit.name}
    #{if habit.description, do: "Description: #{habit.description}", else: ""}
    Category: #{habit.category || "general"}
    Current streak: #{streak} days

    Guidelines:
    - If streak > 0, mention keeping the streak alive
    - If streak is 0, focus on starting fresh
    - Be warm and supportive, not pushy
    - Don't use exclamation marks excessively
    - Personalize based on the category if possible

    Return ONLY the nudge text, no quotes or labels.
    """

    case Brain.prompt(prompt,
           user_id: habit.user_id,
           hal_session_id: "habit:#{habit.id}",
           channel_type: "terminal",
           channel_id: "habit:nudge",
           timeout: 25_000,
           log: false
         ) do
      {:ok, response} when is_binary(response) ->
        String.trim(response)

      {:error, _reason} ->
        # Fallback to simple template
        if streak > 0 do
          "Don't forget about #{habit.name}! You're on a #{streak}-day streak."
        else
          "Time for #{habit.name}. Today's a great day to start."
        end
    end
  end
end
