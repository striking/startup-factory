defmodule HAL.Automation.SchedulerTest do
  use ExUnit.Case, async: true

  alias HAL.Automation.Scheduler

  # Note: Tests that require database operations (Oban.insert, list_scheduled, etc.)
  # need the full application running with Hal.DataCase.
  # These unit tests focus on the logic that doesn't require database access.

  # Ensure module is loaded before checking exports
  setup_all do
    Code.ensure_loaded!(Scheduler)
    :ok
  end

  describe "module exports" do
    test "Scheduler module is defined" do
      assert Code.ensure_loaded?(Scheduler)
    end

    test "schedule_once/3 and schedule_once/4 functions exist" do
      # Function has a default arg, so both arities are exported
      assert function_exported?(Scheduler, :schedule_once, 3)
      assert function_exported?(Scheduler, :schedule_once, 4)
    end

    test "schedule_in/3 and schedule_in/4 functions exist" do
      assert function_exported?(Scheduler, :schedule_in, 3)
      assert function_exported?(Scheduler, :schedule_in, 4)
    end

    test "schedule_recurring/3 and schedule_recurring/4 functions exist" do
      assert function_exported?(Scheduler, :schedule_recurring, 3)
      assert function_exported?(Scheduler, :schedule_recurring, 4)
    end

    test "schedule_natural/3 and schedule_natural/4 functions exist" do
      assert function_exported?(Scheduler, :schedule_natural, 3)
      assert function_exported?(Scheduler, :schedule_natural, 4)
    end

    test "schedule_proactive/2 and schedule_proactive/3 functions exist" do
      assert function_exported?(Scheduler, :schedule_proactive, 2)
      assert function_exported?(Scheduler, :schedule_proactive, 3)
    end

    test "list_scheduled/1 function exists" do
      assert function_exported?(Scheduler, :list_scheduled, 1)
    end

    test "cancel/1 function exists" do
      assert function_exported?(Scheduler, :cancel, 1)
    end

    test "cancel_all/1 function exists" do
      assert function_exported?(Scheduler, :cancel_all, 1)
    end
  end
end

