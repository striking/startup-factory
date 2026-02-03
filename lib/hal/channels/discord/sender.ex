defmodule Hal.Channels.Discord.Sender do
  @moduledoc """
  Module for sending messages to Discord channels.

  Provides utilities for:
  - Sending simple text messages
  - Sending messages with embeds
  - Sending messages with attachments
  - Chunking long messages (Discord has a 2000 char limit)
  - Replying to specific messages (thread support)

  ## Usage

      # Send a simple message
      Sender.send_message(channel_id, "Hello!")

      # Reply to a message
      Sender.send_message(channel_id, "Reply text", reply_to: message_id)

      # Send with an embed
      embed = Sender.build_embed(title: "Title", description: "Description")
      Sender.send_message(channel_id, "", embed: embed)

      # Send a long message (auto-chunked)
      Sender.send_message(channel_id, very_long_text)
  """

  require Logger

  alias Nostrum.Api.Message

  @discord_max_message_length 2000

  # Discord embed colors
  @colors %{
    success: 0x57F287,
    error: 0xED4245,
    warning: 0xFEE75C,
    info: 0x5865F2,
    default: 0x2B2D31
  }

  @doc """
  Sends a message to a Discord channel.

  ## Options

    * `:reply_to` - Message ID to reply to (creates a thread context)
    * `:embed` - Embed map to include
    * `:file` - File path to attach

  ## Examples

      # Simple message
      Sender.send_message(123456, "Hello!")

      # Reply to a message
      Sender.send_message(123456, "Response", reply_to: 789012)

      # With embed
      Sender.send_message(123456, "", embed: %{title: "Title"})
  """
  @spec send_message(integer() | String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def send_message(channel_id, content, opts \\ []) do
    channel_id = ensure_integer(channel_id)

    # Check if we need to chunk the message
    if String.length(content) > @discord_max_message_length and !opts[:embed] do
      send_chunked_message(channel_id, content, opts)
    else
      send_single_message(channel_id, content, opts)
    end
  end

  @doc """
  Builds message options for Nostrum API.

  Converts our options format to Nostrum's expected format.
  """
  @spec build_message_opts(String.t(), keyword()) :: keyword()
  def build_message_opts(content, opts \\ []) do
    base_opts = [content: content]

    base_opts
    |> maybe_add_reply(opts[:reply_to])
    |> maybe_add_embed(opts[:embed])
    |> maybe_add_file(opts[:file])
  end

  @doc """
  Chunks a message into segments that fit Discord's character limit.

  ## Options

    * `:max_length` - Maximum length per chunk (default: 2000)

  ## Examples

      iex> Sender.chunk_message("short")
      ["short"]

      iex> long_msg = String.duplicate("a", 2500)
      iex> chunks = Sender.chunk_message(long_msg)
      iex> length(chunks)
      2
  """
  @spec chunk_message(String.t(), keyword()) :: [String.t()]
  def chunk_message(message, opts \\ []) do
    max_length = Keyword.get(opts, :max_length, @discord_max_message_length)
    do_chunk_message(message, max_length, [])
  end

  @doc """
  Formats content as a Discord code block.

  ## Examples

      iex> Sender.format_code_block("code")
      "```\\ncode\\n```"

      iex> Sender.format_code_block("code", "elixir")
      "```elixir\\ncode\\n```"
  """
  @spec format_code_block(String.t(), String.t() | nil) :: String.t()
  def format_code_block(content, language \\ nil) do
    lang_hint = if language, do: language, else: ""
    "```#{lang_hint}\n#{content}\n```"
  end

  @doc """
  Builds an embed map for Discord.

  ## Options

    * `:title` - Embed title
    * `:description` - Embed description
    * `:color` - Color atom (:success, :error, :warning, :info) or hex integer
    * `:fields` - List of field maps with :name, :value, and optional :inline
    * `:footer` - Footer text
    * `:thumbnail` - Thumbnail URL
    * `:image` - Image URL

  ## Examples

      Sender.build_embed(
        title: "Success",
        description: "Operation completed",
        color: :success
      )

      Sender.build_embed(
        title: "Status",
        fields: [
          %{name: "Status", value: "Online", inline: true},
          %{name: "Uptime", value: "2 hours", inline: true}
        ]
      )
  """
  @spec build_embed(keyword()) :: map()
  def build_embed(opts) do
    embed = %{}

    embed
    |> maybe_put(:title, opts[:title])
    |> maybe_put(:description, opts[:description])
    |> maybe_put(:color, resolve_color(opts[:color]))
    |> maybe_put(:fields, opts[:fields])
    |> maybe_put(:footer, build_footer(opts[:footer]))
    |> maybe_put(:thumbnail, build_url_map(opts[:thumbnail]))
    |> maybe_put(:image, build_url_map(opts[:image]))
  end

  # Private Functions

  defp send_single_message(channel_id, content, opts) do
    message_opts = build_message_opts(content, opts)

    case Message.create(channel_id, message_opts) do
      {:ok, msg} ->
        Logger.debug("Discord: Sent message to channel #{channel_id}")
        {:ok, msg}

      {:error, reason} ->
        Logger.error("Discord: Failed to send message: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp send_chunked_message(channel_id, content, opts) do
    chunks = chunk_message(content)

    # Send all chunks, replying only on the first one
    results =
      chunks
      |> Enum.with_index()
      |> Enum.map(fn {chunk, index} ->
        chunk_opts = if index == 0, do: opts, else: Keyword.delete(opts, :reply_to)
        send_single_message(channel_id, chunk, chunk_opts)
      end)

    # Return the last result
    List.last(results)
  end

  defp do_chunk_message("", _max_length, acc), do: Enum.reverse(acc)

  defp do_chunk_message(message, max_length, acc) do
    if String.length(message) <= max_length do
      Enum.reverse([message | acc])
    else
      {chunk, rest} = String.split_at(message, max_length)
      do_chunk_message(rest, max_length, [chunk | acc])
    end
  end

  defp maybe_add_reply(opts, nil), do: opts

  defp maybe_add_reply(opts, message_id) do
    Keyword.put(opts, :message_reference, %{message_id: message_id})
  end

  defp maybe_add_embed(opts, nil), do: opts
  defp maybe_add_embed(opts, embed), do: Keyword.put(opts, :embeds, [embed])

  defp maybe_add_file(opts, nil), do: opts
  defp maybe_add_file(opts, file_path), do: Keyword.put(opts, :file, file_path)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp resolve_color(nil), do: nil
  defp resolve_color(color) when is_atom(color), do: Map.get(@colors, color, @colors.default)
  defp resolve_color(color) when is_integer(color), do: color

  defp build_footer(nil), do: nil
  defp build_footer(text) when is_binary(text), do: %{text: text}
  defp build_footer(footer) when is_map(footer), do: footer

  defp build_url_map(nil), do: nil
  defp build_url_map(url) when is_binary(url), do: %{url: url}
  defp build_url_map(map) when is_map(map), do: map

  defp ensure_integer(id) when is_integer(id), do: id
  defp ensure_integer(id) when is_binary(id), do: String.to_integer(id)
end
