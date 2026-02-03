defmodule HAL.Automation.Workers.ProactiveTask do
  @moduledoc """
  Oban worker for agent-initiated proactive tasks.

  Unlike ScheduledTask which is typically triggered by user commands,
  ProactiveTask handles tasks that HAL initiates on its own based on:
  - Monitoring conditions (e.g., "notify me when X happens")
  - Intelligent suggestions (e.g., "you haven't checked email in 2 hours")
  - Background maintenance (e.g., session cleanup, context updates)

  ## Job Args

    * `task_type` - Type of proactive task (monitor, suggestion, maintenance)
    * `session_id` - (optional) Session context for the task
    * `prompt` - (optional) Prompt to execute if task type requires AI interaction
    * `config` - Task-specific configuration
    * `respond_via` - (optional) Channel info for sending notifications

  ## Task Types

    * `:monitor` - Check a condition and notify if triggered
    * `:suggestion` - Generate and send a proactive suggestion
    * `:maintenance` - Background maintenance task
    * `:reminder` - Simple reminder without AI processing

  ## Examples

      # Set up a monitoring task
      %{
        task_type: "monitor",
        session_id: "uuid",
        config: %{
          "check_url" => "https://api.github.com/notifications",
          "condition" => "new_items"
        },
        respond_via: %{"channel_type" => "telegram", "channel_id" => "123456"}
      }
      |> HAL.Automation.Workers.ProactiveTask.new()
      |> Oban.insert()

  """

  use Oban.Worker,
    queue: :scheduled,
    max_attempts: 3,
    priority: 2

  require Logger

  alias Hal.Gateway.SessionManager
  alias Hal.Gateway.SessionServer

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    task_type = Map.get(args, "task_type", "reminder")
    session_id = Map.get(args, "session_id")
    config = Map.get(args, "config", %{})
    respond_via = Map.get(args, "respond_via", %{})

    Logger.info("Executing proactive task: #{task_type}")

    result =
      case task_type do
        "monitor" ->
          execute_monitor(session_id, config, respond_via)

        "suggestion" ->
          execute_suggestion(session_id, config, respond_via)

        "maintenance" ->
          execute_maintenance(config)

        "reminder" ->
          execute_reminder(args, respond_via)

        _ ->
          Logger.warning("Unknown proactive task type: #{task_type}")
          :ok
      end

    case result do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Execute a monitoring task - check a condition and notify if triggered
  defp execute_monitor(session_id, config, respond_via) do
    prompt = Map.get(config, "prompt", "Check the monitored condition")

    with {:ok, session_pid} <- get_session(session_id),
         {:ok, response} <- SessionServer.handle_message(session_pid, prompt, []) do
      # Check if the response indicates the condition was triggered
      if should_notify?(response, config) do
        send_notification(respond_via, "Monitor Alert: #{response}")
      end

      :ok
    else
      {:error, :no_session} ->
        Logger.info("Monitor task skipped - no session specified")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Execute a suggestion task - generate and send a proactive suggestion
  defp execute_suggestion(session_id, config, respond_via) do
    prompt = Map.get(config, "prompt", "Generate a helpful suggestion based on recent context")

    with {:ok, session_pid} <- get_session(session_id),
         {:ok, response} <- SessionServer.handle_message(session_pid, prompt, []) do
      send_notification(respond_via, response)
      :ok
    else
      {:error, :no_session} ->
        Logger.info("Suggestion task skipped - no session specified")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Execute maintenance tasks (cleanup, optimization, etc.)
  defp execute_maintenance(config) do
    task = Map.get(config, "task", "session_cleanup")

    case task do
      "session_cleanup" ->
        cleanup_stale_sessions(config)

      "log_rotation" ->
        Logger.info("Log rotation triggered (placeholder)")
        :ok

      _ ->
        Logger.warning("Unknown maintenance task: #{task}")
        :ok
    end
  end

  # Execute a simple reminder
  defp execute_reminder(args, respond_via) do
    message = Map.get(args, "message", Map.get(args, "prompt", "Reminder!"))
    send_notification(respond_via, message)
    :ok
  end

  defp get_session(nil), do: {:error, :no_session}

  defp get_session(session_id) do
    case Hal.Repo.get(Hal.Gateway.Session, session_id) do
      nil ->
        {:error, :session_not_found}

      session ->
        session_manager = Hal.Gateway.SessionManager

        case SessionManager.get_or_create_session(
               session_manager,
               session.channel_type,
               session.channel_id,
               session.user_id
             ) do
          {:ok, pid} -> {:ok, pid}
          error -> error
        end
    end
  end

  defp should_notify?(response, config) do
    trigger_words = Map.get(config, "trigger_words", [])

    if Enum.empty?(trigger_words) do
      # Default: notify if response is not empty
      String.length(response) > 0
    else
      # Check if any trigger words are present
      response_lower = String.downcase(response)

      Enum.any?(trigger_words, fn word ->
        String.contains?(response_lower, String.downcase(word))
      end)
    end
  end

  defp send_notification(%{"channel_type" => channel_type, "channel_id" => channel_id}, message) do
    try do
      case channel_type do
        "telegram" ->
          Hal.Channels.Telegram.Sender.send_message(
            Hal.Channels.Telegram.Sender,
            channel_id,
            message
          )

        "slack" ->
          HAL.Channels.Slack.Sender.send_message(channel_id, message)

        "discord" ->
          Hal.Channels.Discord.Sender.send_message(channel_id, message)

        _ ->
          Logger.warning("Unknown channel type for notification: #{channel_type}")
      end
    rescue
      e ->
        Logger.warning("Failed to send notification: #{Exception.message(e)}")
    end

    :ok
  end

  defp send_notification(_, _message), do: :ok

  defp cleanup_stale_sessions(config) do
    max_age_hours = Map.get(config, "max_age_hours", 72)
    cutoff = DateTime.utc_now() |> DateTime.add(-max_age_hours * 3600, :second)

    import Ecto.Query

    # Find stale sessions
    query =
      from s in Hal.Gateway.Session,
        where: s.status == "active" and s.last_activity < ^cutoff,
        select: s

    stale_sessions = Hal.Repo.all(query)

    Logger.info("Found #{length(stale_sessions)} stale sessions to archive")

    # Archive stale sessions
    for session <- stale_sessions do
      session
      |> Hal.Gateway.Session.status_changeset(%{status: "archived"})
      |> Hal.Repo.update()
    end

    :ok
  end
end
