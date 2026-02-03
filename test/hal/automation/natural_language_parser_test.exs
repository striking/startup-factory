defmodule HAL.Automation.NaturalLanguageParserTest do
  use ExUnit.Case, async: true

  alias HAL.Automation.NaturalLanguageParser

  describe "parse/1 - recurring patterns" do
    test "parses 'every morning at 9am'" do
      assert {:recurring, "0 9 * * *"} = NaturalLanguageParser.parse("every morning at 9am")
    end

    test "parses 'every morning at 9:30am'" do
      assert {:recurring, "30 9 * * *"} = NaturalLanguageParser.parse("every morning at 9:30am")
    end

    test "parses 'every morning' (default 9am)" do
      assert {:recurring, "0 9 * * *"} = NaturalLanguageParser.parse("every morning")
    end

    test "parses 'every evening at 6pm'" do
      assert {:recurring, "0 18 * * *"} = NaturalLanguageParser.parse("every evening at 6pm")
    end

    test "parses 'every evening' (default 6pm)" do
      assert {:recurring, "0 18 * * *"} = NaturalLanguageParser.parse("every evening")
    end

    test "parses 'every day at 3pm'" do
      assert {:recurring, "0 15 * * *"} = NaturalLanguageParser.parse("every day at 3pm")
    end

    test "parses 'daily at 8am'" do
      assert {:recurring, "0 8 * * *"} = NaturalLanguageParser.parse("daily at 8am")
    end

    test "parses 'every weekday at 9am'" do
      assert {:recurring, "0 9 * * 1-5"} = NaturalLanguageParser.parse("every weekday at 9am")
    end

    test "parses 'every weekday' (default 9am)" do
      assert {:recurring, "0 9 * * 1-5"} = NaturalLanguageParser.parse("every weekday")
    end

    test "parses 'every weekend at 10am'" do
      assert {:recurring, "0 10 * * 0,6"} = NaturalLanguageParser.parse("every weekend at 10am")
    end

    test "parses 'every weekend' (default 10am)" do
      assert {:recurring, "0 10 * * 0,6"} = NaturalLanguageParser.parse("every weekend")
    end

    test "parses 'every Monday'" do
      assert {:recurring, "0 0 * * 1"} = NaturalLanguageParser.parse("every Monday")
    end

    test "parses 'every Monday at 10am'" do
      assert {:recurring, "0 10 * * 1"} = NaturalLanguageParser.parse("every Monday at 10am")
    end

    test "parses 'every friday at 5pm'" do
      assert {:recurring, "0 17 * * 5"} = NaturalLanguageParser.parse("every friday at 5pm")
    end

    test "parses 'weekly on Friday at 5pm'" do
      assert {:recurring, "0 17 * * 5"} = NaturalLanguageParser.parse("weekly on Friday at 5pm")
    end

    test "parses 'hourly'" do
      assert {:recurring, "0 * * * *"} = NaturalLanguageParser.parse("hourly")
    end

    test "parses 'every hour'" do
      assert {:recurring, "0 * * * *"} = NaturalLanguageParser.parse("every hour")
    end

    test "parses 'every 30 minutes'" do
      assert {:recurring, "*/30 * * * *"} = NaturalLanguageParser.parse("every 30 minutes")
    end

    test "parses 'every 15 minutes'" do
      assert {:recurring, "*/15 * * * *"} = NaturalLanguageParser.parse("every 15 minutes")
    end

    test "parses 'every 2 hours'" do
      assert {:recurring, "0 */2 * * *"} = NaturalLanguageParser.parse("every 2 hours")
    end

    test "handles case insensitivity" do
      assert {:recurring, "0 9 * * *"} = NaturalLanguageParser.parse("EVERY MORNING AT 9AM")
      assert {:recurring, "0 17 * * 5"} = NaturalLanguageParser.parse("Every Friday At 5PM")
    end
  end

  describe "parse/1 - one-time patterns with 'in'" do
    test "parses 'in 2 hours'" do
      assert {:in, 7200} = NaturalLanguageParser.parse("in 2 hours")
    end

    test "parses 'in 30 minutes'" do
      assert {:in, 1800} = NaturalLanguageParser.parse("in 30 minutes")
    end

    test "parses 'in 1 hour'" do
      assert {:in, 3600} = NaturalLanguageParser.parse("in 1 hour")
    end

    test "parses 'in 5 seconds'" do
      assert {:in, 5} = NaturalLanguageParser.parse("in 5 seconds")
    end

    test "parses 'in 1 day'" do
      assert {:in, 86400} = NaturalLanguageParser.parse("in 1 day")
    end

    test "parses 'in 2 weeks'" do
      assert {:in, 1_209_600} = NaturalLanguageParser.parse("in 2 weeks")
    end
  end

  describe "parse/1 - one-time patterns with specific times" do
    test "parses 'tomorrow at 3pm'" do
      {:once, datetime} = NaturalLanguageParser.parse("tomorrow at 3pm")
      assert datetime.hour == 15
      assert datetime.minute == 0
      # Should be tomorrow
      tomorrow = DateTime.utc_now() |> DateTime.add(1, :day) |> DateTime.to_date()
      assert DateTime.to_date(datetime) == tomorrow
    end

    test "parses 'tomorrow' (default 9am)" do
      {:once, datetime} = NaturalLanguageParser.parse("tomorrow")
      assert datetime.hour == 9
      assert datetime.minute == 0
    end

    test "parses 'next Monday'" do
      {:once, datetime} = NaturalLanguageParser.parse("next Monday")
      # The parser uses :sunday mode (Sunday=0, Monday=1)
      # Date.day_of_week with :sunday returns Sunday=0, Monday=1, etc.
      day = Date.day_of_week(DateTime.to_date(datetime), :sunday)
      assert day == 1, "Expected Monday (1 in :sunday mode) but got #{day}"
    end

    test "parses 'next Friday at 2pm'" do
      {:once, datetime} = NaturalLanguageParser.parse("next Friday at 2pm")
      day = Date.day_of_week(DateTime.to_date(datetime), :sunday)
      assert day == 5, "Expected Friday (5 in :sunday mode) but got #{day}"
      assert datetime.hour == 14
      assert datetime.minute == 0
    end

    test "parses 'at 9am' for today or tomorrow" do
      {:once, datetime} = NaturalLanguageParser.parse("at 9am")
      now = DateTime.utc_now()

      # Should be at 9am
      assert datetime.hour == 9
      assert datetime.minute == 0

      # Should be today if before 9am, tomorrow if after
      if now.hour < 9 do
        assert DateTime.to_date(datetime) == DateTime.to_date(now)
      else
        tomorrow = DateTime.add(now, 1, :day) |> DateTime.to_date()
        assert DateTime.to_date(datetime) == tomorrow
      end
    end
  end

  describe "parse/1 - time format variations" do
    test "parses 12-hour format with am/pm" do
      assert {:recurring, "0 9 * * *"} = NaturalLanguageParser.parse("daily at 9am")
      assert {:recurring, "0 21 * * *"} = NaturalLanguageParser.parse("daily at 9pm")
      assert {:recurring, "0 12 * * *"} = NaturalLanguageParser.parse("daily at 12pm")
      assert {:recurring, "0 0 * * *"} = NaturalLanguageParser.parse("daily at 12am")
    end

    test "parses time with minutes" do
      assert {:recurring, "30 9 * * *"} = NaturalLanguageParser.parse("daily at 9:30am")
      assert {:recurring, "45 14 * * *"} = NaturalLanguageParser.parse("daily at 2:45pm")
    end

    test "parses 24-hour format" do
      assert {:recurring, "0 15 * * *"} = NaturalLanguageParser.parse("daily at 15:00")
      assert {:recurring, "30 9 * * *"} = NaturalLanguageParser.parse("daily at 9:30")
    end
  end

  describe "parse/1 - error cases" do
    test "returns error for unparseable expressions" do
      assert {:error, _} = NaturalLanguageParser.parse("gibberish nonsense")
      assert {:error, _} = NaturalLanguageParser.parse("at invalid time")
    end
  end

  describe "validate_cron/1" do
    test "validates correct cron expressions" do
      assert {:ok, _} = NaturalLanguageParser.validate_cron("0 9 * * *")
      assert {:ok, _} = NaturalLanguageParser.validate_cron("*/30 * * * *")
      assert {:ok, _} = NaturalLanguageParser.validate_cron("0 9 * * 1-5")
      assert {:ok, _} = NaturalLanguageParser.validate_cron("0 9 * * 0,6")
      assert {:ok, _} = NaturalLanguageParser.validate_cron("0 */2 * * *")
    end

    test "returns error for invalid cron expressions" do
      assert {:error, _} = NaturalLanguageParser.validate_cron("invalid")
      assert {:error, _} = NaturalLanguageParser.validate_cron("* * * *")
      assert {:error, _} = NaturalLanguageParser.validate_cron("60 * * * *")
      assert {:error, _} = NaturalLanguageParser.validate_cron("* 24 * * *")
    end

    test "validates field ranges" do
      # Minute: 0-59
      assert {:ok, _} = NaturalLanguageParser.validate_cron("59 * * * *")
      assert {:error, _} = NaturalLanguageParser.validate_cron("60 * * * *")

      # Hour: 0-23
      assert {:ok, _} = NaturalLanguageParser.validate_cron("0 23 * * *")
      assert {:error, _} = NaturalLanguageParser.validate_cron("0 24 * * *")

      # Day: 1-31
      assert {:ok, _} = NaturalLanguageParser.validate_cron("0 0 31 * *")
      assert {:error, _} = NaturalLanguageParser.validate_cron("0 0 32 * *")

      # Month: 1-12
      assert {:ok, _} = NaturalLanguageParser.validate_cron("0 0 1 12 *")
      assert {:error, _} = NaturalLanguageParser.validate_cron("0 0 1 13 *")

      # Weekday: 0-6
      assert {:ok, _} = NaturalLanguageParser.validate_cron("0 0 * * 6")
      assert {:error, _} = NaturalLanguageParser.validate_cron("0 0 * * 7")
    end
  end

  describe "next_occurrence/1" do
    test "calculates next occurrence for simple cron" do
      assert {:ok, datetime} = NaturalLanguageParser.next_occurrence("0 9 * * *")
      assert datetime.hour == 9
      assert datetime.minute == 0
      assert datetime.second == 0
    end

    test "calculates next occurrence for step expression" do
      assert {:ok, datetime} = NaturalLanguageParser.next_occurrence("*/30 * * * *")
      assert rem(datetime.minute, 30) == 0
    end

    test "returns future datetime" do
      now = DateTime.utc_now()
      assert {:ok, datetime} = NaturalLanguageParser.next_occurrence("0 * * * *")
      assert DateTime.compare(datetime, now) == :gt
    end

    test "returns error for invalid cron" do
      assert {:error, _} = NaturalLanguageParser.next_occurrence("invalid cron")
    end
  end
end
