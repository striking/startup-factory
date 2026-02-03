defmodule Hal.Channels.Telegram.Handler do
  @moduledoc """
  Processes incoming Telegram messages and routes them to the Gateway.

  The Handler is responsible for:
  - Determining if the bot should respond (DM vs group @mention)
  - Extracting user/chat information from Telegram updates
  - Downloading voice messages for transcription
  - Creating/looking up users in the database
  - Routing messages to Gateway.Router

  ## Message Types

  - `:text_message` - Regular text messages
  - `:voice_message` - Voice/audio messages (transcribed via STT)
  - `:photo_message` - Photos with optional captions
  - `:document_message` - File attachments
  - `:command` - Bot commands like /start, /help
  - `:callback_query` - Inline keyboard button presses

  ## DM vs Group Logic

  - **DMs**: Respond to all messages
  - **Groups**: Only respond when @mentioned (by username or bot ID)

  ## Usage

  Called by Bot module, not directly:

      Handler.handle_update(handler_name, :text_message, message, cnt)
  """

  use GenServer
  require Logger

  alias Hal.Accounts.User
  alias Hal.Channels.Telegram.Sender
  alias Hal.Gateway.Router
  alias Hal.Repo

  import Ecto.Query

  defstruct [
    :sender_name,
    :session_manager,
    :router,
    :bot_info
  ]

  # Client API

  @doc """
  Starts the Handler GenServer.

  ## Options

    * `:name` - The name to register under (required)
    * `:sender_name` - Name of the Sender process
    * `:session_manager` - SessionManager process name
    * `:router` - Router process name
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Handles an incoming Telegram update.

  Called by the Bot module when an update is received.
  Processes the update asynchronously.
  """
  @spec handle_update(GenServer.server(), atom(), map(), map()) :: :ok
  def handle_update(server, type, data, cnt) do
    GenServer.cast(server, {:handle_update, type, data, cnt})
  end

  @doc """
  Sets the bot info (username, id) after initialization.
  """
  @spec set_bot_info(GenServer.server(), map()) :: :ok
  def set_bot_info(server, bot_info) do
    GenServer.call(server, {:set_bot_info, bot_info})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      sender_name: Keyword.get(opts, :sender_name, Sender),
      session_manager: Keyword.get(opts, :session_manager, Hal.Gateway.SessionManager),
      router: Keyword.get(opts, :router, Hal.Gateway.Router),
      bot_info: nil
    }

    # Try to get bot info asynchronously
    send(self(), :fetch_bot_info)

    {:ok, state}
  end

  @impl true
  def handle_call({:set_bot_info, bot_info}, _from, state) do
    {:reply, :ok, %{state | bot_info: bot_info}}
  end

  @impl true
  def handle_cast({:handle_update, type, data, cnt}, state) do
    process_update(type, data, cnt, state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:fetch_bot_info, state) do
    # Try to get bot info from ExGram
    case get_bot_info() do
      {:ok, bot_info} ->
        Logger.info("Telegram bot info: @#{bot_info.username} (ID: #{bot_info.id})")
        {:noreply, %{state | bot_info: bot_info}}

      {:error, reason} ->
        Logger.warning("Failed to fetch bot info: #{inspect(reason)}")
        # Retry after a delay
        Process.send_after(self(), :fetch_bot_info, 5_000)
        {:noreply, state}
    end
  end

  # Private functions

  defp get_bot_info do
    try do
      case ExGram.get_me(bot: :hal_telegram_bot) do
        {:ok, bot_info} -> {:ok, bot_info}
        {:error, reason} -> {:error, reason}
      end
    rescue
      e -> {:error, Exception.message(e)}
    catch
      :exit, reason -> {:error, reason}
    end
  end

  defp process_update(:text_message, message, _cnt, state) do
    process_text_message(message, state)
  end

  defp process_update(:voice_message, message, _cnt, state) do
    process_voice_message(message, state)
  end

  defp process_update(:photo_message, message, _cnt, state) do
    # For photos, use the caption as the message content
    caption = message.caption || "[Photo received]"
    process_text_message(%{message | text: caption}, state)
  end

  defp process_update(:document_message, message, _cnt, state) do
    caption = message.caption || "[Document received: #{message.document.file_name}]"
    process_text_message(%{message | text: caption}, state)
  end

  defp process_update(:command, %{command: command, message: message}, _cnt, state) do
    case command do
      :start ->
        send_welcome_message(message, state)

      :help ->
        send_help_message(message, state)

      _other ->
        # Treat other commands as regular messages
        process_text_message(message, state)
    end
  end

  defp process_update(:callback_query, callback_query, _cnt, state) do
    Logger.debug("Received callback query: #{inspect(callback_query.data)}")
    # Answer the callback to remove loading state
    answer_callback_query(callback_query.id)
    # Process the callback data as a message if it contains text
    if callback_query.data do
      fake_message = %{
        callback_query.message
        | text: callback_query.data,
          from: callback_query.from
      }

      process_text_message(fake_message, state)
    end
  end

  defp process_update(:edited_message, message, _cnt, state) do
    # Treat edited messages the same as new messages
    if message.text do
      process_text_message(message, state)
    end
  end

  defp process_update(type, _data, _cnt, _state) do
    Logger.debug("Ignoring update type: #{type}")
  end

  defp process_text_message(message, state) do
    chat = message.chat
    from = message.from
    text = message.text || ""

    # Determine if this is a DM or group
    is_dm = chat.type == "private"
    mentions_bot = mentions_bot?(text, state.bot_info)

    # Skip if group message without mention
    if is_dm || mentions_bot do
      do_process_text_message(message, chat, from, text, is_dm, mentions_bot, state)
    else
      Logger.debug("Ignoring group message without bot mention")
      {:ignored, :no_mention}
    end
  end

  defp do_process_text_message(message, chat, from, text, is_dm, mentions_bot, state) do
    # Get or create user
    user = get_or_create_user(from)

    # Clean the message text (remove @mentions)
    cleaned_text = clean_mention(text, state.bot_info)

    # Build message for router
    router_message = %{
      channel_type: "telegram",
      channel_id: to_string(chat.id),
      user_id: user.id,
      content: cleaned_text,
      is_dm: is_dm,
      mentions_bot: mentions_bot,
      metadata: %{
        telegram_message_id: message.message_id,
        telegram_chat_type: chat.type,
        telegram_user_id: from.id,
        username: from.username,
        first_name: from.first_name
      }
    }

    # Route to Gateway
    route_message(router_message, chat.id, state)
  end

  defp process_voice_message(message, state) do
    chat = message.chat
    from = message.from

    # Voice messages are always processed (they require explicit sending)
    is_dm = chat.type == "private"

    # In groups, only process if it's a reply to the bot or in a DM
    if is_dm || is_reply_to_bot?(message, state.bot_info) do
      do_process_voice_message(message, chat, from, is_dm, state)
    else
      Logger.debug("Ignoring voice message in group (not reply to bot)")
      {:ignored, :no_mention}
    end
  end

  defp do_process_voice_message(message, chat, from, is_dm, state) do
    # Download and transcribe the voice message
    case download_and_transcribe_voice(message.voice) do
      {:ok, transcribed_text} ->
        user = get_or_create_user(from)

        router_message = %{
          channel_type: "telegram",
          channel_id: to_string(chat.id),
          user_id: user.id,
          content: transcribed_text,
          is_dm: is_dm,
          mentions_bot: true,
          metadata: %{
            telegram_message_id: message.message_id,
            voice_message: true,
            voice_duration: message.voice.duration
          }
        }

        route_message(router_message, chat.id, state)

      {:error, reason} ->
        Logger.error("Failed to transcribe voice message: #{reason}")

        Sender.send_message(
          state.sender_name,
          chat.id,
          "Sorry, I couldn't process that voice message: #{reason}"
        )
    end
  end

  defp download_and_transcribe_voice(voice) do
    with {:ok, file} <- get_telegram_file(voice.file_id),
         {:ok, audio_data} <- download_voice_file(file),
         {:ok, tmp_path} <- save_voice_to_temp(audio_data, file.file_path) do
      transcribe_and_cleanup(tmp_path)
    end
  end

  defp get_telegram_file(file_id) do
    case ExGram.get_file(file_id, bot: :hal_telegram_bot) do
      {:ok, file} -> {:ok, file}
      {:error, reason} -> {:error, "Failed to get file info: #{inspect(reason)}"}
    end
  end

  defp download_voice_file(file) do
    file_url = "https://api.telegram.org/file/bot#{get_bot_token()}/#{file.file_path}"

    case download_file(file_url) do
      {:ok, audio_data} -> {:ok, audio_data}
      {:error, reason} -> {:error, "Failed to download voice: #{reason}"}
    end
  end

  defp save_voice_to_temp(audio_data, file_path) do
    ext = Path.extname(file_path) |> String.downcase()
    ext = if ext == "", do: ".ogg", else: ext

    tmp_path =
      Path.join(System.tmp_dir!(), "hal_voice_#{System.unique_integer([:positive])}#{ext}")

    case File.write(tmp_path, audio_data) do
      :ok -> {:ok, tmp_path}
      {:error, reason} -> {:error, "Failed to save audio: #{inspect(reason)}"}
    end
  end

  defp transcribe_and_cleanup(tmp_path) do
    result = HAL.Voice.STT.transcribe(tmp_path)
    File.rm(tmp_path)
    result
  end

  defp download_file(url) do
    case HTTPoison.get(url, [], recv_timeout: 30_000) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status_code: status}} ->
        {:error, "HTTP #{status}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, inspect(reason)}
    end
  end

  defp get_bot_token do
    config = Application.get_env(:hal, Hal.Channels.Telegram.Supervisor, [])
    Keyword.get(config, :bot_token, System.get_env("TELEGRAM_BOT_TOKEN"))
  end

  defp route_message(message, chat_id, state) do
    case Router.route_message(state.router, message) do
      {:ok, response} ->
        # Send response back to Telegram
        Sender.send_message(state.sender_name, chat_id, response)

      :ignored ->
        Logger.debug("Message was ignored by router")

      {:error, reason} ->
        Logger.error("Failed to route message: #{inspect(reason)}")

        Sender.send_message(
          state.sender_name,
          chat_id,
          "Sorry, something went wrong. Please try again."
        )
    end
  end

  defp send_welcome_message(message, state) do
    chat_id = message.chat.id
    user_name = message.from.first_name || "there"

    welcome_text = """
    Hello #{user_name}! I'm HAL, your personal AI assistant.

    I'm powered by Claude and can help you with:
    - Answering questions
    - Writing and coding
    - Analyzing information
    - And much more!

    Just send me a message to get started. In groups, mention me with @#{get_bot_username(state)} to get my attention.

    Type /help for more information.
    """

    Sender.send_message(state.sender_name, chat_id, welcome_text)
  end

  defp send_help_message(message, state) do
    chat_id = message.chat.id

    help_text = """
    *HAL - AI Assistant Help*

    *Commands:*
    /start - Start a conversation
    /help - Show this help message

    *Features:*
    - Send text messages and I'll respond with AI-powered answers
    - Send voice messages and I'll transcribe and respond
    - In groups, mention me @#{get_bot_username(state)} to get my attention

    *Tips:*
    - Be specific in your questions for better answers
    - I maintain conversation context within each chat
    - Voice messages work in DMs and when replying to me

    Powered by Claude AI.
    """

    Sender.send_message(state.sender_name, chat_id, help_text, parse_mode: "Markdown")
  end

  defp get_bot_username(state) do
    case state.bot_info do
      %{username: username} when is_binary(username) -> username
      _ -> "hal"
    end
  end

  defp mentions_bot?(text, bot_info) do
    text = String.downcase(text)

    cond do
      # Check for @username mention
      bot_info && bot_info.username &&
          String.contains?(text, "@" <> String.downcase(bot_info.username)) ->
        true

      # Check for common patterns
      String.starts_with?(text, "@hal") ->
        true

      String.starts_with?(text, "hal:") ->
        true

      true ->
        false
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.PredicateFunctionNames
  defp is_reply_to_bot?(message, bot_info) do
    case message.reply_to_message do
      %{from: %{id: from_id}} when bot_info != nil ->
        from_id == bot_info.id

      _ ->
        false
    end
  end

  defp clean_mention(text, bot_info) do
    text
    |> remove_username_mention(bot_info)
    |> remove_common_prefixes()
    |> String.trim()
  end

  defp remove_username_mention(text, nil), do: text

  defp remove_username_mention(text, bot_info) do
    if bot_info.username do
      pattern = ~r/@#{Regex.escape(bot_info.username)}\s*/i
      Regex.replace(pattern, text, "")
    else
      text
    end
  end

  defp remove_common_prefixes(text) do
    text
    |> String.replace(~r/^@hal\s*/i, "")
    |> String.replace(~r/^hal:\s*/i, "")
  end

  defp get_or_create_user(telegram_user) do
    external_id = to_string(telegram_user.id)

    query =
      from u in User,
        where: u.external_id == ^external_id and u.platform == "telegram"

    case Repo.one(query) do
      nil ->
        {:ok, user} =
          %User{}
          |> User.changeset(%{
            external_id: external_id,
            platform: "telegram",
            username: telegram_user.username,
            settings: %{
              first_name: telegram_user.first_name,
              last_name: telegram_user.last_name,
              language_code: telegram_user.language_code
            }
          })
          |> Repo.insert()

        user

      user ->
        user
    end
  end

  defp answer_callback_query(callback_id) do
    try do
      ExGram.answer_callback_query(callback_id, bot: :hal_telegram_bot)
    rescue
      _ -> :ok
    end
  end
end
