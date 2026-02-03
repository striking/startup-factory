defmodule Hal.Channels.Telegram.Bot do
  @moduledoc """
  ExGram bot module for handling Telegram updates.

  This module uses the ExGram library to connect to Telegram's Bot API
  and receive updates via polling. It routes all received updates to
  the Handler for processing.

  ## Update Types Handled

  - Text messages (in DMs and groups)
  - Voice messages
  - Photos
  - Documents
  - Callback queries (for inline keyboards)

  ## Configuration

  The bot is started by the Telegram.Supervisor with:
  - `method: :polling` - Use long polling (webhook support available)
  - `token: bot_token` - Telegram bot token from BotFather
  - `handler_name: pid_or_name` - Handler process to route updates to

  ## Example

      # Started by Supervisor, not directly
      {Hal.Channels.Telegram.Bot,
       method: :polling,
       token: "bot_token",
       handler_name: Hal.Channels.Telegram.Handler}
  """

  use ExGram.Bot, name: :hal_telegram_bot

  require Logger

  alias Hal.Channels.Telegram.Handler

  @doc """
  Initializes the bot.

  Called by ExGram when the bot starts. Stores the handler name
  for routing updates.
  """
  def init(opts) do
    handler_name = Keyword.get(opts, :handler_name, Handler)
    # Store in process dictionary for handle callbacks
    Process.put(:handler_name, handler_name)

    Logger.info("Telegram bot initialized, handler: #{inspect(handler_name)}")
    :ok
  end

  # Handle text messages
  @impl ExGram.Handler
  def handle({:text, _text, message}, cnt) do
    route_to_handler(:text_message, message, cnt)
  end

  # Handle commands (e.g., /start, /help)
  def handle({:command, command, message}, cnt) do
    route_to_handler(:command, %{command: command, message: message}, cnt)
  end

  # Handle voice messages
  def handle({:message, %{voice: voice} = message}, cnt) when not is_nil(voice) do
    route_to_handler(:voice_message, message, cnt)
  end

  # Handle photo messages
  def handle({:message, %{photo: photo} = message}, cnt) when is_list(photo) and photo != [] do
    route_to_handler(:photo_message, message, cnt)
  end

  # Handle document messages
  def handle({:message, %{document: document} = message}, cnt) when not is_nil(document) do
    route_to_handler(:document_message, message, cnt)
  end

  # Handle other messages (fallback)
  def handle({:message, message}, cnt) do
    route_to_handler(:other_message, message, cnt)
  end

  # Handle callback queries (inline keyboard buttons)
  def handle({:callback_query, callback_query}, cnt) do
    route_to_handler(:callback_query, callback_query, cnt)
  end

  # Handle edited messages
  def handle({:edited_message, message}, cnt) do
    route_to_handler(:edited_message, message, cnt)
  end

  # Catch-all for unhandled update types
  def handle({type, data}, _cnt) do
    Logger.debug("Unhandled Telegram update type: #{inspect(type)}")
    Logger.debug("Data: #{inspect(data, limit: 200)}")
    :ok
  end

  def handle(other, _cnt) do
    Logger.debug("Unknown Telegram update format: #{inspect(other, limit: 200)}")
    :ok
  end

  @impl ExGram.Handler
  def handle_error(%ExGram.Error{code: code, message: message}) do
    Logger.error("Telegram bot error: [#{code}] #{message}")
    :ok
  end

  def handle_error(error) do
    Logger.error("Telegram bot error: #{inspect(error)}")
    :ok
  end

  # Private functions

  defp route_to_handler(type, data, cnt) do
    handler_name = Process.get(:handler_name, Handler)

    try do
      Handler.handle_update(handler_name, type, data, cnt)
    rescue
      e ->
        Logger.error("Error routing to handler: #{Exception.message(e)}")
        Logger.error(Exception.format_stacktrace(__STACKTRACE__))
    end

    # Return cnt unchanged - we handle responses via Sender
    cnt
  end
end
