defmodule HAL.Skills.RegistryTest do
  use ExUnit.Case, async: true

  alias HAL.Autonomy.SoulLoader
  alias HAL.Skills.Registry

  test "match_skills/1 activates mission control skill" do
    skills = Registry.match_skills("build a mission control kanban board")
    assert Enum.any?(skills, &(&1.name == "phoenix-liveview-mission-control"))
  end

  test "SoulLoader includes activated skills in system prompt" do
    prompt =
      SoulLoader.build_system_prompt(:main, message: "build a mission control kanban board")

    assert prompt =~ "# Activated Skills"
    assert prompt =~ "Phoenix LiveView"
  end
end
