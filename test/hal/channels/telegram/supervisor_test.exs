defmodule Hal.Channels.Telegram.SupervisorTest do
  @moduledoc """
  Tests for the Telegram Supervisor.
  """
  use ExUnit.Case, async: true

  alias Hal.Channels.Telegram.Supervisor

  describe "enabled?/0" do
    test "returns false when no bot token" do
      # Clear any existing config
      original = Application.get_env(:hal, Supervisor)
      Application.put_env(:hal, Supervisor, [])

      on_exit(fn ->
        if original do
          Application.put_env(:hal, Supervisor, original)
        else
          Application.delete_env(:hal, Supervisor)
        end
      end)

      refute Supervisor.enabled?()
    end

    test "returns false when bot token is empty string" do
      original = Application.get_env(:hal, Supervisor)
      Application.put_env(:hal, Supervisor, bot_token: "", enabled: true)

      on_exit(fn ->
        if original do
          Application.put_env(:hal, Supervisor, original)
        else
          Application.delete_env(:hal, Supervisor)
        end
      end)

      refute Supervisor.enabled?()
    end

    test "returns true when bot token is set" do
      original = Application.get_env(:hal, Supervisor)
      Application.put_env(:hal, Supervisor, bot_token: "test_token", enabled: true)

      on_exit(fn ->
        if original do
          Application.put_env(:hal, Supervisor, original)
        else
          Application.delete_env(:hal, Supervisor)
        end
      end)

      assert Supervisor.enabled?()
    end

    test "returns false when explicitly disabled" do
      original = Application.get_env(:hal, Supervisor)
      Application.put_env(:hal, Supervisor, bot_token: "test_token", enabled: false)

      on_exit(fn ->
        if original do
          Application.put_env(:hal, Supervisor, original)
        else
          Application.delete_env(:hal, Supervisor)
        end
      end)

      refute Supervisor.enabled?()
    end
  end

  describe "start_link/1" do
    test "starts supervisor without bot token (empty children)" do
      original = Application.get_env(:hal, Supervisor)
      Application.put_env(:hal, Supervisor, bot_token: nil, enabled: true)

      on_exit(fn ->
        if original do
          Application.put_env(:hal, Supervisor, original)
        else
          Application.delete_env(:hal, Supervisor)
        end
      end)

      name = :"test_supervisor_#{System.unique_integer([:positive])}"
      {:ok, pid} = Supervisor.start_link(name: name)

      assert Process.alive?(pid)

      # Should have no children since no token
      children = Elixir.Supervisor.which_children(pid)
      assert children == []

      Process.exit(pid, :normal)
    end

    test "starts supervisor when disabled" do
      original = Application.get_env(:hal, Supervisor)
      Application.put_env(:hal, Supervisor, bot_token: "test", enabled: false)

      on_exit(fn ->
        if original do
          Application.put_env(:hal, Supervisor, original)
        else
          Application.delete_env(:hal, Supervisor)
        end
      end)

      name = :"test_supervisor_disabled_#{System.unique_integer([:positive])}"
      {:ok, pid} = Supervisor.start_link(name: name)

      assert Process.alive?(pid)

      # Should have no children since disabled
      children = Elixir.Supervisor.which_children(pid)
      assert children == []

      Process.exit(pid, :normal)
    end
  end
end