defmodule HAL.Automation.SchedulerIntegrationTest do
  @moduledoc """
  Integration tests for the Scheduler module.
  These tests require the database and Oban to be running.

  Note: These tests are tagged as :integration because Oban's inline testing mode
  executes the job workers immediately, which would call Claude Code CLI.
  Run with: mix test --only integration
  """
  use Hal.DataCase, async: false
  use Oban.Testing, repo: Hal.Repo

  alias HAL.Automation.Scheduler
  alias Hal.Accounts.User
  alias Hal.Gateway.Session

  # Tag all tests in this module as integration tests
  # They will be excluded by default and can be run with: mix test --only integration
  @moduletag :integration

  setup do
    # Create a test user
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        external_id: "test_user_#{System.unique_integer()}",
        platform: "telegram",
        username: "test_user"
      })
      |> Hal.Repo.insert()

    # Create a test session
    {:ok, session} =
      %Session{}
      |> Session.changeset(%{
        channel_type: "telegram",
        channel_id: "test_chat_#{System.unique_integer()}",
        user_id: user.id,
        last_activity: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Hal.Repo.insert()

    %{user: user, session: session}
  end

  describe "schedule_once/4" do
    test "schedules a one-time task at a specific datetime", %{session: session} do
      scheduled_at = DateTime.utc_now() |> DateTime.add(1, :hour)

      assert {:ok, job} =
               Scheduler.schedule_once(
                 session.id,
                 "Test prompt",
                 scheduled_at
               )

      assert job.queue == "scheduled"
      assert job.args["session_id"] == session.id
      assert job.args["prompt"] == "Test prompt"
      assert DateTime.compare(job.scheduled_at, scheduled_at) == :eq
    end

    test "includes respond_via when provided", %{session: session} do
      scheduled_at = DateTime.utc_now() |> DateTime.add(1, :hour)
      respond_via = %{"channel_type" => "telegram", "channel_id" => "123"}

      assert {:ok, job} =
               Scheduler.schedule_once(
                 session.id,
                 "Test prompt",
                 scheduled_at,
                 respond_via: respond_via
               )

      assert job.args["respond_via"] == respond_via
    end

    test "includes metadata when provided", %{session: session} do
      scheduled_at = DateTime.utc_now() |> DateTime.add(1, :hour)
      metadata = %{"task_type" => "reminder"}

      assert {:ok, job} =
               Scheduler.schedule_once(
                 session.id,
                 "Test prompt",
                 scheduled_at,
                 metadata: metadata
               )

      assert job.args["metadata"] == metadata
    end
  end

  describe "schedule_in/4" do
    test "schedules a task after specified seconds", %{session: session} do
      before = DateTime.utc_now()

      assert {:ok, job} = Scheduler.schedule_in(session.id, "Test prompt", 3600)

      # Should be scheduled approximately 1 hour from now
      diff = DateTime.diff(job.scheduled_at, before, :second)
      assert diff >= 3599 and diff <= 3601
    end

    test "schedules a task with duration tuple", %{session: session} do
      before = DateTime.utc_now()

      assert {:ok, job} = Scheduler.schedule_in(session.id, "Test prompt", {2, :hours})

      diff = DateTime.diff(job.scheduled_at, before, :second)
      assert diff >= 7199 and diff <= 7201
    end

    test "supports various time units", %{session: session} do
      assert {:ok, job1} = Scheduler.schedule_in(session.id, "Test", {30, :seconds})
      assert {:ok, job2} = Scheduler.schedule_in(session.id, "Test", {5, :minutes})
      assert {:ok, job3} = Scheduler.schedule_in(session.id, "Test", {1, :days})

      now = DateTime.utc_now()
      assert DateTime.diff(job1.scheduled_at, now, :second) >= 29
      assert DateTime.diff(job2.scheduled_at, now, :second) >= 299
      assert DateTime.diff(job3.scheduled_at, now, :second) >= 86399
    end
  end

  describe "schedule_recurring/4" do
    test "schedules a recurring task with cron expression", %{session: session} do
      assert {:ok, job} =
               Scheduler.schedule_recurring(
                 session.id,
                 "Daily check",
                 "0 9 * * *"
               )

      assert job.queue == "scheduled"
      assert job.args["cron_expression"] == "0 9 * * *"
      assert "recurring" in job.tags
    end

    test "returns error for invalid cron expression", %{session: session} do
      assert {:error, {:invalid_cron, _}} =
               Scheduler.schedule_recurring(
                 session.id,
                 "Test",
                 "invalid cron"
               )
    end

    test "calculates next occurrence correctly", %{session: session} do
      # Schedule for next hour (on the hour)
      assert {:ok, job} =
               Scheduler.schedule_recurring(
                 session.id,
                 "Hourly check",
                 "0 * * * *"
               )

      # Should be scheduled at minute 0
      assert job.scheduled_at.minute == 0
      assert job.scheduled_at.second == 0
    end
  end

  describe "schedule_natural/4" do
    test "schedules recurring from natural language", %{session: session} do
      assert {:ok, job} =
               Scheduler.schedule_natural(
                 session.id,
                 "Morning briefing",
                 "every morning at 9am"
               )

      assert job.args["cron_expression"] == "0 9 * * *"
      assert "recurring" in job.tags
    end

    test "schedules one-time from 'in X' expressions", %{session: session} do
      before = DateTime.utc_now()

      assert {:ok, job} =
               Scheduler.schedule_natural(
                 session.id,
                 "Reminder",
                 "in 2 hours"
               )

      diff = DateTime.diff(job.scheduled_at, before, :second)
      assert diff >= 7199 and diff <= 7201
    end

    test "schedules one-time from 'tomorrow at' expressions", %{session: session} do
      assert {:ok, job} =
               Scheduler.schedule_natural(
                 session.id,
                 "Tomorrow task",
                 "tomorrow at 3pm"
               )

      tomorrow = DateTime.utc_now() |> DateTime.add(1, :day) |> DateTime.to_date()
      assert DateTime.to_date(job.scheduled_at) == tomorrow
      assert job.scheduled_at.hour == 15
    end

    test "returns error for unparseable expressions", %{session: session} do
      assert {:error, {:parse_error, _}} =
               Scheduler.schedule_natural(
                 session.id,
                 "Test",
                 "gibberish nonsense"
               )
    end
  end

  describe "schedule_proactive/3" do
    test "schedules a reminder task" do
      # Note: We don't include respond_via to avoid trying to send messages
      assert {:ok, job} =
               Scheduler.schedule_proactive(
                 "reminder",
                 %{"message" => "Time for standup!"},
                 []
               )

      assert job.queue == "scheduled"
      assert job.args["task_type"] == "reminder"
    end

    test "schedules a monitor task with session", %{session: session} do
      assert {:ok, job} =
               Scheduler.schedule_proactive(
                 "monitor",
                 %{"prompt" => "Check deployment status"},
                 session_id: session.id,
                 scheduled_at: DateTime.utc_now() |> DateTime.add(1, :hour)
               )

      assert job.args["session_id"] == session.id
      assert job.args["task_type"] == "monitor"
    end
  end

  describe "list_scheduled/1" do
    test "lists scheduled jobs for a session", %{session: session} do
      # Schedule a few jobs
      {:ok, _} = Scheduler.schedule_in(session.id, "Task 1", {1, :hours})
      {:ok, _} = Scheduler.schedule_in(session.id, "Task 2", {2, :hours})

      jobs = Scheduler.list_scheduled(session.id)

      assert length(jobs) == 2
      assert Enum.all?(jobs, fn job -> job.args["session_id"] == session.id end)
    end

    test "returns empty list for session with no jobs", %{session: session} do
      jobs = Scheduler.list_scheduled(session.id)
      assert jobs == []
    end
  end

  describe "cancel/1" do
    test "cancels a scheduled job", %{session: session} do
      {:ok, job} = Scheduler.schedule_in(session.id, "To be cancelled", {1, :hours})

      assert :ok = Scheduler.cancel(job.id)

      # Verify job is cancelled (state should be "cancelled" or not in available/scheduled)
      updated_job = Hal.Repo.get(Oban.Job, job.id)
      assert updated_job.state == "cancelled"
    end
  end

  describe "cancel_all/1" do
    test "cancels all scheduled jobs for a session", %{session: session} do
      {:ok, _} = Scheduler.schedule_in(session.id, "Task 1", {1, :hours})
      {:ok, _} = Scheduler.schedule_in(session.id, "Task 2", {2, :hours})
      {:ok, _} = Scheduler.schedule_in(session.id, "Task 3", {3, :hours})

      assert {:ok, 3} = Scheduler.cancel_all(session.id)

      # Verify all jobs are cancelled
      jobs = Scheduler.list_scheduled(session.id)
      assert jobs == []
    end
  end
end
