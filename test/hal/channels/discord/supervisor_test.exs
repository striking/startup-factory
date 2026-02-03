defmodule Hal.Channels.Discord.SupervisorTest do
  use ExUnit.Case, async: true

  alias Hal.Channels.Discord.Supervisor, as: DiscordSupervisor

  describe "child_spec/1" do
    test "returns valid child spec" do
      spec = DiscordSupervisor.child_spec([])

      assert spec.id == DiscordSupervisor
      assert spec.start == {DiscordSupervisor, :start_link, [[]]}
      assert spec.type == :supervisor
    end
  end

  describe "enabled?/0" do
    test "returns false when token is not configured" do
      # Clear any existing config
      original = Application.get_env(:hal, :discord)
      Application.put_env(:hal, :discord, enabled: false)

      refute DiscordSupervisor.enabled?()

      # Restore
      if original do
        Application.put_env(:hal, :discord, original)
      else
        Application.delete_env(:hal, :discord)
      end
    end
  end
end
