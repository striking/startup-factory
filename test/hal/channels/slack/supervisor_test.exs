defmodule HAL.Channels.Slack.SupervisorTest do
  @moduledoc """
  Tests for the Slack Supervisor module.
  """
  use ExUnit.Case, async: true

  alias HAL.Channels.Slack.Supervisor, as: SlackSupervisor

  describe "start_link/1" do
    test "starts without tokens configured" do
      # Clear config
      Application.put_env(:hal, HAL.Channels.Slack, [])

      name = :"TestSlackSupervisor#{System.unique_integer()}"
      {:ok, pid} = SlackSupervisor.start_link(name: name)

      assert Process.alive?(pid)

      # Should have no children since not configured
      children = Supervisor.which_children(pid)
      assert children == []

      Supervisor.stop(pid)
    end

    test "starts Client when tokens are configured" do
      # Configure tokens
      Application.put_env(:hal, HAL.Channels.Slack,
        bot_token: "xoxb-test-token",
        app_token: "xapp-test-token"
      )

      name = :"TestSlackSupervisor#{System.unique_integer()}"
      {:ok, pid} = SlackSupervisor.start_link(name: name)

      assert Process.alive?(pid)

      # Should have one child (the Client)
      children = Supervisor.which_children(pid)
      assert length(children) == 1

      Supervisor.stop(pid)

      # Clean up config
      Application.put_env(:hal, HAL.Channels.Slack, [])
    end

    test "uses custom name" do
      Application.put_env(:hal, HAL.Channels.Slack, [])

      name = :"MySlackSupervisor#{System.unique_integer()}"
      {:ok, pid} = SlackSupervisor.start_link(name: name)

      assert Process.whereis(name) == pid

      Supervisor.stop(pid)
    end
  end

  describe "configured?/0" do
    test "returns false when tokens not set" do
      Application.put_env(:hal, HAL.Channels.Slack, [])

      refute SlackSupervisor.configured?()
    end

    test "returns false when only bot_token is set" do
      Application.put_env(:hal, HAL.Channels.Slack, bot_token: "xoxb-test")

      refute SlackSupervisor.configured?()

      Application.put_env(:hal, HAL.Channels.Slack, [])
    end

    test "returns false when only app_token is set" do
      Application.put_env(:hal, HAL.Channels.Slack, app_token: "xapp-test")

      refute SlackSupervisor.configured?()

      Application.put_env(:hal, HAL.Channels.Slack, [])
    end

    test "returns true when both tokens are set" do
      Application.put_env(:hal, HAL.Channels.Slack,
        bot_token: "xoxb-test",
        app_token: "xapp-test"
      )

      assert SlackSupervisor.configured?()

      Application.put_env(:hal, HAL.Channels.Slack, [])
    end
  end

  describe "status/0" do
    test "returns :not_configured when tokens not set" do
      Application.put_env(:hal, HAL.Channels.Slack, [])

      assert SlackSupervisor.status() == :not_configured
    end

    test "returns :not_running when Client not started" do
      Application.put_env(:hal, HAL.Channels.Slack,
        bot_token: "xoxb-test",
        app_token: "xapp-test"
      )

      # Make sure Client isn't running
      if Process.whereis(HAL.Channels.Slack.Client) do
        GenServer.stop(HAL.Channels.Slack.Client)
      end

      assert SlackSupervisor.status() == :not_running

      Application.put_env(:hal, HAL.Channels.Slack, [])
    end
  end
end
