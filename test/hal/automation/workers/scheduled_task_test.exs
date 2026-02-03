defmodule HAL.Automation.Workers.ScheduledTaskTest do
  use ExUnit.Case, async: true

  alias HAL.Automation.Workers.ScheduledTask

  describe "new/2" do
    test "creates a job with correct defaults" do
      args = %{"session_id" => "test-uuid", "prompt" => "Test prompt"}

      changeset = ScheduledTask.new(args)

      assert changeset.valid?
      # Queue can be atom or string depending on Oban version
      assert changeset.changes.queue in [:scheduled, "scheduled"]
      assert changeset.changes.max_attempts == 3
    end

    test "accepts scheduled_at option" do
      args = %{"session_id" => "test-uuid", "prompt" => "Test prompt"}
      scheduled_at = DateTime.utc_now() |> DateTime.add(1, :hour)

      changeset = ScheduledTask.new(args, scheduled_at: scheduled_at)

      assert changeset.valid?
      assert DateTime.compare(changeset.changes.scheduled_at, scheduled_at) == :eq
    end

    test "accepts tags option" do
      args = %{"session_id" => "test-uuid", "prompt" => "Test prompt"}

      changeset = ScheduledTask.new(args, tags: ["scheduled", "reminder"])

      assert changeset.valid?
      assert "scheduled" in changeset.changes.tags
      assert "reminder" in changeset.changes.tags
    end

    test "sets priority to 1" do
      args = %{"session_id" => "test-uuid", "prompt" => "Test prompt"}

      changeset = ScheduledTask.new(args)

      assert changeset.changes.priority == 1
    end
  end

  # Note: perform/1 tests require database access and SessionManager
  # Those are covered in integration tests with Hal.DataCase
end
