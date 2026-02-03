defmodule Hal.Notifications.Workers.CalendarReminderWorker do
  @moduledoc """
  Oban worker that checks for upcoming calendar events and sends reminders.

  Runs periodically (every 5 minutes) to check for events that need reminders.
  Respects user preferences for reminder timing (15, 30, 60 minutes before).
  """

  use Oban.Worker,
    queue: :scheduled,
    max_attempts: 3

  require Logger

  alias HAL.Credentials
  alias Hal.Notifications
  alias Hal.Notifications.Preference
  alias Hal.Notifications.History
  alias HAL.Integrations.Calendar, as: CalendarAPI

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    user_id = args["user_id"]

    if user_id do
      check_user_calendar(user_id)
    else
      check_all_users()
    end

    :ok
  end

  @doc """
  Checks calendar for a specific user and sends reminders.
  """
  def check_user_calendar(user_id) do
    with {:ok, prefs} <- Preference.get_or_create(user_id),
         true <- prefs.calendar_reminders,
         false <- Preference.in_quiet_hours?(user_id),
         {:ok, access_token} <- Credentials.get_google_token() do
      process_upcoming_events(user_id, access_token, prefs)
    else
      {:error, :not_found} ->
        Logger.debug("Google credentials not configured, skipping calendar check")
        :ok

      {:error, reason} ->
        Logger.warning("Calendar check failed for user #{user_id}: #{inspect(reason)}")
        :ok

      false ->
        Logger.debug("Calendar reminders disabled or in quiet hours for user #{user_id}")
        :ok

      _ ->
        :ok
    end
  end

  defp check_all_users do
    # Get all users with calendar reminders enabled
    Preference.users_with_enabled(:calendar)
    |> Enum.each(fn pref ->
      check_user_calendar(pref.user_id)
    end)
  end

  defp process_upcoming_events(user_id, access_token, prefs) do
    # Look ahead for the longest reminder window (e.g., 60 minutes)
    max_minutes = Enum.max(prefs.calendar_reminder_minutes, fn -> 60 end)
    time_min = DateTime.utc_now()
    time_max = DateTime.add(time_min, max_minutes + 5, :minute)

    case CalendarAPI.list_events(access_token,
           time_min: time_min,
           time_max: time_max,
           max_results: 20,
           order_by: "startTime"
         ) do
      {:ok, events} ->
        Enum.each(events, fn event ->
          check_and_send_reminder(user_id, event, prefs)
        end)

      {:error, reason} ->
        Logger.error("Failed to fetch calendar events: #{inspect(reason)}")
    end
  end

  defp check_and_send_reminder(user_id, event, prefs) do
    event_start = parse_event_time(event["start"])

    if event_start do
      minutes_until = minutes_until_event(event_start)

      # Find matching reminder intervals
      prefs.calendar_reminder_minutes
      |> Enum.filter(fn mins ->
        # Allow 2 minute window for cron timing
        minutes_until >= mins - 2 and minutes_until <= mins + 2
      end)
      |> Enum.each(fn reminder_mins ->
        send_reminder_if_not_sent(user_id, event, reminder_mins)
      end)
    end
  end

  defp send_reminder_if_not_sent(user_id, event, reminder_mins) do
    event_id = event["id"]
    trigger_id = "#{event_id}_#{reminder_mins}min"

    unless History.already_sent?(user_id, "calendar", trigger_id) do
      send_calendar_reminder(user_id, event, reminder_mins, trigger_id)
    end
  end

  defp send_calendar_reminder(user_id, event, reminder_mins, trigger_id) do
    title = event["summary"] || "Untitled Event"
    location = event["location"]
    event_start = parse_event_time(event["start"])

    # Record the notification attempt
    {:ok, history} =
      History.record(%{
        user_id: user_id,
        trigger_type: "calendar",
        trigger_id: trigger_id,
        title: "📅 #{title}",
        body: format_reminder_body(title, event_start, location, reminder_mins),
        priority: if(reminder_mins <= 15, do: "urgent", else: "normal"),
        metadata: %{
          event_id: event["id"],
          reminder_minutes: reminder_mins
        }
      })

    # Get user and send notification
    case Hal.Repo.get(Hal.Accounts.User, user_id) do
      nil ->
        History.mark_failed(history.id, "User not found")

      user ->
        message = format_reminder_message(title, event_start, location, reminder_mins)

        case Notifications.send(user, message, fallback: true) do
          {:ok, result} ->
            channel = to_string(result.channel)
            message_id = result[:message_id] || result[:message_ts] || result[:chat_id]
            History.mark_delivered(history.id, channel, to_string(message_id))

          {:error, reason} ->
            History.mark_failed(history.id, inspect(reason))
        end
    end
  end

  defp format_reminder_message(title, event_start, location, reminder_mins) do
    time_str = format_time(event_start)

    msg = "📅 *#{title}* starts in #{reminder_mins} minutes\n⏰ #{time_str}"
    if location, do: msg <> "\n📍 #{location}", else: msg
  end

  defp format_reminder_body(title, event_start, location, reminder_mins) do
    time_str = format_time(event_start)
    body = "Event: #{title}\nStarts: #{time_str} (in #{reminder_mins} minutes)"
    if location, do: body <> "\nLocation: #{location}", else: body
  end

  defp parse_event_time(%{"dateTime" => dt}) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_event_time(%{"date" => date}) when is_binary(date) do
    # All-day event - treat as midnight
    case Date.from_iso8601(date) do
      {:ok, d} -> DateTime.new!(d, ~T[00:00:00], "Etc/UTC")
      _ -> nil
    end
  end

  defp parse_event_time(_), do: nil

  defp minutes_until_event(event_start) do
    diff_seconds = DateTime.diff(event_start, DateTime.utc_now(), :second)
    div(diff_seconds, 60)
  end

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%I:%M %p")
  end
end
