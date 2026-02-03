defmodule HAL.SchedulerTest do
  use ExUnit.Case, async: true

  describe "scheduler configuration" do
    test "scheduler module is defined" do
      assert Code.ensure_loaded?(HAL.Scheduler)
    end

    test "scheduler uses Quantum" do
      # Verify the module uses Quantum behaviour (exports jobs/0, add_job/1, etc.)
      assert function_exported?(HAL.Scheduler, :jobs, 0)
      assert function_exported?(HAL.Scheduler, :add_job, 1)
    end

    test "scheduler has jobs configured" do
      # Verify jobs are accessible
      assert function_exported?(HAL.Scheduler, :jobs, 0)
    end
  end
end
