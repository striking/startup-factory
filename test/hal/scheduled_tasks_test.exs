defmodule HAL.ScheduledTasksTest do
  use ExUnit.Case, async: false

  describe "morning_briefing/0" do
    test "module and function exist" do
      # Verify the module and function are defined
      assert :morning_briefing in Keyword.keys(HAL.ScheduledTasks.__info__(:functions))
    end
  end

  describe "weekly_review/0" do
    test "module and function exist" do
      # Verify the module and function are defined
      assert :weekly_review in Keyword.keys(HAL.ScheduledTasks.__info__(:functions))
    end
  end
end
