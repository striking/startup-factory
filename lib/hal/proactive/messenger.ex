defmodule HAL.Proactive.Messenger do
  @moduledoc """
  Determines when HAL should proactively reach out to the user.

  Proactive messaging triggers:
  - Goal milestones achieved
  - Important calendar conflicts detected
  - Critical email received (VIP senders, keywords)
  - Learning worth sharing
  - Stuck on something needing user input
  - Daily summary (if enabled)

  Respects quiet hours from USER.md configuration.

  ## Usage

      # Check if we should send a proactive message
      case Messenger.should_message?(user_id, trigger) do
        {:yes, reason} -> send_message(reason)
        :no -> :ok
        {:quiet_hours, resume_at} -> schedule_for_later(resume_at)
      end

      # Send a proactive message
      Messenger.send_proactive(user_id, message, opts)
  """

  require Logger

  alias Hal.Accounts.User
  alias Hal.Notifications
  alias Hal.Repo

  # 23:00 to 08:00
  @default_quiet_hours {23, 8}

  @doc """
  Check if we should send a proactive message.
  """
  @spec should_message?(Ecto.UUID.t(), atom()) ::
          {:yes, String.t()} | :no | {:quiet_hours, DateTime.t()}
  def should_message?(user_id, trigger) do
    quiet_hours = get_quiet_hours(user_id)

    if in_quiet_hours?(quiet_hours) do
      {:quiet_hours, next_active_time(quiet_hours)}
    else
      check_trigger(trigger, user_id)
    end
  end

  @doc """
  Send a proactive message to the user.
  """
  @spec send_proactive(Ecto.UUID.t(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def send_proactive(user_id, message, opts \\ []) do
    priority = Keyword.get(opts, :priority, :normal)
    channel = Keyword.get(opts, :channel, :auto)
    silent = Keyword.get(opts, :silent, priority == :low)

    # Check quiet hours unless urgent
    if priority != :urgent do
      case should_message?(user_id, :manual) do
        {:quiet_hours, _} ->
          Logger.debug("Skipping proactive message during quiet hours")
          {:error, :quiet_hours}

        _ ->
          do_send(user_id, message, channel, silent)
      end
    else
      do_send(user_id, message, channel, silent)
    end
  end

  @doc """
  Queue a proactive message for later (after quiet hours).
  """
  @spec queue_for_later(Ecto.UUID.t(), String.t(), DateTime.t(), keyword()) :: {:ok, term()}
  def queue_for_later(user_id, message, send_at, opts \\ []) do
    # In a full implementation, this would use Oban or similar
    Logger.info("Queued proactive message for #{user_id} at #{send_at}")

    # For now, just log it
    {:ok, %{user_id: user_id, message: message, send_at: send_at, opts: opts}}
  end

  # Trigger Types

  @doc """
  Notify about goal milestone.
  """
  def notify_goal_milestone(user_id, goal, milestone) do
    case should_message?(user_id, :goal_milestone) do
      {:yes, _} ->
        message = format_goal_milestone(goal, milestone)
        send_proactive(user_id, message, priority: :normal)

      {:quiet_hours, resume_at} ->
        message = format_goal_milestone(goal, milestone)
        queue_for_later(user_id, message, resume_at)

      :no ->
        :ok
    end
  end

  @doc """
  Notify about calendar conflict.
  """
  def notify_calendar_conflict(user_id, events) do
    case should_message?(user_id, :calendar_conflict) do
      {:yes, _} ->
        message = format_calendar_conflict(events)
        send_proactive(user_id, message, priority: :high)

      {:quiet_hours, resume_at} ->
        message = format_calendar_conflict(events)
        queue_for_later(user_id, message, resume_at, priority: :high)

      :no ->
        :ok
    end
  end

  @doc """
  Notify about important email.
  """
  def notify_important_email(user_id, email) do
    case should_message?(user_id, :important_email) do
      {:yes, _} ->
        message = format_important_email(email)
        send_proactive(user_id, message, priority: :high)

      {:quiet_hours, resume_at} ->
        message = format_important_email(email)
        queue_for_later(user_id, message, resume_at, priority: :high)

      :no ->
        :ok
    end
  end

  @doc """
  Share a useful learning.
  """
  def share_learning(user_id, learning) do
    case should_message?(user_id, :learning) do
      {:yes, _} ->
        message = format_learning(learning)
        send_proactive(user_id, message, priority: :low, silent: true)

      _ ->
        # Don't queue learnings - they're low priority
        :ok
    end
  end

  @doc """
  Request user input when stuck.
  """
  def request_input(user_id, context, question) do
    case should_message?(user_id, :stuck) do
      {:yes, _} ->
        message = format_input_request(context, question)
        send_proactive(user_id, message, priority: :normal)

      {:quiet_hours, resume_at} ->
        message = format_input_request(context, question)
        queue_for_later(user_id, message, resume_at)

      :no ->
        :ok
    end
  end

  # Private Functions

  defp check_trigger(trigger, _user_id) do
    # Could check user preferences here
    case trigger do
      :goal_milestone -> {:yes, "Goal milestone reached"}
      :calendar_conflict -> {:yes, "Calendar conflict detected"}
      :important_email -> {:yes, "Important email received"}
      :learning -> {:yes, "Useful learning to share"}
      :stuck -> {:yes, "Need user input"}
      :manual -> {:yes, "Manual trigger"}
      _ -> :no
    end
  end

  defp get_quiet_hours(_user_id) do
    # In full implementation, read from USER.md or user preferences
    # For now, use defaults
    @default_quiet_hours
  end

  defp in_quiet_hours?({quiet_start, quiet_end}) do
    now = DateTime.utc_now()
    hour = now.hour

    if quiet_start > quiet_end do
      # Spans midnight (e.g., 23:00 to 08:00)
      hour >= quiet_start or hour < quiet_end
    else
      # Same day (e.g., 13:00 to 14:00)
      hour >= quiet_start and hour < quiet_end
    end
  end

  defp next_active_time({_quiet_start, quiet_end}) do
    now = DateTime.utc_now()
    today = Date.utc_today()

    target_date =
      if now.hour >= quiet_end do
        Date.add(today, 1)
      else
        today
      end

    DateTime.new!(target_date, Time.new!(quiet_end, 0, 0), "Etc/UTC")
  end

  defp do_send(user_id, message, channel, silent) do
    # Fetch user to get notification preferences
    case Repo.get(User, user_id) do
      nil ->
        Logger.warning("ProactiveMessenger: User #{user_id} not found")
        {:error, :user_not_found}

      user ->
        # Build notification options
        opts = build_notification_opts(channel, silent)

        # Send via HAL.Notifications
        result = Notifications.send(user, message, opts)

        # Log observation regardless of result
        log_proactive_message(user_id, message, channel, silent, result)

        result
    end
  end

  defp build_notification_opts(channel, silent) do
    opts = []

    # Map priority to urgency
    opts = if silent, do: Keyword.put(opts, :urgent, false), else: opts

    # Specify channel if not :auto
    opts =
      if channel != :auto do
        Keyword.put(opts, :channels, [channel])
      else
        # Enable fallback for auto routing
        Keyword.put(opts, :fallback, true)
      end

    opts
  end

  defp log_proactive_message(user_id, message, channel, silent, result) do
    status =
      case result do
        {:ok, _} -> "sent"
        {:error, reason} -> "failed: #{inspect(reason)}"
      end

    HAL.Observations.log(%{
      type: "proactive_message",
      observation: "Proactive message #{status}",
      message_preview: String.slice(message, 0, 100),
      user_id: user_id,
      channel: channel,
      silent: silent
    })
  end

  # Message Formatters

  defp format_goal_milestone(goal, milestone) do
    """
    Goal milestone reached!

    **#{goal.title}**: #{milestone}
    Progress: #{round(goal.progress * 100)}%
    """
  end

  defp format_calendar_conflict(events) do
    event_list =
      events
      |> Enum.map(fn e -> "- #{e.title} at #{e.start_time}" end)
      |> Enum.join("\n")

    """
    Calendar conflict detected!

    These events overlap:
    #{event_list}

    Would you like me to suggest rescheduling?
    """
  end

  defp format_important_email(email) do
    """
    Important email from #{email.from}:

    **#{email.subject}**

    Would you like me to summarize or draft a response?
    """
  end

  defp format_learning(learning) do
    """
    Something I learned that might be useful:

    #{learning.observation}

    Impact: #{learning.impact || "General improvement"}
    """
  end

  defp format_input_request(context, question) do
    """
    I need your input on something:

    **Context**: #{context}

    **Question**: #{question}
    """
  end
end
