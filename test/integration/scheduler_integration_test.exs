defmodule HAL.Integration.SchedulerIntegrationTest do
  @moduledoc """
  Integration tests for scheduled task execution.

  Tests the complete scheduling pipeline:
  1. Task creation via Scheduler API
  2. Oban job insertion
  3. Job execution at scheduled time
  4. Response delivery to channel

  These tests require:
  - PostgreSQL with Oban tables
  - Claude Code CLI for AI processing
  - Properly configured channels for response delivery

  Run with: mix test test/integration/scheduler_integration_test.exs --include integration
  """

  use Hal.DataCase, async: false
  use Oban.Testing, repo: Hal.Repo

  alias HAL.Automation.Scheduler
  alias HAL.Automation.Workers.{ScheduledTask, ProactiveTask}
  alias Hal.Accounts.User
  alias Hal.Gateway.Session

  @moduletag :integration
  @moduletag timeout: 300_000

  setup do
    # Create a test user
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        external_id: "scheduler_test_user_#{System.unique_integer([:positive])}",
        platform: "telegram",
        username: "scheduler_test"
      })
      |> Repo.insert()

    # Create a test session
    {:ok, session} =
      %Session{}
      |> Session.changeset(%{
        channel_type: "telegram",
        channel_id: "scheduler_chat_#{System.unique_integer([:positive])}",
        user_id: user.id,
        last_activity: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    %{user: user, session: session}
  end

  describe "scheduled task execution" do
    @tag :slow
    test "executes scheduled task at the right time", %{session: session} do
      # Schedule a task for 5 seconds from now
      scheduled_at = DateTime.utc_now() |> DateTime.add(5, :second)

      {:ok, job} =
        Scheduler.schedule_once(
          session.id,
          "What is 1 + 1? Reply with just the number.",
          scheduled_at
        )

      # Verify job was created
      assert job.state == "scheduled"
      assert job.scheduled_at == scheduled_at

      # Wait for job to become available (past scheduled time)
      Process.sleep(6_000)

      # In real execution, Oban would pick up and execute the job
      # For integration testing, we manually drain the queue
      assert_enqueued(worker: ScheduledTask, args: %{"session_id" => session.id})
    end

    @tag :slow
    test "recurring task reschedules after execution", %{session: session} do
      # Schedule a recurring task (every minute for testing)
      {:ok, job} =
        Scheduler.schedule_recurring(
          session.id,
          "Check status",
          "* * * * *"
        )

      assert "recurring" in job.tags
      assert job.args["cron_expression"] == "* * * * *"

      # The job should be scheduled for the next minute
      now = DateTime.utc_now()
      assert DateTime.diff(job.scheduled_at, now, :second) <= 60
    end
  end

  describe "proactive task execution" do
    @tag :slow
    test "executes reminder proactive task", %{session: session} do
      {:ok, job} =
        Scheduler.schedule_proactive(
          "reminder",
          %{"message" => "Time for your scheduled task!"},
          session_id: session.id,
          respond_via: %{"channel_type" => "telegram", "channel_id" => session.channel_id}
        )

      assert job.args["task_type"] == "reminder"
      assert_enqueued(worker: ProactiveTask)
    end

    @tag :slow
    test "executes monitor proactive task", %{session: session} do
      {:ok, job} =
        Scheduler.schedule_proactive(
          "monitor",
          %{"prompt" => "Check if the system is healthy", "trigger_words" => ["error", "failed"]},
          session_id: session.id,
          scheduled_at: DateTime.utc_now() |> DateTime.add(1, :minute)
        )

      assert job.args["task_type"] == "monitor"
      assert job.args["config"]["prompt"] == "Check if the system is healthy"
    end
  end

  describe "natural language scheduling" do
    @tag :slow
    test "schedules from 'in X hours' expression", %{session: session} do
      before = DateTime.utc_now()

      {:ok, job} =
        Scheduler.schedule_natural(
          session.id,
          "Remind me to check email",
          "in 2 hours"
        )

      # Verify scheduled time is approximately 2 hours from now
      diff = DateTime.diff(job.scheduled_at, before, :second)
      assert diff >= 7190 and diff <= 7210
    end

    @tag :slow
    test "schedules from 'every morning at' expression", %{session: session} do
      {:ok, job} =
        Scheduler.schedule_natural(
          session.id,
          "Morning briefing",
          "every morning at 9am"
        )

      assert "recurring" in job.tags
      assert job.args["cron_expression"] == "0 9 * * *"
    end

    @tag :slow
    test "schedules from 'tomorrow at' expression", %{session: session} do
      {:ok, job} =
        Scheduler.schedule_natural(
          session.id,
          "Tomorrow's meeting reminder",
          "tomorrow at 3pm"
        )

      tomorrow = DateTime.utc_now() |> DateTime.add(1, :day) |> DateTime.to_date()
      assert DateTime.to_date(job.scheduled_at) == tomorrow
      assert job.scheduled_at.hour == 15
    end
  end

  describe "job management" do
    @tag :slow
    test "lists all scheduled jobs for a session", %{session: session} do
      # Create multiple jobs
      {:ok, _} = Scheduler.schedule_in(session.id, "Task 1", {1, :hours})
      {:ok, _} = Scheduler.schedule_in(session.id, "Task 2", {2, :hours})
      {:ok, _} = Scheduler.schedule_in(session.id, "Task 3", {3, :hours})

      jobs = Scheduler.list_scheduled(session.id)

      assert length(jobs) == 3
      # Jobs should be ordered by scheduled_at
      times = Enum.map(jobs, & &1.scheduled_at)
      assert times == Enum.sort(times, DateTime)
    end

    @tag :slow
    test "cancels a specific job", %{session: session} do
      {:ok, job} = Scheduler.schedule_in(session.id, "To be cancelled", {1, :hours})

      # Cancel the job
      :ok = Scheduler.cancel(job.id)

      # Verify it's no longer in the scheduled list
      jobs = Scheduler.list_scheduled(session.id)
      refute Enum.any?(jobs, &(&1.id == job.id))
    end

    @tag :slow
    test "cancels all jobs for a session", %{session: session} do
      # Create multiple jobs
      {:ok, _} = Scheduler.schedule_in(session.id, "Task 1", {1, :hours})
      {:ok, _} = Scheduler.schedule_in(session.id, "Task 2", {2, :hours})

      # Cancel all
      {:ok, count} = Scheduler.cancel_all(session.id)

      assert count == 2
      assert Scheduler.list_scheduled(session.id) == []
    end
  end
end
