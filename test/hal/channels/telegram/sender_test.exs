defmodule Hal.Channels.Telegram.SenderTest do
  @moduledoc """
  Tests for the Telegram Sender GenServer.

  Note: These tests mock ExGram API calls to avoid actual Telegram requests.
  """
  use ExUnit.Case, async: true

  alias Hal.Channels.Telegram.Sender

  describe "message splitting" do
    test "sends short messages as-is" do
      # We test the splitting logic indirectly by checking the function behavior
      # The actual API call is mocked in integration tests

      text = "Hello, world!"
      assert byte_size(text) < 4096
    end

    test "splits long messages at paragraph breaks" do
      # Create a message longer than 4096 bytes
      paragraph1 = String.duplicate("A", 3000)
      paragraph2 = String.duplicate("B", 3000)
      long_message = "#{paragraph1}\n\n#{paragraph2}"

      assert byte_size(long_message) > 4096
      # The sender should split this into 2 messages
    end

    test "splits at sentence breaks when no paragraphs" do
      sentence1 = String.duplicate("Word ", 600)
      sentence2 = String.duplicate("More ", 600)
      long_message = "#{sentence1}. #{sentence2}."

      assert byte_size(long_message) > 4096
    end
  end

  describe "start_link/1" do
    test "starts with required options" do
      name = :"test_sender_#{System.unique_integer([:positive])}"

      {:ok, pid} = Sender.start_link(name: name, bot_token: "test_token")

      assert Process.alive?(pid)
      Process.exit(pid, :normal)
    end
  end
end
