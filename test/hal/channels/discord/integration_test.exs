defmodule Hal.Channels.Discord.IntegrationTest do
  @moduledoc """
  Integration tests for the Discord channel connector.

  These tests verify the full message flow from Discord events
  through the Gateway and back to Discord responses.

  ## Running Integration Tests

  These tests require a Discord bot token and are marked with @tag :integration.
  They are excluded from the default test run.

  To run integration tests:

      mix test --include integration

  Or set the DISCORD_BOT_TOKEN environment variable and run:

      DISCORD_BOT_TOKEN=your_token mix test --include integration

  """

  use ExUnit.Case, async: true

  alias Hal.Channels.Discord.Consumer
  alias Hal.Channels.Discord.Sender
  alias Hal.Channels.Discord.Supervisor, as: DiscordSupervisor

  # Mock structs for testing without Nostrum
  defmodule MockMessage do
    defstruct [
      :id,
      :channel_id,
      :guild_id,
      :author,
      :content,
      :mentions,
      :type,
      :timestamp
    ]
  end

  defmodule MockUser do
    defstruct [:id, :username, :bot, :discriminator]
  end

  @bot_user_id 111_222_333

  setup do
    # Set up mock bot user ID
    Application.put_env(:hal, :discord_bot_user_id, @bot_user_id)

    on_exit(fn ->
      Application.delete_env(:hal, :discord_bot_user_id)
    end)

    :ok
  end

  describe "message flow integration" do
    test "DM message builds correct gateway message" do
      msg = build_dm_message("Hello HAL, how are you?")

      # Build gateway message
      gateway_message = Consumer.build_gateway_message(msg)

      # Verify message format
      assert gateway_message.channel_type == "discord"
      assert gateway_message.is_dm == true
      assert gateway_message.mentions_bot == false
      assert gateway_message.user_id == "999999"
      assert gateway_message.channel_id == "123456"
    end

    test "guild message with mention creates correct gateway message" do
      bot_user_id = Application.get_env(:hal, :discord_bot_user_id)
      msg = build_guild_message_with_mention("what is Elixir?", bot_user_id)

      # Verify should_respond logic
      assert Consumer.should_respond?(msg) == true

      # Build and verify gateway message
      gateway_message = Consumer.build_gateway_message(msg)
      assert gateway_message.is_dm == false
      assert gateway_message.mentions_bot == true

      # Content should have mention stripped (the build function adds <@bot_id>)
      cleaned_content = Consumer.extract_message_content(msg)
      assert cleaned_content == "what is Elixir?"
    end

    test "guild message without mention is ignored" do
      msg = build_guild_message_without_mention("Random chat message")

      assert Consumer.should_respond?(msg) == false
    end

    test "bot messages are ignored" do
      msg = build_bot_message("I'm a bot message")

      assert Consumer.should_respond?(msg) == false
    end
  end

  # Note: Session continuity tests are in the gateway_test.exs since they
  # require database setup with a valid user. These Discord-specific tests
  # focus on message parsing and routing logic without database dependencies.

  describe "Sender utilities" do
    test "chunk_message splits long messages correctly" do
      long_message = String.duplicate("a", 5000)
      chunks = Sender.chunk_message(long_message)

      assert length(chunks) == 3
      assert Enum.all?(chunks, &(String.length(&1) <= 2000))
      assert Enum.join(chunks) == long_message
    end

    test "build_embed creates valid embed structure" do
      embed =
        Sender.build_embed(
          title: "Test Title",
          description: "Test Description",
          color: :success,
          fields: [
            %{name: "Field 1", value: "Value 1"},
            %{name: "Field 2", value: "Value 2", inline: true}
          ]
        )

      assert embed.title == "Test Title"
      assert embed.description == "Test Description"
      assert embed.color == 0x57F287
      assert length(embed.fields) == 2
    end

    test "format_code_block wraps content correctly" do
      code = "def hello, do: :world"

      assert Sender.format_code_block(code) == "```\ndef hello, do: :world\n```"

      assert Sender.format_code_block(code, "elixir") ==
               "```elixir\ndef hello, do: :world\n```"
    end
  end

  describe "Supervisor configuration" do
    test "returns disabled when no token configured" do
      original = Application.get_env(:hal, :discord)
      Application.put_env(:hal, :discord, enabled: false, token: nil)

      refute DiscordSupervisor.enabled?()

      if original do
        Application.put_env(:hal, :discord, original)
      else
        Application.delete_env(:hal, :discord)
      end
    end

    test "returns enabled when token is configured" do
      original = Application.get_env(:hal, :discord)
      Application.put_env(:hal, :discord, enabled: true, token: "test_token_123")

      assert DiscordSupervisor.enabled?()

      if original do
        Application.put_env(:hal, :discord, original)
      else
        Application.delete_env(:hal, :discord)
      end
    end
  end

  # Helper functions for building mock messages

  defp build_dm_message(content) do
    %MockMessage{
      id: System.unique_integer([:positive]),
      channel_id: 123_456,
      guild_id: nil,
      author: %MockUser{id: 999_999, username: "testuser", bot: false},
      content: content,
      mentions: [],
      type: 0,
      timestamp: DateTime.utc_now()
    }
  end

  defp build_guild_message_with_mention(content, bot_user_id) do
    %MockMessage{
      id: System.unique_integer([:positive]),
      channel_id: 123_456,
      guild_id: 789_012,
      author: %MockUser{id: 999_999, username: "testuser", bot: false},
      content: "<@#{bot_user_id}> #{content}",
      mentions: [%MockUser{id: bot_user_id, username: "hal", bot: true}],
      type: 0,
      timestamp: DateTime.utc_now()
    }
  end

  defp build_guild_message_without_mention(content) do
    %MockMessage{
      id: System.unique_integer([:positive]),
      channel_id: 123_456,
      guild_id: 789_012,
      author: %MockUser{id: 999_999, username: "testuser", bot: false},
      content: content,
      mentions: [],
      type: 0,
      timestamp: DateTime.utc_now()
    }
  end

  defp build_bot_message(content) do
    %MockMessage{
      id: System.unique_integer([:positive]),
      channel_id: 123_456,
      guild_id: nil,
      author: %MockUser{id: 888_888, username: "otherbot", bot: true},
      content: content,
      mentions: [],
      type: 0,
      timestamp: DateTime.utc_now()
    }
  end
end

# Mock AI Client for testing without actual Claude Code calls
defmodule MockAIClient do
  @moduledoc false

  def prompt(_session_id, _message, _opts \\ []) do
    {:ok, "This is a mock response from the AI."}
  end
end
