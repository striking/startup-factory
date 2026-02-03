defmodule HAL.Automation.Workers.ProactiveTaskTest do
  use ExUnit.Case, async: true

  alias HAL.Automation.Workers.ProactiveTask

  describe "new/2" do
    test "creates a job with correct defaults" do
      args = %{"task_type" => "reminder", "config" => %{"message" => "Test"}}

      changeset = ProactiveTask.new(args)

      assert changeset.valid?
      # Queue is stored as string in changeset
      assert changeset.changes.queue in [:scheduled, "scheduled"]
      assert changeset.changes.max_attempts == 3
    end

    test "sets priority to 2" do
      args = %{"task_type" => "reminder"}

      changeset = ProactiveTask.new(args)

      assert changeset.changes.priority == 2
    end
  end

  describe "perform/1 - reminder task" do
    test "executes reminder without session and without respond_via" do
      job = %Oban.Job{
        args: %{
          "task_type" => "reminder",
          "message" => "Test reminder"
        }
      }

      # Should succeed without error (no notification sent without respond_via)
      assert :ok = ProactiveTask.perform(job)
    end

    # Note: Tests that require respond_via would try to send messages
    # via GenServers that aren't started in unit tests.
    # Integration tests with full app would cover those cases.
  end

  describe "perform/1 - maintenance task" do
    test "handles unknown maintenance task" do
      job = %Oban.Job{
        args: %{
          "task_type" => "maintenance",
          "config" => %{"task" => "unknown_task"}
        }
      }

      assert :ok = ProactiveTask.perform(job)
    end
  end

  describe "perform/1 - monitor task" do
    test "skips monitor when no session specified" do
      job = %Oban.Job{
        args: %{
          "task_type" => "monitor",
          "config" => %{"prompt" => "Check something"}
        }
      }

      # Should succeed without error
      assert :ok = ProactiveTask.perform(job)
    end
  end

  describe "perform/1 - suggestion task" do
    test "skips suggestion when no session specified" do
      job = %Oban.Job{
        args: %{
          "task_type" => "suggestion",
          "config" => %{"prompt" => "Generate a suggestion"}
        }
      }

      assert :ok = ProactiveTask.perform(job)
    end
  end

  describe "perform/1 - unknown task type" do
    test "handles unknown task type gracefully" do
      job = %Oban.Job{
        args: %{
          "task_type" => "unknown_type"
        }
      }

      assert :ok = ProactiveTask.perform(job)
    end
  end
end
