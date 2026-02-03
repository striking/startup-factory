defmodule HAL.Automation.Workers.ScheduledTask do
  @moduledoc """
  Oban worker for executing scheduled tasks.

  This worker handles one-time and recurring scheduled tasks that send prompts
  to Claude Code via an existing session. Results are broadcast back through
  the appropriate channel (Telegram, Slack, Discord).

  ## Job Args

    * `session_id` - The database session ID to use for context
    * `prompt` - The prompt to send to Claude
    * `respond_via` - (optional) Channel info for sending responses back
      * `channel_type` - telegram, slack, discord
      * `channel_id` - Platform-specific channel identifier
    * `metadata` - (optional) Additional metadata for the task

  ## Examples

      # Schedule a one-time task
      %{session_id: "uuid", prompt: "Check my GitHub notifications"}
      |> HAL.Automation.Workers.ScheduledTask.new(scheduled_at: ~U[2026-01-28 09:00:00Z])
      |> Oban.insert()

      # Schedule a recurring task (via Oban.Pro.Cron or manual rescheduling)
      %{session_id: "uuid", prompt: "Daily standup summary"}
      |> HAL.Automation.Workers.ScheduledTask.new()
      |> Oban.insert()

  """

  use Oban.Worker,
    queue: :scheduled,
    max_attempts: 3,
    priority: 1

  require Logger

  alias Hal.Gateway.SessionManager
  alias Hal.Gateway.SessionServer

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    session_id = Map.fetch!(args, "session_id")
    prompt = Map.fetch!(args, "prompt")
    respond_via = Map.get(args, "respond_via", %{})
    metadata = Map.get(args, "metadata", %{})

    Logger.info("Executing scheduled task for session #{session_id}: #{truncate(prompt, 50)}")

    with {:ok, session_pid} <- get_or_start_session(session_id),
         {:ok, response} <- execute_prompt(session_pid, prompt, metadata) do
      # Send response back through the channel if specified
      maybe_send_response(respond_via, response)

      Logger.info("Scheduled task completed successfully for session #{session_id}")
      :ok
    else
      {:error, :session_not_found} ->
        Logger.error("Session #{session_id} not found for scheduled task")
        {:error, "Session not found: #{session_id}"}

      {:error, reason} ->
        Logger.error("Scheduled task failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Get the session pid or start a new session server if needed
  defp get_or_start_session(session_id) do
    # Try to find the session in the database first
    case Hal.Repo.get(Hal.Gateway.Session, session_id) do
      nil ->
        {:error, :session_not_found}

      session ->
        # Try to get the session from SessionManager
        session_manager = Hal.Gateway.SessionManager

        session_pid =
          SessionManager.get_session(
            session_manager,
            session.channel_type,
            session.channel_id,
            session.user_id
          )

        if session_pid do
          {:ok, session_pid}
        else
          # Session not running, start it via SessionManager
          SessionManager.get_or_create_session(
            session_manager,
            session.channel_type,
            session.channel_id,
            session.user_id
          )
        end
    end
  end

  defp execute_prompt(session_pid, prompt, metadata) do
    opts = if map_size(metadata) > 0, do: [metadata: metadata], else: []
    SessionServer.handle_message(session_pid, prompt, opts)
  end

  defp maybe_send_response(
         %{"channel_type" => channel_type, "channel_id" => channel_id},
         response
       ) do
    case channel_type do
      "telegram" ->
        # Send via Telegram
        send_telegram_response(channel_id, response)

      "slack" ->
        # Send via Slack
        send_slack_response(channel_id, response)

      "discord" ->
        # Send via Discord
        send_discord_response(channel_id, response)

      _ ->
        Logger.warning("Unknown channel type for response: #{channel_type}")
        :ok
    end
  end

  defp maybe_send_response(_, _response), do: :ok

  defp send_telegram_response(chat_id, response) do
    # Telegram Sender is a GenServer, need to use the registered name
    case Hal.Channels.Telegram.Sender.send_message(
           Hal.Channels.Telegram.Sender,
           chat_id,
           response
         ) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to send Telegram response: #{inspect(reason)}")
        :ok
    end
  rescue
    e ->
      Logger.warning("Telegram sender not available: #{Exception.message(e)}")
      :ok
  end

  defp send_slack_response(channel_id, response) do
    case HAL.Channels.Slack.Sender.send_message(channel_id, response) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to send Slack response: #{inspect(reason)}")
        :ok
    end
  rescue
    e ->
      Logger.warning("Slack sender not available: #{Exception.message(e)}")
      :ok
  end

  defp send_discord_response(channel_id, response) do
    case Hal.Channels.Discord.Sender.send_message(channel_id, response) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to send Discord response: #{inspect(reason)}")
        :ok
    end
  rescue
    e ->
      Logger.warning("Discord sender not available: #{Exception.message(e)}")
      :ok
  end

  defp truncate(string, max_length) when byte_size(string) > max_length do
    String.slice(string, 0, max_length) <> "..."
  end

  defp truncate(string, _max_length), do: string
end
