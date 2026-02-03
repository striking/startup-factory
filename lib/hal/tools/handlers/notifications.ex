defmodule Hal.Tools.Handlers.Notifications do
  @moduledoc """
  Handler for HAL notification tool operations.

  Routes notifications to appropriate channels (Telegram, Email).
  Requires channel configuration to send real notifications.
  """

  require Logger
  alias Hal.Tools.Executor

  @doc """
  Send a notification to the user.

  ## Arguments

    * `args` - Map containing:
      * `"message"` - The notification message (required)
      * `"channel"` - Channel type: telegram, email, auto (default: auto)
      * `"priority"` - Priority: low, normal, high, urgent (default: normal)
      * `"silent"` - Send without sound/vibration (default: false)
    * `opts` - Context options with `:user_id`, `:channel_type`, `:channel_id`
  """
  @spec send(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def send(args, opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    message = Map.get(args, "message")

    if is_nil(message) do
      Executor.return_error("Missing required argument: message")
    else
      channel = Map.get(args, "channel", "auto")
      priority = Map.get(args, "priority", "normal")
      silent = Map.get(args, "silent", false)

      # Determine which channel to use
      target_channel = resolve_channel(channel, opts)
      target_channel_id = Keyword.get(opts, :channel_id) || get_default_channel_id(target_channel)

      Logger.info(
        "Sending notification to #{target_channel} for user #{user_id}, priority: #{priority}"
      )

      # Format message with priority indicator
      formatted_message = format_message(message, priority, silent)

      result = send_to_channel(target_channel, target_channel_id, formatted_message, silent)

      case result do
        {:ok, details} ->
          Executor.return_success("Notification sent successfully", details)

        {:error, :channel_not_configured} ->
          Executor.return_error(
            "Notification channel not configured",
            "No #{target_channel} channel configured. Set TELEGRAM_BOT_TOKEN and TELEGRAM_ADMIN_CHAT_ID for Telegram notifications."
          )

        {:error, :channel_not_available} ->
          Executor.return_error(
            "Notification channel not available",
            "The #{target_channel} channel is not running. Check that the channel service is started."
          )

        {:error, reason} ->
          Executor.return_error("Failed to send notification", inspect(reason))
      end
    end
  rescue
    e ->
      Logger.error("Notification send failed: #{Exception.message(e)}")
      Executor.return_error("Notification send failed", Exception.message(e))
  end

  # Private helpers

  defp resolve_channel("auto", opts) do
    # Use the current conversation channel if available, otherwise telegram
    Keyword.get(opts, :channel_type, "telegram")
  end

  defp resolve_channel(specific_channel, _opts), do: specific_channel

  defp get_default_channel_id("telegram") do
    # Use admin chat ID from environment for proactive notifications
    System.get_env("TELEGRAM_ADMIN_CHAT_ID")
  end

  defp get_default_channel_id("email") do
    # Use admin email from environment
    System.get_env("HAL_ADMIN_EMAIL")
  end

  defp get_default_channel_id(_), do: nil

  defp format_message(message, priority, silent) do
    formatted =
      case priority do
        "urgent" -> "🚨 URGENT: #{message}"
        "high" -> "⚠️ #{message}"
        "low" -> "ℹ️ #{message}"
        _ -> message
      end

    if silent do
      "🔇 #{formatted}"
    else
      formatted
    end
  end

  defp send_to_channel("telegram", nil, _message, _silent) do
    {:error, :channel_not_configured}
  end

  defp send_to_channel("telegram", chat_id, message, silent) do
    # Check if Telegram sender is running
    case Process.whereis(Hal.Channels.Telegram.Sender) do
      nil ->
        {:error, :channel_not_available}

      _pid ->
        opts = if silent, do: [disable_notification: true], else: []

        case Hal.Channels.Telegram.Sender.send_message(
               Hal.Channels.Telegram.Sender,
               chat_id,
               message,
               opts
             ) do
          :ok ->
            {:ok,
             %{
               channel: "telegram",
               chat_id: chat_id,
               sent_at: DateTime.utc_now() |> DateTime.to_iso8601()
             }}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp send_to_channel("email", nil, _message, _silent) do
    {:error, :channel_not_configured}
  end

  defp send_to_channel("email", email_address, message, _silent) do
    # Check if Google credentials are available for sending email
    case HAL.Credentials.get_google_token() do
      {:ok, token} ->
        # Use the Email integration to send
        case HAL.Integrations.Email.send_email(token,
               to: email_address,
               subject: "HAL Notification",
               body: message
             ) do
          {:ok, _} ->
            {:ok,
             %{
               channel: "email",
               to: email_address,
               sent_at: DateTime.utc_now() |> DateTime.to_iso8601()
             }}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :not_found} ->
        {:error, :channel_not_configured}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_to_channel(unknown_channel, _channel_id, _message, _silent) do
    Logger.warning("Unknown notification channel: #{unknown_channel}")
    {:error, {:unknown_channel, unknown_channel}}
  end
end
