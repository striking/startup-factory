defmodule HAL.Channels.Slack.Handler do
  @moduledoc """
  Processes incoming Slack events and routes them to the Gateway.

  This module handles:
  - Message events from channels and DMs
  - @mention detection in channels
  - Thread context preservation
  - Routing to Gateway.Router for AI processing

  ## Event Types Handled

  - `message` - Regular messages in channels/DMs
  - `app_mention` - Bot @mentions in channels

  ## Routing Rules

  1. **DMs (im channel type)**: Always respond
  2. **@mentions in channels**: Respond in thread
  3. **Channel messages without mention**: Ignore
  4. **Bot messages**: Ignore (prevent loops)

  ## Thread Handling

  For threaded conversations:
  - Uses thread_ts as part of session key for continuity
  - Replies maintain thread context
  """

  require Logger

  alias HAL.Channels.Slack.Sender
  alias Hal.Gateway.Router

  @doc """
  Handles an incoming Slack event.

  This is the main entry point for processing Slack events.
  Events are routed to appropriate handlers based on type.

  ## Arguments

    * `event` - The Slack event payload

  ## Returns

    * `:ok` - Event handled successfully
    * `{:error, reason}` - Error occurred
  """
  @spec handle_event(map()) :: :ok | {:error, term()}
  def handle_event(%{"type" => "message"} = event) do
    handle_message_event(event)
  end

  def handle_event(%{"type" => "app_mention"} = event) do
    handle_app_mention_event(event)
  end

  def handle_event(%{"type" => type}) do
    Logger.debug("Ignoring Slack event type: #{type}")
    :ok
  end

  def handle_event(event) do
    Logger.debug("Ignoring unknown Slack event: #{inspect(event)}")
    :ok
  end

  @doc """
  Handles a message event from Slack.

  Message events include:
  - Direct messages (channel starts with "D")
  - Channel messages (channel starts with "C")
  - Group messages (channel starts with "G")
  """
  @spec handle_message_event(map()) :: :ok | {:error, term()}
  def handle_message_event(event) do
    # Ignore bot messages (including our own)
    if bot_message?(event) do
      :ok
    else
      process_message(event)
    end
  end

  @doc """
  Handles an app_mention event from Slack.

  App mentions occur when someone @mentions the bot in a channel.
  """
  @spec handle_app_mention_event(map()) :: :ok | {:error, term()}
  def handle_app_mention_event(event) do
    # App mentions are always responded to
    process_mention(event)
  end

  # Private functions

  defp process_message(event) do
    channel_id = event["channel"]
    user_id = event["user"]
    text = event["text"] || ""
    thread_ts = event["thread_ts"]
    message_ts = event["ts"]

    # Determine if this is a DM
    is_dm = dm_channel?(channel_id)

    # Check if bot is mentioned in channel messages
    mentions_bot = is_dm || mentions_bot?(text, get_bot_user_id())

    # Build session key - use thread_ts for thread continuity
    session_channel_id = build_session_channel_id(channel_id, thread_ts)

    # Build message for Router
    message = %{
      channel_type: "slack",
      channel_id: session_channel_id,
      user_id: user_id,
      content: text,
      is_dm: is_dm,
      mentions_bot: mentions_bot,
      metadata: %{
        raw_channel_id: channel_id,
        thread_ts: thread_ts,
        message_ts: message_ts
      }
    }

    if Router.should_respond?(message) do
      route_and_respond(message, channel_id, thread_ts || message_ts)
    else
      :ok
    end
  end

  defp process_mention(event) do
    channel_id = event["channel"]
    user_id = event["user"]
    text = event["text"] || ""
    thread_ts = event["thread_ts"]
    message_ts = event["ts"]

    # Build session key - use thread_ts for thread continuity
    session_channel_id = build_session_channel_id(channel_id, thread_ts)

    # Build message for Router
    message = %{
      channel_type: "slack",
      channel_id: session_channel_id,
      user_id: user_id,
      content: text,
      is_dm: false,
      mentions_bot: true,
      metadata: %{
        raw_channel_id: channel_id,
        thread_ts: thread_ts,
        message_ts: message_ts
      }
    }

    route_and_respond(message, channel_id, thread_ts || message_ts)
  end

  defp route_and_respond(message, channel_id, reply_thread_ts) do
    # Show typing indicator (optional enhancement)
    # Can add later with reactions.add or typing indicator API

    router = Hal.Gateway.default_names().router

    case Router.route_message(router, message) do
      {:ok, response} ->
        # Send response in thread
        case Sender.send_message(channel_id, response, thread_ts: reply_thread_ts) do
          {:ok, _} ->
            Logger.debug("Sent Slack response to #{channel_id}")
            :ok

          {:error, reason} ->
            Logger.error("Failed to send Slack message: #{inspect(reason)}")
            {:error, reason}
        end

      :ignored ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to route Slack message: #{inspect(reason)}")
        # Optionally notify user of error
        error_msg = "Sorry, I encountered an error processing your message."
        Sender.send_message(channel_id, error_msg, thread_ts: reply_thread_ts)
        {:error, reason}
    end
  end

  defp bot_message?(event) do
    # Check for bot_id or subtype indicating bot message
    Map.has_key?(event, "bot_id") ||
      event["subtype"] == "bot_message" ||
      event["subtype"] == "message_changed" ||
      event["subtype"] == "message_deleted"
  end

  defp dm_channel?(channel_id) do
    # DM channels start with "D"
    String.starts_with?(channel_id, "D")
  end

  defp mentions_bot?(text, bot_user_id) when is_binary(bot_user_id) do
    # Check for <@BOTID> mention pattern
    String.contains?(text, "<@#{bot_user_id}>")
  end

  defp mentions_bot?(_text, _nil_bot_id), do: false

  defp build_session_channel_id(channel_id, nil), do: channel_id

  defp build_session_channel_id(channel_id, thread_ts) do
    # Include thread_ts in session key for thread continuity
    "#{channel_id}:#{thread_ts}"
  end

  defp get_bot_user_id do
    # This would be set during Client initialization after auth.test
    Process.get(:slack_bot_user_id) ||
      Application.get_env(:hal, HAL.Channels.Slack)[:bot_user_id]
  end
end
