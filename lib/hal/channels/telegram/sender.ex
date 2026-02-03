defmodule Hal.Channels.Telegram.Sender do
  @moduledoc """
  Sends responses back to Telegram users.

  The Sender is responsible for:
  - Sending text messages with proper formatting
  - Sending voice messages (via TTS)
  - Handling rate limits with exponential backoff
  - Splitting long messages that exceed Telegram's limit
  - Error handling and retry logic

  ## Rate Limiting

  Telegram has rate limits:
  - ~30 messages/second to different users
  - ~1 message/second to the same group

  The Sender handles 429 (Too Many Requests) responses by
  backing off for the time specified in the `retry_after` header.

  ## Message Length

  Telegram messages are limited to 4096 characters.
  Long messages are automatically split into multiple parts.

  ## Usage

      # Send a text message
      Sender.send_message(sender, chat_id, "Hello!")

      # Send with options
      Sender.send_message(sender, chat_id, "Hello!", parse_mode: "Markdown")

      # Send a voice message
      Sender.send_voice(sender, chat_id, "Hello, this is HAL speaking.")
  """

  use GenServer
  require Logger

  @max_message_length 4096
  @max_retries 3
  @base_backoff_ms 1000

  defstruct [
    :bot_token
  ]

  # Client API

  @doc """
  Starts the Sender GenServer.

  ## Options

    * `:name` - The name to register under (required)
    * `:bot_token` - Telegram bot token
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Sends a text message to a Telegram chat.

  ## Options

    * `:parse_mode` - "Markdown" or "HTML" (default: none)
    * `:reply_to_message_id` - Message ID to reply to
    * `:disable_notification` - Send silently (default: false)
    * `:disable_web_page_preview` - Disable link previews (default: false)

  ## Examples

      Sender.send_message(sender, 123456789, "Hello!")
      Sender.send_message(sender, 123456789, "*Bold text*", parse_mode: "Markdown")
  """
  @spec send_message(GenServer.server(), integer() | String.t(), String.t(), keyword()) ::
          :ok | {:error, term()}
  def send_message(server, chat_id, text, opts \\ []) do
    GenServer.call(server, {:send_message, chat_id, text, opts}, 60_000)
  end

  @doc """
  Sends a voice message to a Telegram chat.

  The text is first converted to speech using ElevenLabs TTS,
  then sent as a voice message.

  ## Options

    * `:reply_to_message_id` - Message ID to reply to
    * `:disable_notification` - Send silently (default: false)

  ## Examples

      Sender.send_voice(sender, 123456789, "Hello, this is HAL speaking.")
  """
  @spec send_voice(GenServer.server(), integer() | String.t(), String.t(), keyword()) ::
          :ok | {:error, term()}
  def send_voice(server, chat_id, text, opts \\ []) do
    GenServer.call(server, {:send_voice, chat_id, text, opts}, 120_000)
  end

  @doc """
  Sends a typing indicator to show the bot is working.

  Useful for long-running operations.
  """
  @spec send_typing(GenServer.server(), integer() | String.t()) :: :ok
  def send_typing(server, chat_id) do
    GenServer.cast(server, {:send_typing, chat_id})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      bot_token: Keyword.get(opts, :bot_token)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:send_message, chat_id, text, opts}, _from, state) do
    result = do_send_message(chat_id, text, opts)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:send_voice, chat_id, text, opts}, _from, state) do
    result = do_send_voice(chat_id, text, opts)
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:send_typing, chat_id}, state) do
    do_send_typing(chat_id)
    {:noreply, state}
  end

  # Private functions

  defp do_send_message(chat_id, text, opts) do
    with {:ok, chat_id} <- normalize_chat_id(chat_id) do
      # Split long messages
      chunks = split_message(text)

      results =
        Enum.map(chunks, fn chunk ->
          send_with_retry(chat_id, chunk, opts, 0)
        end)

      # Return error if any chunk failed
      case Enum.find(results, &match?({:error, _}, &1)) do
        nil -> :ok
        error -> error
      end
    end
  end

  defp send_with_retry(chat_id, text, opts, attempt) when attempt < @max_retries do
    case ExGram.send_message(chat_id, text, build_send_opts(opts)) do
      {:ok, _message} ->
        :ok

      {:error, %ExGram.Error{code: 429, message: message}} ->
        # Rate limited - extract retry_after and back off
        retry_after = extract_retry_after(message)
        Logger.warning("Telegram rate limit hit, waiting #{retry_after}ms")
        Process.sleep(retry_after)
        send_with_retry(chat_id, text, opts, attempt + 1)

      {:error, %ExGram.Error{code: code, message: _message}} when code in [500, 502, 503, 504] ->
        # Server error - exponential backoff
        backoff = (@base_backoff_ms * :math.pow(2, attempt)) |> round()
        Logger.warning("Telegram server error #{code}, retrying in #{backoff}ms")
        Process.sleep(backoff)
        send_with_retry(chat_id, text, opts, attempt + 1)

      {:error, error} ->
        Logger.error("Failed to send Telegram message: #{inspect(error)}")
        {:error, error}
    end
  end

  defp send_with_retry(_chat_id, _text, _opts, _attempt) do
    {:error, :max_retries_exceeded}
  end

  defp build_send_opts(opts) do
    base_opts = [bot: :hal_telegram_bot]

    opts
    |> Keyword.take([
      :parse_mode,
      :reply_to_message_id,
      :disable_notification,
      :disable_web_page_preview
    ])
    |> Keyword.merge(base_opts)
  end

  defp do_send_voice(chat_id, text, opts) do
    with {:ok, chat_id} <- normalize_chat_id(chat_id) do
      # First synthesize the speech
      case HAL.Voice.TTS.synthesize(text) do
        {:ok, audio_path} ->
          # Send the voice message
          result = send_voice_file(chat_id, audio_path, opts)
          # Clean up the temp file
          HAL.Voice.TTS.cleanup(audio_path)
          result

        {:error, reason} ->
          Logger.error("Failed to synthesize voice: #{reason}")
          # Fall back to text message
          do_send_message(chat_id, text, opts)
      end
    end
  end

  defp send_voice_file(chat_id, file_path, opts) do
    voice_opts =
      opts
      |> Keyword.take([:reply_to_message_id, :disable_notification])
      |> Keyword.merge(bot: :hal_telegram_bot)

    case ExGram.send_voice(chat_id, {:file, file_path}, voice_opts) do
      {:ok, _message} ->
        :ok

      {:error, error} ->
        Logger.error("Failed to send voice message: #{inspect(error)}")
        {:error, error}
    end
  end

  defp do_send_typing(chat_id) do
    case normalize_chat_id(chat_id) do
      {:ok, chat_id} ->
        try do
          ExGram.send_chat_action(chat_id, "typing", bot: :hal_telegram_bot)
        rescue
          e ->
            Logger.debug("Failed to send typing indicator: #{Exception.message(e)}")
        end

      {:error, _reason} ->
        :ok
    end
  end

  defp normalize_chat_id(chat_id) when is_binary(chat_id) do
    case Integer.parse(chat_id) do
      {chat_id, ""} -> {:ok, chat_id}
      _ -> {:error, :invalid_chat_id}
    end
  end

  defp normalize_chat_id(chat_id) when is_integer(chat_id), do: {:ok, chat_id}

  defp normalize_chat_id(_chat_id), do: {:error, :invalid_chat_id}

  defp split_message(text) when byte_size(text) <= @max_message_length do
    [text]
  end

  defp split_message(text) do
    # Try to split at paragraph breaks first, then sentences, then words
    do_split_message(text, [])
  end

  defp do_split_message("", acc), do: Enum.reverse(acc)

  defp do_split_message(text, acc) when byte_size(text) <= @max_message_length do
    Enum.reverse([text | acc])
  end

  defp do_split_message(text, acc) do
    # Find a good split point
    {chunk, rest} = find_split_point(text)
    do_split_message(rest, [chunk | acc])
  end

  defp find_split_point(text) do
    # Take first chunk up to max length
    chunk = String.slice(text, 0, @max_message_length)

    # Try to find a good break point (paragraph, sentence, word)
    split_index =
      find_paragraph_break(chunk) ||
        find_sentence_break(chunk) ||
        find_word_break(chunk) ||
        @max_message_length

    chunk = String.slice(text, 0, split_index) |> String.trim_trailing()
    rest = String.slice(text, split_index, String.length(text)) |> String.trim_leading()

    {chunk, rest}
  end

  defp find_paragraph_break(text) do
    # Look for double newline in the last 20% of the chunk
    start_search = round(String.length(text) * 0.8)
    search_area = String.slice(text, start_search, String.length(text))

    case :binary.match(search_area, "\n\n") do
      {pos, _} -> start_search + pos + 2
      :nomatch -> nil
    end
  end

  defp find_sentence_break(text) do
    # Look for sentence endings in the last 30%
    start_search = round(String.length(text) * 0.7)
    search_area = String.slice(text, start_search, String.length(text))

    # Find last sentence ending
    patterns = [". ", "! ", "? ", ".\n", "!\n", "?\n"]

    patterns
    |> Enum.map(fn pattern ->
      case String.split(search_area, pattern, parts: 2) do
        [first, _rest] -> start_search + String.length(first) + String.length(pattern)
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(fn -> nil end)
  end

  defp find_word_break(text) do
    # Look for space in the last 10%
    start_search = round(String.length(text) * 0.9)
    search_area = String.slice(text, start_search, String.length(text))

    case :binary.match(search_area, " ") do
      {pos, _} -> start_search + pos + 1
      :nomatch -> nil
    end
  end

  defp extract_retry_after(message) do
    # Try to extract retry_after from error message
    case Regex.run(~r/retry after (\d+)/i, message) do
      [_, seconds] ->
        String.to_integer(seconds) * 1000

      _ ->
        # Default to 5 seconds
        5000
    end
  end
end
