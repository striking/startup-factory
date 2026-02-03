defmodule Hal.Tools.Handlers.Calendar do
  @moduledoc """
  Handler for HAL calendar tool operations.

  Uses Google Calendar API when the user has connected their Google account.
  Returns helpful error if not connected.
  """

  require Logger
  alias Hal.Tools.Executor
  alias HAL.Credentials
  alias HAL.Integrations.Calendar, as: CalendarAPI

  @doc """
  Get upcoming calendar events.

  ## Arguments

    * `args` - Map containing:
      * `"start_date"` - Optional start date (ISO 8601)
      * `"end_date"` - Optional end date (ISO 8601)
      * `"limit"` - Optional result limit
    * `opts` - Context options with `:user_id`
  """
  @spec get_events(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def get_events(args, opts) do
    _user_id = Keyword.fetch!(opts, :user_id)

    # Parse dates or use defaults
    time_min = parse_datetime(Map.get(args, "start_date")) || DateTime.utc_now()

    time_max =
      parse_datetime(Map.get(args, "end_date")) || DateTime.add(DateTime.utc_now(), 7, :day)

    limit = Map.get(args, "limit", 10)

    case Credentials.get_google_token() do
      {:ok, access_token} ->
        case CalendarAPI.list_events(access_token,
               time_min: time_min,
               time_max: time_max,
               max_results: limit,
               order_by: "startTime"
             ) do
          {:ok, events} ->
            formatted_events = Enum.map(events, &format_event/1)
            count = length(formatted_events)

            Executor.return_success(
              "Found #{count} #{pluralize("event", count)}",
              %{
                events: formatted_events,
                start_date: DateTime.to_iso8601(time_min),
                end_date: DateTime.to_iso8601(time_max)
              }
            )

          {:error, reason} ->
            Logger.error("Calendar API error: #{inspect(reason)}")
            Executor.return_error("Failed to fetch calendar events", reason)
        end

      {:error, :not_found} ->
        Executor.return_error(
          "Google credentials not configured",
          "Please add Google credentials at ~/.hal/credentials/google.json"
        )

      {:error, :no_refresh_token} ->
        Executor.return_error(
          "Google authentication expired",
          "Please update your Google credentials at ~/.hal/credentials/google.json"
        )

      {:error, reason} ->
        Logger.error("Token error: #{inspect(reason)}")
        Executor.return_error("Authentication error", inspect(reason))
    end
  rescue
    e ->
      Logger.error("Calendar get_events failed: #{Exception.message(e)}")
      Executor.return_error("Calendar get_events failed", Exception.message(e))
  end

  @doc """
  Create a new calendar event.

  ## Arguments

    * `args` - Map containing:
      * `"title"` - Event title
      * `"start_time"` - Start time (ISO 8601)
      * `"end_time"` - End time (ISO 8601)
      * `"description"` - Optional description
      * `"location"` - Optional location
      * `"attendees"` - Optional list of attendee emails
    * `opts` - Context options with `:user_id`
  """
  @spec create_event(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def create_event(args, opts) do
    _user_id = Keyword.fetch!(opts, :user_id)

    title = Map.get(args, "title")
    start_time = Map.get(args, "start_time")
    end_time = Map.get(args, "end_time")

    cond do
      is_nil(title) ->
        Executor.return_error("Missing required argument: title")

      is_nil(start_time) ->
        Executor.return_error("Missing required argument: start_time")

      is_nil(end_time) ->
        Executor.return_error("Missing required argument: end_time")

      true ->
        case Credentials.get_google_token() do
          {:ok, access_token} ->
            event_data = build_event_data(args)

            case CalendarAPI.create_event(access_token, event_data) do
              {:ok, event} ->
                Executor.return_success(
                  "Event '#{title}' created successfully",
                  format_event(event)
                )

              {:error, reason} ->
                Logger.error("Calendar create error: #{inspect(reason)}")
                Executor.return_error("Failed to create event", reason)
            end

          {:error, :not_found} ->
            Executor.return_error(
              "Google credentials not configured",
              "Please add Google credentials at ~/.hal/credentials/google.json"
            )

          {:error, :no_refresh_token} ->
            Executor.return_error(
              "Google authentication expired",
              "Please update your Google credentials at ~/.hal/credentials/google.json"
            )

          {:error, reason} ->
            Logger.error("Token error: #{inspect(reason)}")
            Executor.return_error("Authentication error", inspect(reason))
        end
    end
  rescue
    e ->
      Logger.error("Calendar create_event failed: #{Exception.message(e)}")
      Executor.return_error("Calendar create_event failed", Exception.message(e))
  end

  # Private helpers

  defp format_event(event) do
    %{
      id: event["id"],
      title: event["summary"],
      description: event["description"],
      location: event["location"],
      start_time: get_event_time(event["start"]),
      end_time: get_event_time(event["end"]),
      attendees: format_attendees(event["attendees"]),
      html_link: event["htmlLink"],
      status: event["status"]
    }
  end

  defp get_event_time(nil), do: nil
  defp get_event_time(%{"dateTime" => dt}), do: dt
  defp get_event_time(%{"date" => d}), do: d
  defp get_event_time(_), do: nil

  defp format_attendees(nil), do: []

  defp format_attendees(attendees) do
    Enum.map(attendees, fn a ->
      %{
        email: a["email"],
        name: a["displayName"],
        response_status: a["responseStatus"]
      }
    end)
  end

  defp build_event_data(args) do
    data = %{
      "summary" => Map.get(args, "title"),
      "start" => %{"dateTime" => Map.get(args, "start_time")},
      "end" => %{"dateTime" => Map.get(args, "end_time")}
    }

    data =
      if desc = Map.get(args, "description"), do: Map.put(data, "description", desc), else: data

    data = if loc = Map.get(args, "location"), do: Map.put(data, "location", loc), else: data

    if attendees = Map.get(args, "attendees") do
      formatted_attendees = Enum.map(attendees, fn email -> %{"email" => email} end)
      Map.put(data, "attendees", formatted_attendees)
    else
      data
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} ->
        dt

      _ ->
        # Try parsing as date only
        case Date.from_iso8601(str) do
          {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
          _ -> nil
        end
    end
  end

  defp pluralize(word, 1), do: word
  defp pluralize(word, _), do: "#{word}s"
end
