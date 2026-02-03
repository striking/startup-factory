defmodule Hal.Channels.Discord.ConsumerTest do
  use ExUnit.Case, async: true

  alias Hal.Channels.Discord.Consumer

  # Mock message struct similar to Nostrum.Struct.Message
  defmodule MockMessage do
    defstruct [
      :id,
      :channel_id,
      :guild_id,
      :author,
      :content,
      :mentions,
      :type
    ]
  end

  defmodule MockUser do
    defstruct [:id, :username, :bot]
  end

  @bot_user_id 123_456_789

  setup do
    # Set up mock bot user ID for tests
    Application.put_env(:hal, :discord_bot_user_id, @bot_user_id)

    on_exit(fn ->
      Application.delete_env(:hal, :discord_bot_user_id)
    end)

    :ok
  end

  describe "should_respond?/1" do
    test "returns true for DM messages (no guild_id)" do
      msg = %MockMessage{
        id: 1,
        channel_id: 111,
        guild_id: nil,
        author: %MockUser{id: 999, username: "testuser", bot: false},
        content: "Hello HAL",
        mentions: [],
        type: 0
      }

      assert Consumer.should_respond?(msg) == true
    end

    test "returns true when bot is mentioned" do
      bot_user_id = Application.get_env(:hal, :discord_bot_user_id)

      msg = %MockMessage{
        id: 1,
        channel_id: 111,
        guild_id: 222,
        author: %MockUser{id: 999, username: "testuser", bot: false},
        content: "Hey <@#{bot_user_id}> what's up?",
        mentions: [%MockUser{id: bot_user_id, username: "hal", bot: true}],
        type: 0
      }

      assert Consumer.should_respond?(msg) == true
    end

    test "returns false for guild messages without mention" do
      msg = %MockMessage{
        id: 1,
        channel_id: 111,
        guild_id: 222,
        author: %MockUser{id: 999, username: "testuser", bot: false},
        content: "Random message without mention",
        mentions: [],
        type: 0
      }

      assert Consumer.should_respond?(msg) == false
    end

    test "returns false for messages from bots" do
      msg = %MockMessage{
        id: 1,
        channel_id: 111,
        guild_id: nil,
        author: %MockUser{id: 888, username: "otherbot", bot: true},
        content: "I'm a bot message",
        mentions: [],
        type: 0
      }

      assert Consumer.should_respond?(msg) == false
    end
  end

  describe "extract_message_content/1" do
    test "removes bot mention from content" do
      bot_user_id = Application.get_env(:hal, :discord_bot_user_id)

      msg = %MockMessage{
        id: 1,
        channel_id: 111,
        guild_id: 222,
        author: %MockUser{id: 999, username: "testuser", bot: false},
        content: "<@#{bot_user_id}> What is Elixir?",
        mentions: [%MockUser{id: bot_user_id, username: "hal", bot: true}],
        type: 0
      }

      assert Consumer.extract_message_content(msg) == "What is Elixir?"
    end

    test "removes multiple bot mention formats" do
      bot_user_id = Application.get_env(:hal, :discord_bot_user_id)

      msg = %MockMessage{
        id: 1,
        channel_id: 111,
        guild_id: 222,
        author: %MockUser{id: 999, username: "testuser", bot: false},
        content: "<@!#{bot_user_id}> Help me with this",
        mentions: [%MockUser{id: bot_user_id, username: "hal", bot: true}],
        type: 0
      }

      assert Consumer.extract_message_content(msg) == "Help me with this"
    end

    test "preserves content for DMs" do
      msg = %MockMessage{
        id: 1,
        channel_id: 111,
        guild_id: nil,
        author: %MockUser{id: 999, username: "testuser", bot: false},
        content: "Hello, how are you?",
        mentions: [],
        type: 0
      }

      assert Consumer.extract_message_content(msg) == "Hello, how are you?"
    end
  end

  describe "build_gateway_message/1" do
    test "builds correct message map for DM" do
      msg = %MockMessage{
        id: 1,
        channel_id: 111,
        guild_id: nil,
        author: %MockUser{id: 999, username: "testuser", bot: false},
        content: "Test message",
        mentions: [],
        type: 0
      }

      result = Consumer.build_gateway_message(msg)

      assert result.channel_type == "discord"
      assert result.channel_id == "111"
      assert result.user_id == "999"
      assert result.content == "Test message"
      assert result.is_dm == true
      assert result.mentions_bot == false
    end

    test "builds correct message map for guild message with mention" do
      bot_user_id = Application.get_env(:hal, :discord_bot_user_id)

      msg = %MockMessage{
        id: 1,
        channel_id: 111,
        guild_id: 222,
        author: %MockUser{id: 999, username: "testuser", bot: false},
        content: "<@#{bot_user_id}> Hello",
        mentions: [%MockUser{id: bot_user_id, username: "hal", bot: true}],
        type: 0
      }

      result = Consumer.build_gateway_message(msg)

      assert result.channel_type == "discord"
      assert result.channel_id == "111"
      assert result.user_id == "999"
      assert result.content == "<@#{bot_user_id}> Hello"
      assert result.is_dm == false
      assert result.mentions_bot == true
    end
  end

  describe "dm?/1" do
    test "returns true when guild_id is nil" do
      msg = %MockMessage{guild_id: nil}
      assert Consumer.dm?(msg) == true
    end

    test "returns false when guild_id is present" do
      msg = %MockMessage{guild_id: 123}
      assert Consumer.dm?(msg) == false
    end
  end

  describe "mentions_bot?/1" do
    test "returns true when bot is in mentions list" do
      bot_user_id = Application.get_env(:hal, :discord_bot_user_id)

      msg = %MockMessage{
        mentions: [%MockUser{id: bot_user_id, username: "hal", bot: true}]
      }

      assert Consumer.mentions_bot?(msg) == true
    end

    test "returns false when bot is not in mentions" do
      msg = %MockMessage{
        mentions: [%MockUser{id: 888, username: "other", bot: false}]
      }

      assert Consumer.mentions_bot?(msg) == false
    end

    test "returns false for empty mentions" do
      msg = %MockMessage{mentions: []}
      assert Consumer.mentions_bot?(msg) == false
    end

    test "returns false for nil mentions" do
      msg = %MockMessage{mentions: nil}
      assert Consumer.mentions_bot?(msg) == false
    end
  end
end
