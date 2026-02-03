defmodule HAL.Automation.NaturalLanguageParser do
  @moduledoc """
  Parses natural language time expressions into cron expressions or DateTime values.

  This module handles common natural language patterns for scheduling:

  ## Recurring Patterns

    * "every morning at 9am" -> "0 9 * * *"
    * "every day at 3pm" -> "0 15 * * *"
    * "every Monday" -> "0 0 * * 1"
    * "every weekday at 8am" -> "0 8 * * 1-5"
    * "every hour" -> "0 * * * *"
    * "every 30 minutes" -> "*/30 * * * *"
    * "weekly on Friday at 5pm" -> "0 17 * * 5"

  ## One-time Patterns

    * "in 2 hours" -> DateTime 2 hours from now
    * "in 30 minutes" -> DateTime 30 minutes from now
    * "tomorrow at 3pm" -> DateTime tomorrow at 15:00
    * "next Monday" -> DateTime of next Monday at 00:00
    * "at 9am" -> DateTime today at 9am (or tomorrow if past)

  ## Return Types

    * `{:recurring, cron_expression}` - For repeating schedules
    * `{:once, datetime}` - For one-time schedules at a specific time
    * `{:in, seconds}` - For relative schedules (e.g., "in 2 hours")
    * `{:error, reason}` - When parsing fails

  """

  @type parse_result ::
          {:recurring, String.t()}
          | {:once, DateTime.t()}
          | {:in, integer()}
          | {:error, String.t()}

  @days_of_week %{
    "sunday" => 0,
    "sun" => 0,
    "monday" => 1,
    "mon" => 1,
    "tuesday" => 2,
    "tue" => 2,
    "wednesday" => 3,
    "wed" => 3,
    "thursday" => 4,
    "thu" => 4,
    "friday" => 5,
    "fri" => 5,
    "saturday" => 6,
    "sat" => 6
  }

  @doc """
  Parses a natural language time expression.

  ## Examples

      iex> NaturalLanguageParser.parse("every morning at 9am")
      {:recurring, "0 9 * * *"}

      iex> NaturalLanguageParser.parse("in 2 hours")
      {:in, 7200}

      iex> NaturalLanguageParser.parse("tomorrow at 3pm")
      {:once, ~U[2026-01-29 15:00:00Z]}

  """
  @spec parse(String.t()) :: parse_result()
  def parse(expression) when is_binary(expression) do
    expression
    |> String.downcase()
    |> String.trim()
    |> do_parse()
  end

  # Pattern: "every morning at Xam/pm"
  defp do_parse("every morning at " <> rest) do
    case parse_time(rest) do
      {:ok, hour, minute} -> {:recurring, "#{minute} #{hour} * * *"}
      :error -> {:error, "Could not parse time: #{rest}"}
    end
  end

  # Pattern: "every morning" (default 9am)
  defp do_parse("every morning") do
    {:recurring, "0 9 * * *"}
  end

  # Pattern: "every evening at Xpm"
  defp do_parse("every evening at " <> rest) do
    case parse_time(rest) do
      {:ok, hour, minute} -> {:recurring, "#{minute} #{hour} * * *"}
      :error -> {:error, "Could not parse time: #{rest}"}
    end
  end

  # Pattern: "every evening" (default 6pm)
  defp do_parse("every evening") do
    {:recurring, "0 18 * * *"}
  end

  # Pattern: "every day at X"
  defp do_parse("every day at " <> rest) do
    case parse_time(rest) do
      {:ok, hour, minute} -> {:recurring, "#{minute} #{hour} * * *"}
      :error -> {:error, "Could not parse time: #{rest}"}
    end
  end

  # Pattern: "daily at X"
  defp do_parse("daily at " <> rest) do
    case parse_time(rest) do
      {:ok, hour, minute} -> {:recurring, "#{minute} #{hour} * * *"}
      :error -> {:error, "Could not parse time: #{rest}"}
    end
  end

  # Pattern: "every weekday at X"
  defp do_parse("every weekday at " <> rest) do
    case parse_time(rest) do
      {:ok, hour, minute} -> {:recurring, "#{minute} #{hour} * * 1-5"}
      :error -> {:error, "Could not parse time: #{rest}"}
    end
  end

  # Pattern: "every weekday" (default 9am)
  defp do_parse("every weekday") do
    {:recurring, "0 9 * * 1-5"}
  end

  # Pattern: "every weekend at X"
  defp do_parse("every weekend at " <> rest) do
    case parse_time(rest) do
      {:ok, hour, minute} -> {:recurring, "#{minute} #{hour} * * 0,6"}
      :error -> {:error, "Could not parse time: #{rest}"}
    end
  end

  # Pattern: "every weekend"
  defp do_parse("every weekend") do
    {:recurring, "0 10 * * 0,6"}
  end

  # Pattern: "every hour" (must be before generic "every " pattern)
  defp do_parse("every hour") do
    {:recurring, "0 * * * *"}
  end

  # Pattern: "every [day] at X"
  defp do_parse("every " <> rest) do
    parse_every_day_pattern(rest)
  end

  # Pattern: "weekly on [day] at X"
  defp do_parse("weekly on " <> rest) do
    parse_weekly_pattern(rest)
  end

  # Pattern: "in X hours/minutes/seconds"
  defp do_parse("in " <> rest) do
    parse_duration(rest)
  end

  # Pattern: "tomorrow at X"
  defp do_parse("tomorrow at " <> rest) do
    case parse_time(rest) do
      {:ok, hour, minute} ->
        %DateTime{} =
          tomorrow =
          DateTime.utc_now()
          |> DateTime.add(1, :day)
          |> DateTime.truncate(:second)

        scheduled_at = %{tomorrow | hour: hour, minute: minute, second: 0}

        {:once, scheduled_at}

      :error ->
        {:error, "Could not parse time: #{rest}"}
    end
  end

  # Pattern: "tomorrow" (default 9am)
  defp do_parse("tomorrow") do
    %DateTime{} =
      tomorrow =
      DateTime.utc_now()
      |> DateTime.add(1, :day)
      |> DateTime.truncate(:second)

    scheduled_at = %{tomorrow | hour: 9, minute: 0, second: 0}
    {:once, scheduled_at}
  end

  # Pattern: "next [day]" or "next [day] at X"
  defp do_parse("next " <> rest) do
    parse_next_day_pattern(rest)
  end

  # Pattern: "at X" (today or tomorrow if past)
  defp do_parse("at " <> rest) do
    case parse_time(rest) do
      {:ok, hour, minute} ->
        %DateTime{} = now = DateTime.utc_now()

        today =
          %{now | hour: hour, minute: minute, second: 0}
          |> DateTime.truncate(:second)

        # If the time has passed today, schedule for tomorrow
        scheduled_at =
          if DateTime.compare(today, now) == :lt do
            DateTime.add(today, 1, :day)
          else
            today
          end

        {:once, scheduled_at}

      :error ->
        {:error, "Could not parse time: #{rest}"}
    end
  end

  # Pattern: "hourly"
  defp do_parse("hourly") do
    {:recurring, "0 * * * *"}
  end

  # Pattern: "every X minutes" (catch-all for remaining patterns)
  defp do_parse(expression) do
    cond do
      String.contains?(expression, "minute") ->
        parse_minute_interval(expression)

      String.contains?(expression, "hour") ->
        parse_hour_interval(expression)

      true ->
        {:error, "Could not parse expression: #{expression}"}
    end
  end

  # Parse "every [day] at X" or "every [day]"
  defp parse_every_day_pattern(rest) do
    # Try to match "day at time" or just "day"
    parts = String.split(rest, " at ", parts: 2)

    case parts do
      [day_str, time_str] ->
        case {Map.get(@days_of_week, String.downcase(day_str)), parse_time(time_str)} do
          {nil, _} ->
            # Maybe it's not a day, try other patterns
            parse_interval_pattern(rest)

          {day_num, {:ok, hour, minute}} ->
            {:recurring, "#{minute} #{hour} * * #{day_num}"}

          {_, :error} ->
            {:error, "Could not parse time: #{time_str}"}
        end

      [day_str] ->
        case Map.get(@days_of_week, String.downcase(day_str)) do
          nil ->
            # Maybe it's an interval pattern
            parse_interval_pattern(rest)

          day_num ->
            {:recurring, "0 0 * * #{day_num}"}
        end
    end
  end

  # Parse "weekly on [day] at X"
  defp parse_weekly_pattern(rest) do
    parts = String.split(rest, " at ", parts: 2)

    case parts do
      [day_str, time_str] ->
        case {Map.get(@days_of_week, String.downcase(day_str)), parse_time(time_str)} do
          {nil, _} ->
            {:error, "Unknown day: #{day_str}"}

          {day_num, {:ok, hour, minute}} ->
            {:recurring, "#{minute} #{hour} * * #{day_num}"}

          {_, :error} ->
            {:error, "Could not parse time: #{time_str}"}
        end

      [day_str] ->
        case Map.get(@days_of_week, String.downcase(day_str)) do
          nil -> {:error, "Unknown day: #{day_str}"}
          day_num -> {:recurring, "0 0 * * #{day_num}"}
        end
    end
  end

  # Parse "next monday", "next monday at 3pm"
  defp parse_next_day_pattern(rest) do
    parts = String.split(rest, " at ", parts: 2)

    case parts do
      [day_str, time_str] ->
        case {Map.get(@days_of_week, String.downcase(day_str)), parse_time(time_str)} do
          {nil, _} ->
            {:error, "Unknown day: #{day_str}"}

          {day_num, {:ok, hour, minute}} ->
            scheduled_at = next_weekday(day_num, hour, minute)
            {:once, scheduled_at}

          {_, :error} ->
            {:error, "Could not parse time: #{time_str}"}
        end

      [day_str] ->
        case Map.get(@days_of_week, String.downcase(day_str)) do
          nil ->
            {:error, "Unknown day: #{day_str}"}

          day_num ->
            scheduled_at = next_weekday(day_num, 0, 0)
            {:once, scheduled_at}
        end
    end
  end

  # Parse interval patterns like "30 minutes" or "2 hours"
  defp parse_interval_pattern(expression) do
    cond do
      String.contains?(expression, "minute") ->
        parse_minute_interval(expression)

      String.contains?(expression, "hour") ->
        parse_hour_interval(expression)

      true ->
        {:error, "Could not parse interval: #{expression}"}
    end
  end

  # Parse "X minutes" or "every X minutes"
  defp parse_minute_interval(expression) do
    case Regex.run(~r/(\d+)\s*minute/, expression) do
      [_, minutes_str] ->
        minutes = String.to_integer(minutes_str)

        if minutes > 0 and minutes < 60 do
          {:recurring, "*/#{minutes} * * * *"}
        else
          {:recurring, "0 * * * *"}
        end

      nil ->
        {:error, "Could not parse minute interval: #{expression}"}
    end
  end

  # Parse "X hours" or "every X hours"
  defp parse_hour_interval(expression) do
    case Regex.run(~r/(\d+)\s*hour/, expression) do
      [_, hours_str] ->
        hours = String.to_integer(hours_str)

        if hours > 0 and hours < 24 do
          {:recurring, "0 */#{hours} * * *"}
        else
          {:recurring, "0 * * * *"}
        end

      nil ->
        {:error, "Could not parse hour interval: #{expression}"}
    end
  end

  # Parse duration like "2 hours", "30 minutes", "5 seconds"
  defp parse_duration(rest) do
    rest = String.trim(rest)

    cond do
      String.contains?(rest, "second") ->
        case Regex.run(~r/(\d+)\s*second/, rest) do
          [_, seconds_str] -> {:in, String.to_integer(seconds_str)}
          nil -> {:error, "Could not parse seconds: #{rest}"}
        end

      String.contains?(rest, "minute") ->
        case Regex.run(~r/(\d+)\s*minute/, rest) do
          [_, minutes_str] -> {:in, String.to_integer(minutes_str) * 60}
          nil -> {:error, "Could not parse minutes: #{rest}"}
        end

      String.contains?(rest, "hour") ->
        case Regex.run(~r/(\d+)\s*hour/, rest) do
          [_, hours_str] -> {:in, String.to_integer(hours_str) * 3600}
          nil -> {:error, "Could not parse hours: #{rest}"}
        end

      String.contains?(rest, "day") ->
        case Regex.run(~r/(\d+)\s*day/, rest) do
          [_, days_str] -> {:in, String.to_integer(days_str) * 86400}
          nil -> {:error, "Could not parse days: #{rest}"}
        end

      String.contains?(rest, "week") ->
        case Regex.run(~r/(\d+)\s*week/, rest) do
          [_, weeks_str] -> {:in, String.to_integer(weeks_str) * 604_800}
          nil -> {:error, "Could not parse weeks: #{rest}"}
        end

      true ->
        {:error, "Could not parse duration: #{rest}"}
    end
  end

  # Parse time strings like "9am", "9:30am", "15:00", "3pm"
  defp parse_time(time_str) do
    time_str = String.trim(time_str)

    cond do
      # Format: "9am" or "9pm"
      Regex.match?(~r/^(\d{1,2})(am|pm)$/i, time_str) ->
        case Regex.run(~r/^(\d{1,2})(am|pm)$/i, time_str) do
          [_, hour_str, period] ->
            hour = String.to_integer(hour_str)
            hour = convert_to_24h(hour, String.downcase(period))
            {:ok, hour, 0}

          nil ->
            :error
        end

      # Format: "9:30am" or "9:30pm"
      Regex.match?(~r/^(\d{1,2}):(\d{2})(am|pm)$/i, time_str) ->
        case Regex.run(~r/^(\d{1,2}):(\d{2})(am|pm)$/i, time_str) do
          [_, hour_str, minute_str, period] ->
            hour = String.to_integer(hour_str)
            minute = String.to_integer(minute_str)
            hour = convert_to_24h(hour, String.downcase(period))
            {:ok, hour, minute}

          nil ->
            :error
        end

      # Format: "15:00" or "15:30" (24-hour)
      Regex.match?(~r/^(\d{1,2}):(\d{2})$/, time_str) ->
        case Regex.run(~r/^(\d{1,2}):(\d{2})$/, time_str) do
          [_, hour_str, minute_str] ->
            hour = String.to_integer(hour_str)
            minute = String.to_integer(minute_str)

            if hour >= 0 and hour < 24 and minute >= 0 and minute < 60 do
              {:ok, hour, minute}
            else
              :error
            end

          nil ->
            :error
        end

      # Format: just "9" (assumes am for morning hours, pm for afternoon)
      Regex.match?(~r/^(\d{1,2})$/, time_str) ->
        case Regex.run(~r/^(\d{1,2})$/, time_str) do
          [_, hour_str] ->
            hour = String.to_integer(hour_str)
            {:ok, hour, 0}

          nil ->
            :error
        end

      true ->
        :error
    end
  end

  defp convert_to_24h(hour, "am") when hour == 12, do: 0
  defp convert_to_24h(hour, "am"), do: hour
  defp convert_to_24h(hour, "pm") when hour == 12, do: 12
  defp convert_to_24h(hour, "pm"), do: hour + 12

  # Calculate the next occurrence of a specific weekday
  defp next_weekday(target_day, hour, minute) do
    %DateTime{} = now = DateTime.utc_now()
    current_day = Date.day_of_week(DateTime.to_date(now), :sunday)

    days_ahead =
      if target_day > current_day do
        target_day - current_day
      else
        7 - current_day + target_day
      end

    # If it's the same day but the time has passed, go to next week
    days_ahead =
      if days_ahead == 0 do
        target_time = %{now | hour: hour, minute: minute, second: 0}
        if DateTime.compare(target_time, now) == :lt, do: 7, else: 0
      else
        days_ahead
      end

    %DateTime{} = base_dt = DateTime.add(now, days_ahead, :day)

    %{base_dt | hour: hour, minute: minute, second: 0}
    |> DateTime.truncate(:second)
  end

  @doc """
  Validates a cron expression.

  Returns `{:ok, parsed}` if valid, `{:error, reason}` if invalid.

  ## Examples

      iex> NaturalLanguageParser.validate_cron("0 9 * * *")
      {:ok, %{minute: 0, hour: 9, day: "*", month: "*", weekday: "*"}}

      iex> NaturalLanguageParser.validate_cron("invalid")
      {:error, "Invalid cron expression"}

  """
  @spec validate_cron(String.t()) :: {:ok, map()} | {:error, String.t()}
  def validate_cron(cron_expression) do
    parts = String.split(cron_expression, " ")

    if length(parts) != 5 do
      {:error, "Cron expression must have exactly 5 fields"}
    else
      [minute, hour, day, month, weekday] = parts

      with {:ok, min_val} <- validate_cron_field(minute, 0, 59),
           {:ok, hour_val} <- validate_cron_field(hour, 0, 23),
           {:ok, day_val} <- validate_cron_field(day, 1, 31),
           {:ok, month_val} <- validate_cron_field(month, 1, 12),
           {:ok, weekday_val} <- validate_cron_field(weekday, 0, 6) do
        {:ok,
         %{
           minute: min_val,
           hour: hour_val,
           day: day_val,
           month: month_val,
           weekday: weekday_val
         }}
      else
        {:error, field, reason} ->
          {:error, "Invalid #{field}: #{reason}"}
      end
    end
  end

  defp validate_cron_field("*", _min, _max), do: {:ok, "*"}

  defp validate_cron_field(field, min, max) do
    cond do
      # Step value: */5
      String.starts_with?(field, "*/") ->
        case Integer.parse(String.slice(field, 2..-1//1)) do
          {step, ""} when step > 0 -> {:ok, field}
          _ -> {:error, field, "invalid step value"}
        end

      # Range: 1-5
      String.contains?(field, "-") ->
        case String.split(field, "-") do
          [start_str, end_str] ->
            with {start_val, ""} <- Integer.parse(start_str),
                 {end_val, ""} <- Integer.parse(end_str),
                 true <- start_val >= min and end_val <= max and start_val <= end_val do
              {:ok, field}
            else
              _ -> {:error, field, "invalid range"}
            end

          _ ->
            {:error, field, "invalid range format"}
        end

      # List: 1,3,5
      String.contains?(field, ",") ->
        values = String.split(field, ",")

        valid =
          Enum.all?(values, fn v ->
            case Integer.parse(v) do
              {val, ""} -> val >= min and val <= max
              _ -> false
            end
          end)

        if valid, do: {:ok, field}, else: {:error, field, "invalid list values"}

      # Single value
      true ->
        case Integer.parse(field) do
          {val, ""} when val >= min and val <= max -> {:ok, val}
          {_, ""} -> {:error, field, "value out of range (#{min}-#{max})"}
          _ -> {:error, field, "not a valid number"}
        end
    end
  end

  @doc """
  Calculates the next occurrence for a cron expression.

  Returns the DateTime of when the cron job should next run.

  ## Examples

      iex> NaturalLanguageParser.next_occurrence("0 9 * * *")
      {:ok, ~U[2026-01-28 09:00:00Z]}

  """
  @spec next_occurrence(String.t()) :: {:ok, DateTime.t()} | {:error, String.t()}
  def next_occurrence(cron_expression) do
    case validate_cron(cron_expression) do
      {:ok, parsed} ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        next = find_next_match(now, parsed, 0)
        {:ok, next}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_next_match(datetime, _parsed, iterations) when iterations > 1440 do
    # Safety limit: don't search more than 1 day in minutes
    datetime
  end

  defp find_next_match(datetime, parsed, iterations) do
    %DateTime{} = candidate = DateTime.add(datetime, iterations + 1, :minute)
    candidate = %{candidate | second: 0}

    if matches_cron?(candidate, parsed) do
      candidate
    else
      find_next_match(datetime, parsed, iterations + 1)
    end
  end

  defp matches_cron?(datetime, parsed) do
    matches_field?(datetime.minute, parsed.minute) and
      matches_field?(datetime.hour, parsed.hour) and
      matches_field?(datetime.day, parsed.day) and
      matches_field?(datetime.month, parsed.month) and
      matches_field?(Date.day_of_week(DateTime.to_date(datetime), :sunday), parsed.weekday)
  end

  defp matches_field?(_value, "*"), do: true
  defp matches_field?(value, value), do: true

  defp matches_field?(value, field) when is_binary(field) do
    cond do
      String.starts_with?(field, "*/") ->
        step = String.slice(field, 2..-1//1) |> String.to_integer()
        rem(value, step) == 0

      String.contains?(field, "-") ->
        [start_str, end_str] = String.split(field, "-")
        start_val = String.to_integer(start_str)
        end_val = String.to_integer(end_str)
        value >= start_val and value <= end_val

      String.contains?(field, ",") ->
        values = String.split(field, ",") |> Enum.map(&String.to_integer/1)
        value in values

      true ->
        false
    end
  end

  defp matches_field?(_, _), do: false
end
