defmodule Hal.ChannelGateway do
  @moduledoc """
  Unified gateway for all messaging channels.

  Normalizes messages from different platforms (Telegram, Slack, Discord, Email, Terminal)
  into a standard format and routes to the appropriate session handler.

  ## Architecture

  ```
  [Telegram] ──┐
  [Slack]     ──┤
  [Discord]   ──┼──> [ChannelGateway] ──> [Router] ──> [SessionManager]
  [Email]     ──┤
  [Terminal]  ──┘
  ```

  ## Normalized Message Format

  All messages are normalized to this structure:

      %{
        user_id: binary(),              # User UUID from database
        text: String.t(),               # Message text content
        channel_type: atom(),           # :telegram, :slack, :discord, :email, :terminal
        channel_id: String.t(),         # Unique channel identifier
        attachments: list(),            # List of attachment maps
        metadata: map(),                # Channel-specific metadata
        timestamp: DateTime.t(),        # Message timestamp
        is_dm: boolean(),               # Whether this is a direct message
        mentions_bot: boolean()         # Whether the bot was mentioned
      }

  ## Usage

      # From Telegram handler
      ChannelGateway.route_message(:telegram, raw_telegram_message)

      # From Slack handler
      ChannelGateway.route_message(:slack, raw_slack_event)

      # Returns
      {:ok, response_text} | :ignored | {:error, reason}

  ## User Management

  The ChannelGateway automatically handles user lookup and creation.
  Users are uniquely identified by `{platform, external_id}` pairs.
  """

  require Logger

  alias Hal.Accounts.User
  alias Hal.Gateway.Router
  alias Hal.Repo

  import Ecto.Query

  @type channel_type :: :telegram | :slack | :discord | :email | :terminal
  @type raw_message :: map()

  @type normalized_message :: %{
          user_id: binary(),
          text: String.t(),
          channel_type: atom(),
          channel_id: String.t(),
          attachments: list(),
          metadata: map(),
          timestamp: DateTime.t(),
          is_dm: boolean(),
          mentions_bot: boolean()
        }

  @doc """
  Routes a message from any channel to the user's session.

  ## Arguments

    * `channel_type` - The channel type (`:telegram`, `:slack`, `:discord`, etc.)
    * `raw_message` - The raw message map from the channel
    * `opts` - Optional keyword list (e.g., `:router_name` for testing)

  ## Returns

    * `{:ok, response_text}` - Message processed successfully
    * `:ignored` - Message was ignored (e.g., group message without mention)
    * `{:error, reason}` - Error occurred

  ## Examples

      # From Telegram
      ChannelGateway.route_message(:telegram, %{
        from: %{id: 123, username: "john"},
        chat: %{id: 456, type: "private"},
        text: "Hello HAL",
        date: 1234567890
      })

      # From Slack
      ChannelGateway.route_message(:slack, %{
        "user" => "U123",
        "channel" => "C456",
        "text" => "Hello HAL",
        "ts" => "1234567890.123"
      })
  """
  @spec route_message(channel_type(), raw_message(), keyword()) ::
          {:ok, String.t()} | :ignored | {:error, term()}
  def route_message(channel_type, raw_message, opts \\ []) do
    # Normalize message based on channel
    with {:ok, normalized} <- normalize_message(channel_type, raw_message) do
      # Route to Gateway.Router
      router_name = Keyword.get(opts, :router_name, Hal.Gateway.Router)
      Router.route_message(router_name, normalized, opts)
    end
  end

  @doc """
  Normalizes a raw message from a specific channel into the standard format.

  This function handles all channel-specific message parsing and user lookup/creation.

  ## Examples

      iex> normalize_message(:telegram, telegram_msg)
      {:ok, %{user_id: "uuid", text: "hello", ...}}

      iex> normalize_message(:invalid_channel, msg)
      {:error, :unsupported_channel}
  """
  @spec normalize_message(channel_type(), raw_message()) ::
          {:ok, normalized_message()} | {:error, term()}
  def normalize_message(:telegram, msg), do: normalize_telegram(msg)
  def normalize_message(:slack, msg), do: normalize_slack(msg)
  def normalize_message(:discord, msg), do: normalize_discord(msg)
  def normalize_message(:email, msg), do: normalize_email(msg)
  def normalize_message(:terminal, msg), do: normalize_terminal(msg)
  def normalize_message(_unsupported, _msg), do: {:error, :unsupported_channel}

  # Normalize Telegram messages
  defp normalize_telegram(msg) do
    with {:ok, user_id} <- get_or_create_user_id("telegram", msg.from.id, msg.from) do
      text = Map.get(msg, :text) || Map.get(msg, :caption, "")

      {:ok,
       %{
         user_id: user_id,
         text: text,
         channel_type: :telegram,
         channel_id: to_string(msg.chat.id),
         attachments: extract_telegram_attachments(msg),
         metadata: %{
           message_id: msg.message_id,
           chat_type: msg.chat.type,
           telegram_user_id: msg.from.id,
           username: Map.get(msg.from, :username),
           first_name: Map.get(msg.from, :first_name)
         },
         timestamp: DateTime.from_unix!(msg.date),
         is_dm: msg.chat.type == "private",
         mentions_bot: Map.get(msg, :mentions_bot, false)
       }}
    end
  end

  # Normalize Slack messages
  defp normalize_slack(msg) do
    with {:ok, user_id} <- get_or_create_user_id("slack", msg["user"], %{}) do
      ts = parse_slack_timestamp(msg["ts"])

      {:ok,
       %{
         user_id: user_id,
         text: msg["text"] || "",
         channel_type: :slack,
         channel_id: msg["channel"],
         attachments: extract_slack_attachments(msg),
         metadata: %{
           ts: msg["ts"],
           thread_ts: msg["thread_ts"],
           raw_channel_id: msg["channel"]
         },
         timestamp: ts,
         is_dm: String.starts_with?(msg["channel"], "D"),
         mentions_bot: Map.get(msg, "mentions_bot", false)
       }}
    end
  end

  # Normalize Discord messages
  defp normalize_discord(msg) do
    with {:ok, user_id} <- get_or_create_user_id("discord", msg.author.id, msg.author) do
      {:ok,
       %{
         user_id: user_id,
         text: msg.content || "",
         channel_type: :discord,
         channel_id: to_string(msg.channel_id),
         attachments: extract_discord_attachments(msg),
         metadata: %{
           message_id: msg.id,
           guild_id: msg.guild_id,
           discord_user_id: msg.author.id,
           username: msg.author.username
         },
         timestamp: msg.timestamp,
         is_dm: msg.guild_id == nil,
         mentions_bot: Map.get(msg, :mentions_bot, false)
       }}
    end
  end

  # Normalize Email messages
  defp normalize_email(msg) do
    with {:ok, user_id} <- get_or_create_user_id("email", msg.from_email, %{}) do
      {:ok,
       %{
         user_id: user_id,
         text: Map.get(msg, :body, ""),
         channel_type: :email,
         channel_id: msg.from_email,
         attachments: Map.get(msg, :attachments, []),
         metadata: %{
           subject: Map.get(msg, :subject),
           message_id: Map.get(msg, :message_id),
           from_email: msg.from_email
         },
         timestamp: Map.get(msg, :timestamp) || DateTime.utc_now(),
         is_dm: true,
         mentions_bot: true
       }}
    end
  end

  # Normalize Terminal messages
  defp normalize_terminal(msg) do
    user_identifier = Map.get(msg, :user_id, "default")
    text = Map.get(msg, :text) || Map.get(msg, :input, "")
    session_id = Map.get(msg, :session_id, "terminal")

    with {:ok, user_id} <- get_or_create_user_id("terminal", user_identifier, %{}) do
      {:ok,
       %{
         user_id: user_id,
         text: text,
         channel_type: :terminal,
         channel_id: session_id,
         attachments: [],
         metadata: %{},
         timestamp: DateTime.utc_now(),
         is_dm: true,
         mentions_bot: true
       }}
    end
  end

  # Helper functions for attachment extraction
  defp extract_telegram_attachments(msg) do
    attachments = []

    # Extract photo
    attachments =
      case Map.get(msg, :photo) do
        nil ->
          attachments

        photos when is_list(photos) ->
          largest_photo = Enum.max_by(photos, & &1.file_size)

          [
            %{
              type: "photo",
              file_id: largest_photo.file_id,
              file_size: largest_photo.file_size
            }
            | attachments
          ]

        _ ->
          attachments
      end

    # Extract document
    attachments =
      case Map.get(msg, :document) do
        nil ->
          attachments

        document ->
          [
            %{
              type: "document",
              file_id: document.file_id,
              file_name: document.file_name,
              mime_type: document.mime_type,
              file_size: document.file_size
            }
            | attachments
          ]
      end

    # Extract voice
    attachments =
      case Map.get(msg, :voice) do
        nil ->
          attachments

        voice ->
          [
            %{
              type: "voice",
              file_id: voice.file_id,
              duration: voice.duration,
              mime_type: voice.mime_type
            }
            | attachments
          ]
      end

    # Extract audio
    attachments =
      case Map.get(msg, :audio) do
        nil ->
          attachments

        audio ->
          [
            %{
              type: "audio",
              file_id: audio.file_id,
              duration: audio.duration,
              performer: audio.performer,
              title: audio.title
            }
            | attachments
          ]
      end

    Enum.reverse(attachments)
  end

  defp extract_slack_attachments(msg) do
    files = msg["files"] || []

    Enum.map(files, fn file ->
      %{
        type: "file",
        id: file["id"],
        name: file["name"],
        title: file["title"],
        mimetype: file["mimetype"],
        filetype: file["filetype"],
        url_private: file["url_private"],
        size: file["size"]
      }
    end)
  end

  defp extract_discord_attachments(msg) do
    attachments = Map.get(msg, :attachments, [])

    Enum.map(attachments, fn att ->
      %{
        type: "attachment",
        id: att.id,
        filename: att.filename,
        url: att.url,
        size: att.size,
        content_type: att.content_type
      }
    end)
  end

  # User lookup/creation with error handling
  defp get_or_create_user_id(platform, external_id, user_info) when is_binary(external_id) do
    case find_or_create_user(platform, external_id, user_info) do
      {:ok, user} -> {:ok, user.id}
      {:error, reason} -> {:error, {:user_creation_failed, reason}}
    end
  end

  defp get_or_create_user_id(platform, external_id, user_info) do
    get_or_create_user_id(platform, to_string(external_id), user_info)
  end

  defp find_or_create_user(platform, external_id, user_info) do
    query =
      from u in User,
        where: u.external_id == ^external_id and u.platform == ^platform

    case Repo.one(query) do
      nil ->
        create_user(platform, external_id, user_info)

      user ->
        {:ok, user}
    end
  end

  defp create_user(platform, external_id, user_info) do
    attrs = %{
      external_id: external_id,
      platform: platform,
      username: extract_username(user_info),
      settings: extract_settings(platform, user_info)
    }

    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  defp extract_username(%{username: username}) when is_binary(username), do: username
  defp extract_username(%{"username" => username}) when is_binary(username), do: username

  defp extract_username(%{first_name: first_name, last_name: nil}),
    do: first_name

  defp extract_username(%{first_name: first_name, last_name: last_name}),
    do: "#{first_name} #{last_name}"

  defp extract_username(_), do: nil

  defp extract_settings("telegram", user_info) do
    %{
      first_name: Map.get(user_info, :first_name),
      last_name: Map.get(user_info, :last_name),
      language_code: Map.get(user_info, :language_code)
    }
  end

  defp extract_settings("slack", _user_info), do: %{}

  defp extract_settings("discord", user_info) do
    %{
      username: Map.get(user_info, :username),
      discriminator: Map.get(user_info, :discriminator)
    }
  end

  defp extract_settings(_platform, _user_info), do: %{}

  defp parse_slack_timestamp(ts) when is_binary(ts) do
    [seconds, _microseconds] = String.split(ts, ".")
    DateTime.from_unix!(String.to_integer(seconds))
  end

  defp parse_slack_timestamp(_), do: DateTime.utc_now()
end
