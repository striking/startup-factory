defmodule Hal.Channels.Discord.Consumer do
  @moduledoc """
  Nostrum Consumer for handling Discord events.

  This module implements the `Nostrum.Consumer` behaviour to handle
  Discord gateway events, primarily MESSAGE_CREATE events.

  ## Event Handling

  The consumer handles:
  - MESSAGE_CREATE: New messages in channels and DMs
  - MESSAGE_REACTION_ADD: Reactions added to messages (optional)

  ## Routing Rules

  Messages are routed to the Gateway when:
  1. Message is a DM (guild_id is nil)
  2. Message mentions the bot (@HAL)

  Messages are ignored when:
  1. Message is from a bot
  2. Message is in a guild without mentioning the bot

  ## Usage

  The consumer is started as part of the Discord Supervisor and receives
  events from Nostrum's gateway connection.
  """

  @behaviour Nostrum.Consumer

  require Logger

  alias Hal.Gateway.Router

  @doc """
  Handles incoming Discord gateway events.

  ## MESSAGE_CREATE

  Routes incoming messages to the Gateway Router if they should be responded to.
  """
  @impl true
  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    if should_respond?(msg) do
      handle_message(msg)
    else
      :ignore
    end
  end

  @impl true
  def handle_event({:MESSAGE_REACTION_ADD, _reaction, _ws_state}) do
    # Optional: Handle reactions (e.g., for confirmations)
    :ok
  end

  @impl true
  def handle_event({:READY, ready_data, _ws_state}) do
    Logger.info("Discord bot connected as #{ready_data.user.username}")
    # Store the bot user ID for mention detection
    Application.put_env(:hal, :discord_bot_user_id, ready_data.user.id)
    :ok
  end

  @impl true
  def handle_event(_event) do
    # Ignore all other events
    :ok
  end

  @doc """
  Determines if the bot should respond to a message.

  Returns `true` for:
  - DMs (direct messages, where guild_id is nil)
  - Guild messages that mention the bot

  Returns `false` for:
  - Messages from bots
  - Guild messages without bot mention
  """
  @spec should_respond?(map()) :: boolean()
  def should_respond?(msg) do
    cond do
      bot_message?(msg) -> false
      dm?(msg) -> true
      mentions_bot?(msg) -> true
      true -> false
    end
  end

  @doc """
  Checks if a message is a DM (direct message).

  A message is a DM when guild_id is nil.
  """
  @spec dm?(map()) :: boolean()
  def dm?(%{guild_id: nil}), do: true
  def dm?(_msg), do: false

  @doc """
  Checks if the message mentions the bot.

  Looks through the mentions list for the bot's user ID.
  """
  @spec mentions_bot?(map()) :: boolean()
  def mentions_bot?(%{mentions: nil}), do: false
  def mentions_bot?(%{mentions: []}), do: false

  def mentions_bot?(%{mentions: mentions}) when is_list(mentions) do
    bot_user_id = get_bot_user_id()

    Enum.any?(mentions, fn user ->
      user.id == bot_user_id
    end)
  end

  def mentions_bot?(_msg), do: false

  @doc """
  Extracts the message content, removing bot mentions.

  Removes patterns like `<@123456>` or `<@!123456>` from the start of the message.
  """
  @spec extract_message_content(map()) :: String.t()
  def extract_message_content(%{content: content}) do
    bot_user_id = get_bot_user_id()

    content
    |> String.replace(~r/<@!?#{bot_user_id}>\s*/, "")
    |> String.trim()
  end

  @doc """
  Builds a Gateway-compatible message map from a Discord message.
  """
  @spec build_gateway_message(map()) :: map()
  def build_gateway_message(msg) do
    %{
      channel_type: "discord",
      channel_id: to_string(msg.channel_id),
      user_id: to_string(msg.author.id),
      content: msg.content,
      is_dm: dm?(msg),
      mentions_bot: mentions_bot?(msg),
      metadata: %{
        discord_message_id: msg.id,
        discord_guild_id: msg.guild_id,
        author_username: msg.author.username
      }
    }
  end

  # Private Functions

  defp handle_message(msg) do
    Logger.debug("Discord: Handling message from #{msg.author.username}: #{msg.content}")

    gateway_message = build_gateway_message(msg)
    # Override content with cleaned version (mentions removed)
    gateway_message = %{gateway_message | content: extract_message_content(msg)}

    # Get the default router name
    router_name = Hal.Gateway.default_names().router

    case Router.route_message(router_name, gateway_message) do
      {:ok, response} ->
        send_response(msg.channel_id, response, msg.id)

      :ignored ->
        :ok

      {:error, reason} ->
        Logger.error("Discord: Failed to route message: #{inspect(reason)}")
        send_error_response(msg.channel_id, msg.id)
    end
  end

  defp send_response(channel_id, response, reply_to_message_id) do
    alias Nostrum.Api.Message

    # Send as a reply to maintain thread context
    case Message.create(channel_id,
           content: response,
           message_reference: %{message_id: reply_to_message_id}
         ) do
      {:ok, _msg} ->
        Logger.debug("Discord: Sent response to channel #{channel_id}")
        :ok

      {:error, reason} ->
        Logger.error("Discord: Failed to send message: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp send_error_response(channel_id, reply_to_message_id) do
    alias Nostrum.Api.Message

    error_msg = "Sorry, I encountered an error processing your message. Please try again."

    Message.create(channel_id,
      content: error_msg,
      message_reference: %{message_id: reply_to_message_id}
    )

    :ok
  end

  defp bot_message?(%{author: %{bot: true}}), do: true
  defp bot_message?(_msg), do: false

  defp get_bot_user_id do
    Application.get_env(:hal, :discord_bot_user_id)
  end
end
