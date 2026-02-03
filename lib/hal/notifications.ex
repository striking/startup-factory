defmodule Hal.Notifications do
  @moduledoc """
  Unified notification system that routes messages to users' preferred channels.

  This module provides:
  - Intelligent routing based on user preferences
  - Fallback handling when primary channels fail
  - Multi-channel delivery
  - Delivery confirmation tracking
  - Support for Telegram, Slack, Discord, and Email

  ## User Preferences

  User notification preferences are stored in the `users.settings` JSONB field:

      %{
        "notification_preferences" => %{
          "primary_channel" => "telegram",
          "fallback_channels" => ["slack", "email"],
          "telegram_chat_id" => "123456789",
          "slack_user_id" => "U123ABC",
          "discord_user_id" => "987654321",
          "email" => "user@example.com"
        }
      }

  ## Usage

      # Send to user's preferred channel
      Notifications.send(user, "Hello!")

      # Send via specific channel
      Notifications.send_telegram(user, "Hello via Telegram")

      # Send with options (fallback, etc.)
      Notifications.send(user, "Important!", fallback: true, urgent: true)

  ## Delivery Confirmation

  All send functions return:
  - `{:ok, %{channel: :telegram, message_id: "..."}}` on success
  - `{:error, reason}` on failure (after fallback attempts if enabled)
  """

  require Logger

  alias Hal.Accounts.User
  alias Hal.Channels.Telegram.Sender, as: TelegramSender
  alias HAL.Channels.Slack.Sender, as: SlackSender
  alias Hal.Channels.Discord.Sender, as: DiscordSender
  alias Hal.Mailer

  @type user :: %User{}
  @type message :: String.t()
  @type channel :: :telegram | :slack | :discord | :email
  @type send_result :: {:ok, map()} | {:error, term()}
  @type send_opts :: [
          fallback: boolean(),
          urgent: boolean(),
          channels: [channel()],
          reply_to: String.t()
        ]

  @valid_channels [:telegram, :slack, :discord, :email]

  @doc """
  Sends a notification to a user via their preferred channel.

  Automatically routes to the user's primary notification channel based on
  their preferences. If fallback is enabled and the primary channel fails,
  attempts delivery via fallback channels in order.

  ## Arguments

    * `user` - User struct with notification preferences
    * `message` - Text message to send
    * `opts` - Options (see below)

  ## Options

    * `:fallback` - Enable fallback to secondary channels (default: false)
    * `:urgent` - Mark as urgent, affects retry logic (default: false)
    * `:channels` - Override and send to specific channels (default: user preference)
    * `:reply_to` - Message ID to reply to (channel-specific format)

  ## Returns

    * `{:ok, %{channel: channel, message_id: id}}` - Success with delivery details
    * `{:error, reason}` - All channels failed

  ## Examples

      # Simple send to preferred channel
      {:ok, result} = Notifications.send(user, "Task completed!")

      # Send with fallback
      {:ok, result} = Notifications.send(user, "Critical alert!", fallback: true, urgent: true)

      # Send to specific channels
      {:ok, result} = Notifications.send(user, "Multi-channel message", channels: [:slack, :email])
  """
  @spec send(user(), message(), send_opts()) :: send_result()
  def send(user, message, opts \\ []) do
    channels = determine_channels(user, opts)

    case channels do
      [] ->
        Logger.warning("No notification channels configured for user #{user.id}")
        {:error, :no_channels_configured}

      [primary | fallbacks] ->
        result = send_to_channel(user, message, primary, opts)

        case {result, opts[:fallback]} do
          {{:ok, _} = success, _} ->
            success

          {{:error, reason}, true} when fallbacks != [] ->
            Logger.warning(
              "Primary channel #{primary} failed (#{inspect(reason)}), trying fallbacks: #{inspect(fallbacks)}"
            )

            try_fallbacks(user, message, fallbacks, opts, reason)

          {{:error, reason}, _} ->
            Logger.error("Failed to send notification via #{primary}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  Sends a notification via Telegram.

  ## Arguments

    * `user` - User struct (must have telegram_chat_id in settings)
    * `message` - Text message to send
    * `opts` - Options passed to Telegram sender

  ## Returns

    * `{:ok, %{channel: :telegram, message_id: id}}` - Success
    * `{:error, reason}` - Failure

  ## Examples

      Notifications.send_telegram(user, "Hello from Telegram!")
      Notifications.send_telegram(user, "*Bold*", parse_mode: "Markdown")
  """
  @spec send_telegram(user(), message(), keyword()) :: send_result()
  def send_telegram(user, message, opts \\ []) do
    case get_telegram_chat_id(user) do
      {:ok, chat_id} ->
        sender = Process.whereis(Hal.Channels.Telegram.Sender)

        if sender && Process.alive?(sender) do
          case TelegramSender.send_message(sender, chat_id, message, opts) do
            :ok ->
              {:ok, %{channel: :telegram, chat_id: chat_id}}

            {:error, reason} ->
              {:error, {:telegram, reason}}
          end
        else
          {:error, :telegram_sender_not_available}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends a notification via Slack.

  ## Arguments

    * `user` - User struct (must have slack_user_id or slack_channel in settings)
    * `message` - Text message to send
    * `opts` - Options passed to Slack sender

  ## Returns

    * `{:ok, %{channel: :slack, message_ts: ts}}` - Success
    * `{:error, reason}` - Failure

  ## Examples

      Notifications.send_slack(user, "Hello from Slack!")
      Notifications.send_slack(user, "Thread reply", thread_ts: "1234567890.123456")
  """
  @spec send_slack(user(), message(), keyword()) :: send_result()
  def send_slack(user, message, opts \\ []) do
    case get_slack_channel(user) do
      {:ok, channel_id} ->
        try do
          case SlackSender.send_message(channel_id, message, opts) do
            {:ok, %{"ts" => message_ts}} ->
              {:ok, %{channel: :slack, channel_id: channel_id, message_ts: message_ts}}

            {:error, reason} ->
              {:error, {:slack, reason}}
          end
        rescue
          RuntimeError -> {:error, {:slack, :not_configured}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends a notification via Discord.

  ## Arguments

    * `user` - User struct (must have discord_user_id or discord_channel in settings)
    * `message` - Text message to send
    * `opts` - Options passed to Discord sender

  ## Returns

    * `{:ok, %{channel: :discord, message_id: id}}` - Success
    * `{:error, reason}` - Failure

  ## Examples

      Notifications.send_discord(user, "Hello from Discord!")
      Notifications.send_discord(user, "Reply", reply_to: message_id)
  """
  @spec send_discord(user(), message(), keyword()) :: send_result()
  def send_discord(user, message, opts \\ []) do
    case get_discord_channel(user) do
      {:ok, channel_id} ->
        try do
          case DiscordSender.send_message(channel_id, message, opts) do
            {:ok, discord_message} ->
              {:ok, %{channel: :discord, channel_id: channel_id, message_id: discord_message.id}}

            {:error, reason} ->
              {:error, {:discord, reason}}
          end
        rescue
          ArgumentError -> {:error, {:discord, :invalid_channel}}
          _ -> {:error, {:discord, :send_failed}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends a notification via Email.

  ## Arguments

    * `user` - User struct (must have email in settings)
    * `message` - Email body (plain text or HTML)
    * `opts` - Options (subject, from, html)

  ## Options

    * `:subject` - Email subject line (required)
    * `:from` - Sender email (default: configured default)
    * `:html` - HTML version of message

  ## Returns

    * `{:ok, %{channel: :email, message_id: id}}` - Success
    * `{:error, reason}` - Failure

  ## Examples

      Notifications.send_email(user, "Task completed!", subject: "Notification")
      Notifications.send_email(user, "Plain text", subject: "Alert", html: "<p>HTML version</p>")
  """
  @spec send_email(user(), message(), keyword()) :: send_result()
  def send_email(user, message, opts \\ []) do
    case get_user_email(user) do
      {:ok, email} ->
        subject = Keyword.get(opts, :subject, "HAL Notification")
        from = Keyword.get(opts, :from, get_default_from_email())
        html = Keyword.get(opts, :html)

        email_struct =
          Swoosh.Email.new()
          |> Swoosh.Email.to(email)
          |> Swoosh.Email.from(from)
          |> Swoosh.Email.subject(subject)
          |> Swoosh.Email.text_body(message)

        email_struct =
          if html do
            Swoosh.Email.html_body(email_struct, html)
          else
            email_struct
          end

        case Mailer.deliver(email_struct) do
          {:ok, response} ->
            message_id = extract_email_message_id(response)
            {:ok, %{channel: :email, email: email, message_id: message_id}}

          {:error, reason} ->
            {:error, {:email, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private Functions

  @spec determine_channels(user(), send_opts()) :: [channel()]
  defp determine_channels(user, opts) do
    case Keyword.get(opts, :channels) do
      nil ->
        # Use user preferences
        get_user_channel_preferences(user)

      channels when is_list(channels) ->
        # Validate and use specified channels
        channels
        |> Enum.filter(&(&1 in @valid_channels))
        |> validate_user_has_channels(user)
    end
  end

  @spec get_user_channel_preferences(user()) :: [channel()]
  defp get_user_channel_preferences(user) do
    prefs = get_notification_preferences(user)

    # Handle case where prefs is not a map
    prefs = if is_map(prefs), do: prefs, else: %{}

    primary = String.to_existing_atom(prefs["primary_channel"] || user.platform)
    fallbacks = parse_fallback_channels(prefs["fallback_channels"] || [])

    [primary | fallbacks]
    |> Enum.uniq()
    |> Enum.filter(&(&1 in @valid_channels))
    |> validate_user_has_channels(user)
  rescue
    ArgumentError ->
      # Invalid atom in preferences, fall back to user platform
      [String.to_atom(user.platform)]
  end

  @spec parse_fallback_channels(list(String.t())) :: [channel()]
  defp parse_fallback_channels(fallbacks) when is_list(fallbacks) do
    Enum.map(fallbacks, fn channel ->
      String.to_existing_atom(channel)
    end)
  rescue
    ArgumentError -> []
  end

  defp parse_fallback_channels(_), do: []

  @spec validate_user_has_channels(list(channel()), user()) :: [channel()]
  defp validate_user_has_channels(channels, user) do
    Enum.filter(channels, fn channel ->
      has_channel_configured?(user, channel)
    end)
  end

  @spec has_channel_configured?(user(), channel()) :: boolean()
  defp has_channel_configured?(user, :telegram) do
    # Check if we have telegram chat_id, not whether sender is running
    prefs = get_notification_preferences(user)
    !!(prefs["telegram_chat_id"] || (user.platform == "telegram" && user.external_id))
  end

  defp has_channel_configured?(user, :slack) do
    # Check if we have slack channel info
    prefs = get_notification_preferences(user)

    !!(prefs["slack_channel"] || prefs["slack_user_id"] ||
         (user.platform == "slack" && user.external_id))
  end

  defp has_channel_configured?(user, :discord) do
    # Check if we have discord channel info
    prefs = get_notification_preferences(user)

    !!(prefs["discord_dm_channel"] || prefs["discord_user_id"] || prefs["discord_channel"] ||
         (user.platform == "discord" && user.external_id))
  end

  defp has_channel_configured?(user, :email) do
    # Check if we have valid email
    prefs = get_notification_preferences(user)
    email = prefs["email"]
    !!(email && String.contains?(email, "@"))
  end

  @spec send_to_channel(user(), message(), channel(), send_opts()) :: send_result()
  defp send_to_channel(user, message, :telegram, opts), do: send_telegram(user, message, opts)
  defp send_to_channel(user, message, :slack, opts), do: send_slack(user, message, opts)
  defp send_to_channel(user, message, :discord, opts), do: send_discord(user, message, opts)
  defp send_to_channel(user, message, :email, opts), do: send_email(user, message, opts)

  @spec try_fallbacks(user(), message(), [channel()], send_opts(), term()) :: send_result()
  defp try_fallbacks(user, message, [channel | rest], opts, _last_error) do
    Logger.info("Attempting fallback delivery via #{channel}")

    case send_to_channel(user, message, channel, opts) do
      {:ok, _} = success ->
        success

      {:error, reason} ->
        if rest == [] do
          Logger.error("All fallback channels exhausted")
          {:error, {:all_channels_failed, reason}}
        else
          try_fallbacks(user, message, rest, opts, reason)
        end
    end
  end

  defp try_fallbacks(_user, _message, [], _opts, last_error) do
    {:error, {:all_channels_failed, last_error}}
  end

  # User Setting Extractors

  @spec get_notification_preferences(user()) :: map()
  defp get_notification_preferences(user) do
    settings = if is_map(user.settings), do: user.settings, else: %{}
    prefs = settings["notification_preferences"]
    if is_map(prefs), do: prefs, else: %{}
  end

  @spec get_telegram_chat_id(user()) :: {:ok, String.t() | integer()} | {:error, atom()}
  defp get_telegram_chat_id(user) do
    prefs = get_notification_preferences(user)

    chat_id = prefs["telegram_chat_id"] || (user.platform == "telegram" && user.external_id)

    if chat_id do
      {:ok, chat_id}
    else
      {:error, :telegram_not_configured}
    end
  end

  @spec get_slack_channel(user()) :: {:ok, String.t()} | {:error, atom()}
  defp get_slack_channel(user) do
    prefs = get_notification_preferences(user)

    # Try DM first, then fall back to user_id (will open DM), then channel
    channel =
      prefs["slack_channel"] ||
        prefs["slack_user_id"] ||
        (user.platform == "slack" && user.external_id)

    if channel do
      {:ok, channel}
    else
      {:error, :slack_not_configured}
    end
  end

  @spec get_discord_channel(user()) :: {:ok, String.t() | integer()} | {:error, atom()}
  defp get_discord_channel(user) do
    prefs = get_notification_preferences(user)

    # Try DM channel first, then user_id, then regular channel
    channel =
      prefs["discord_dm_channel"] ||
        prefs["discord_user_id"] ||
        prefs["discord_channel"] ||
        (user.platform == "discord" && user.external_id)

    if channel do
      {:ok, channel}
    else
      {:error, :discord_not_configured}
    end
  end

  @spec get_user_email(user()) :: {:ok, String.t()} | {:error, atom()}
  defp get_user_email(user) do
    prefs = get_notification_preferences(user)
    email = prefs["email"]

    if email && String.contains?(email, "@") do
      {:ok, email}
    else
      {:error, :email_not_configured}
    end
  end

  @spec get_default_from_email() :: {String.t(), String.t()}
  defp get_default_from_email do
    from_email = Application.get_env(:hal, :notification_from_email, "notifications@hal.local")
    from_name = Application.get_env(:hal, :notification_from_name, "HAL Assistant")
    {from_name, from_email}
  end

  @spec extract_email_message_id(any()) :: String.t() | nil
  defp extract_email_message_id(%{id: id}), do: id
  defp extract_email_message_id(_), do: nil
end
