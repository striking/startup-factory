defmodule Hal.Notifications.Proactive do
  @moduledoc """
  Coordinator for proactive notifications.

  Manages the scheduling and execution of proactive notification checks:
  - Calendar reminders (meeting starting soon)
  - Email alerts (urgent emails received)
  - Task reminders (tasks due today)
  - Daily summaries (optional morning briefing)

  ## Usage

      # Check all notification types for a user
      Proactive.check_all(user_id)

      # Check specific notification type
      Proactive.check_calendar(user_id)
      Proactive.check_email(user_id)

      # Schedule recurring checks (called on app startup)
      Proactive.schedule_recurring_checks()

  ## Quiet Hours

  All proactive notifications respect the user's quiet hours settings.
  During quiet hours, notifications are suppressed (recorded but not delivered).
  """

  require Logger

  alias Hal.Notifications.Workers.CalendarReminderWorker
  alias Hal.Notifications.Workers.EmailAlertWorker
  alias Hal.Notifications.Preference
  alias Hal.Notifications.History

  @doc """
  Checks all notification types for a specific user.
  """
  @spec check_all(binary()) :: :ok
  def check_all(user_id) do
    # Run checks in parallel
    tasks = [
      Task.async(fn -> check_calendar(user_id) end),
      Task.async(fn -> check_email(user_id) end)
    ]

    Task.await_many(tasks, 30_000)
    :ok
  end

  @doc """
  Checks calendar for upcoming events and sends reminders.
  """
  @spec check_calendar(binary()) :: :ok
  def check_calendar(user_id) do
    CalendarReminderWorker.check_user_calendar(user_id)
  end

  @doc """
  Checks email for urgent messages and sends alerts.
  """
  @spec check_email(binary()) :: :ok
  def check_email(user_id) do
    EmailAlertWorker.check_user_email(user_id)
  end

  @doc """
  Schedules an immediate check for a user (via Oban).
  """
  @spec schedule_check(binary(), atom()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def schedule_check(user_id, type) do
    worker =
      case type do
        :calendar -> CalendarReminderWorker
        :email -> EmailAlertWorker
        _ -> raise ArgumentError, "Unknown check type: #{type}"
      end

    %{user_id: user_id}
    |> worker.new()
    |> Oban.insert()
  end

  @doc """
  Gets notification preferences for a user, creating defaults if needed.
  """
  @spec get_preferences(binary()) :: {:ok, Preference.t()} | {:error, term()}
  def get_preferences(user_id) do
    Preference.get_or_create(user_id)
  end

  @doc """
  Updates notification preferences for a user.
  """
  @spec update_preferences(binary(), map()) :: {:ok, Preference.t()} | {:error, term()}
  def update_preferences(user_id, attrs) do
    Preference.update(user_id, attrs)
  end

  @doc """
  Checks if the user is currently in quiet hours.
  """
  @spec in_quiet_hours?(binary()) :: boolean()
  def in_quiet_hours?(user_id) do
    Preference.in_quiet_hours?(user_id)
  end

  @doc """
  Gets recent notification history for a user.
  """
  @spec recent_notifications(binary(), keyword()) :: [History.t()]
  def recent_notifications(user_id, opts \\ []) do
    History.recent(user_id, opts)
  end

  @doc """
  Cleans up old notification history.

  Called periodically to prevent unbounded growth.
  """
  @spec cleanup_history(integer()) :: {integer(), nil}
  def cleanup_history(days_to_keep \\ 30) do
    History.cleanup(days_to_keep)
  end

  @doc """
  Sends a proactive notification to a user.

  Respects quiet hours and records in history.
  """
  @spec send(binary(), map()) :: {:ok, History.t()} | {:error, term()}
  def send(user_id, notification) do
    if in_quiet_hours?(user_id) do
      Logger.info("Skipping notification for #{user_id} - in quiet hours")
      {:error, :quiet_hours}
    else
      # Record in history
      History.record(%{
        user_id: user_id,
        trigger_type: to_string(notification[:type] || "general"),
        trigger_id: notification[:data][:habit_id] || notification[:data][:trigger_id],
        title: notification[:title],
        body: notification[:message],
        channel: notification[:channel],
        status: "delivered",
        metadata: notification[:data] || %{}
      })
    end
  end

  @doc """
  Returns status summary for a user's proactive notifications.
  """
  @spec status(binary()) :: map()
  def status(user_id) do
    with {:ok, prefs} <- Preference.get_or_create(user_id) do
      recent = History.recent(user_id, limit: 10)

      %{
        user_id: user_id,
        preferences: %{
          calendar_reminders: prefs.calendar_reminders,
          email_alerts: prefs.email_alerts,
          task_reminders: prefs.task_reminders,
          daily_summary: prefs.daily_summary,
          quiet_hours_enabled: prefs.quiet_hours_enabled
        },
        in_quiet_hours: Preference.in_quiet_hours?(user_id),
        recent_count: length(recent),
        recent_notifications:
          Enum.map(recent, fn h ->
            %{
              type: h.trigger_type,
              title: h.title,
              status: h.status,
              sent_at: h.inserted_at
            }
          end)
      }
    else
      {:error, reason} ->
        %{error: reason}
    end
  end
end
