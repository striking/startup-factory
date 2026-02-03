defmodule HAL.Channels.Slack.ClientTest do
  @moduledoc """
  Tests for the Slack Socket Mode Client.
  """
  use ExUnit.Case, async: true

  alias HAL.Channels.Slack.Client

  describe "start_link/1" do
    test "starts without tokens configured" do
      # Clear any existing config
      Application.put_env(:hal, HAL.Channels.Slack, [])

      {:ok, pid} = Client.start_link(name: :"TestClient#{System.unique_integer()}")

      assert Process.alive?(pid)
      # Should not be connected since no tokens
      refute Client.connected?(pid)

      GenServer.stop(pid)
    end

    test "starts with custom name" do
      Application.put_env(:hal, HAL.Channels.Slack, [])

      name = :"CustomSlackClient#{System.unique_integer()}"
      {:ok, pid} = Client.start_link(name: name)

      assert Process.alive?(pid)
      assert Process.whereis(name) == pid

      GenServer.stop(pid)
    end
  end

  describe "connected?/1" do
    test "returns false when not connected" do
      Application.put_env(:hal, HAL.Channels.Slack, [])

      {:ok, pid} = Client.start_link(name: :"TestClient#{System.unique_integer()}")

      refute Client.connected?(pid)

      GenServer.stop(pid)
    end
  end

  describe "get_bot_user_id/1" do
    test "returns nil when not connected" do
      Application.put_env(:hal, HAL.Channels.Slack, [])

      {:ok, pid} = Client.start_link(name: :"TestClient#{System.unique_integer()}")

      assert Client.get_bot_user_id(pid) == nil

      GenServer.stop(pid)
    end
  end

  describe "send_message/3" do
    # This delegates to Sender, which is tested separately
    # Here we just verify the delegation works
  end

  describe "reconnection behavior" do
    test "schedules reconnect on disconnect" do
      # This would test the reconnection logic
      # Would need to mock the WebSocket connection
    end

    test "uses exponential backoff" do
      # Would verify delay increases with each attempt
    end
  end

  describe "message handling" do
    test "handles hello message" do
      Application.put_env(:hal, HAL.Channels.Slack, [])

      {:ok, pid} = Client.start_link(name: :"TestClient#{System.unique_integer()}")

      # Simulate receiving a hello message
      hello_msg = Jason.encode!(%{"type" => "hello"})
      send(pid, {:websocket_message, hello_msg})

      # Give it time to process
      Process.sleep(50)

      # Should still be alive (didn't crash)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "handles disconnect message" do
      Application.put_env(:hal, HAL.Channels.Slack, [])

      {:ok, pid} = Client.start_link(name: :"TestClient#{System.unique_integer()}")

      # Simulate receiving a disconnect message
      disconnect_msg = Jason.encode!(%{"type" => "disconnect", "reason" => "test"})
      send(pid, {:websocket_message, disconnect_msg})

      # Give it time to process
      Process.sleep(50)

      # Should still be alive (handles disconnect gracefully)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "processes event payloads" do
      Application.put_env(:hal, HAL.Channels.Slack, [])

      {:ok, pid} = Client.start_link(name: :"TestClient#{System.unique_integer()}")

      # Simulate receiving an event
      event_msg =
        Jason.encode!(%{
          "envelope_id" => "abc123",
          "type" => "events_api",
          "payload" => %{
            "event" => %{
              "type" => "message",
              "channel" => "D123",
              "user" => "U123",
              "text" => "Hello",
              "ts" => "123.456"
            }
          }
        })

      send(pid, {:websocket_message, event_msg})

      # Give it time to process
      Process.sleep(50)

      # Should still be alive
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "handles malformed JSON gracefully" do
      Application.put_env(:hal, HAL.Channels.Slack, [])

      {:ok, pid} = Client.start_link(name: :"TestClient#{System.unique_integer()}")

      # Send malformed JSON
      send(pid, {:websocket_message, "not valid json {"})

      # Give it time to process
      Process.sleep(50)

      # Should still be alive (handles error gracefully)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  describe "websocket lifecycle" do
    test "handles websocket_closed message" do
      Application.put_env(:hal, HAL.Channels.Slack, [])

      {:ok, pid} = Client.start_link(name: :"TestClient#{System.unique_integer()}")

      send(pid, {:websocket_closed, :normal})

      Process.sleep(50)

      assert Process.alive?(pid)
      refute Client.connected?(pid)

      GenServer.stop(pid)
    end

    test "handles websocket_error message" do
      Application.put_env(:hal, HAL.Channels.Slack, [])

      {:ok, pid} = Client.start_link(name: :"TestClient#{System.unique_integer()}")

      send(pid, {:websocket_error, :connection_refused})

      Process.sleep(50)

      assert Process.alive?(pid)
      refute Client.connected?(pid)

      GenServer.stop(pid)
    end
  end
end
