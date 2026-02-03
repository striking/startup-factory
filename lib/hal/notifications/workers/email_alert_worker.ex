defmodule Hal.Notifications.Workers.EmailAlertWorker do
  @moduledoc """
  Oban worker that checks for urgent emails and sends alerts.

  Uses Claude to intelligently assess email urgency based on:
  - Sender importance (boss, client, family)
  - Content tone and time sensitivity
  - Action required vs informational
  - Context from user preferences

  No keyword matching - the AI decides what's truly urgent.
  """

  use Oban.Worker,
    queue: :scheduled,
    max_attempts: 3

  require Logger

  alias HAL.Credentials
  alias Hal.Notifications
  alias Hal.Notifications.Preference
  alias Hal.Notifications.History
  alias HAL.Integrations.Email, as: GmailAPI
  alias HAL.Autonomy.Brain

  # Only check emails from the last 30 minutes to avoid re-alerting old emails
  @check_window_minutes 30
  # Maximum emails to analyze per check (to control Claude API costs)
  @max_emails_to_analyze 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    user_id = args["user_id"]

    if user_id do
      check_user_email(user_id)
    else
      check_all_users()
    end

    :ok
  end

  @doc """
  Checks email for a specific user and sends alerts for urgent emails.
  """
  def check_user_email(user_id) do
    with {:ok, prefs} <- Preference.get_or_create(user_id),
         true <- prefs.email_alerts,
         false <- Preference.in_quiet_hours?(user_id),
         {:ok, access_token} <- Credentials.get_google_token() do
      process_urgent_emails(user_id, access_token, prefs)
    else
      {:error, :not_found} ->
        Logger.debug("Google credentials not configured, skipping email check")
        :ok

      {:error, reason} ->
        Logger.warning("Email check failed for user #{user_id}: #{inspect(reason)}")
        :ok

      false ->
        Logger.debug("Email alerts disabled or in quiet hours for user #{user_id}")
        :ok

      _ ->
        :ok
    end
  end

  defp check_all_users do
    Preference.users_with_enabled(:email)
    |> Enum.each(fn pref ->
      check_user_email(pref.user_id)
    end)
  end

  defp process_urgent_emails(user_id, access_token, prefs) do
    # Build query for recent unread emails
    after_time = DateTime.utc_now() |> DateTime.add(-@check_window_minutes, :minute)
    after_timestamp = DateTime.to_unix(after_time)

    # Build Gmail query
    query = "is:unread after:#{after_timestamp}"

    case GmailAPI.search_emails(access_token, query, max_results: @max_emails_to_analyze) do
      {:ok, emails} when emails != [] ->
        # Use Claude to assess which emails are truly urgent
        assess_and_alert_urgent(user_id, emails, prefs)

      {:ok, []} ->
        Logger.debug("No new unread emails for user #{user_id}")

      {:error, reason} ->
        Logger.error("Failed to fetch emails: #{inspect(reason)}")
    end
  end

  defp assess_and_alert_urgent(user_id, emails, prefs) do
    # Build context for Claude
    vip_senders = prefs.urgent_email_senders || []

    email_summaries =
      emails
      |> Enum.map(fn email ->
        """
        ---
        From: #{email.from}
        Subject: #{email.subject}
        Snippet: #{truncate(email.snippet, 200)}
        Date: #{email.date}
        """
      end)
      |> Enum.join("\n")

    prompt = """
    Analyze these emails and identify which ones are TRULY urgent and require immediate attention.

    Consider:
    - Time-sensitive content (meetings, deadlines, responses needed today)
    - Sender importance#{if vip_senders != [], do: " (VIP senders: #{Enum.join(vip_senders, ", ")})", else: ""}
    - Tone indicating urgency (not just keywords like "urgent" - actual time pressure)
    - Business critical vs informational
    - Personal/family matters that may need quick response

    DO NOT flag as urgent:
    - Marketing emails
    - Newsletters
    - Automated notifications
    - Emails that can wait until tomorrow

    Emails to analyze:
    #{email_summaries}

    Respond with ONLY a JSON array of email subjects that are truly urgent. Empty array [] if none are urgent.
    Example: ["Meeting in 30 minutes", "Client needs response ASAP"]
    """

    case Brain.prompt(prompt,
           user_id: user_id,
           hal_session_id: "email-urgency",
           channel_type: "terminal",
           channel_id: "email:urgency",
           timeout: 60_000,
           log: false
         ) do
      {:ok, response} ->
        urgent_subjects = parse_urgent_subjects(response)

        emails
        |> Enum.filter(fn email -> email.subject in urgent_subjects end)
        |> Enum.each(fn email -> send_alert_if_not_sent(user_id, email) end)

      {:error, reason} ->
        Logger.warning("Claude urgency assessment failed: #{inspect(reason)}")
        # Don't alert on failure - better to miss alerts than spam user
    end
  end

  defp parse_urgent_subjects(response) do
    # Extract JSON array from response
    case Regex.run(~r/\[.*?\]/s, response) do
      [json | _] ->
        case Jason.decode(json) do
          {:ok, subjects} when is_list(subjects) -> subjects
          _ -> []
        end

      nil ->
        []
    end
  end

  defp send_alert_if_not_sent(user_id, email) do
    trigger_id = email.id

    unless History.already_sent?(user_id, "email", trigger_id) do
      send_email_alert(user_id, email, trigger_id)
    end
  end

  defp send_email_alert(user_id, email, trigger_id) do
    from = email.from || "Unknown sender"
    subject = email.subject || "No subject"
    snippet = truncate(email.snippet, 200)

    # Record the notification attempt
    {:ok, history} =
      History.record(%{
        user_id: user_id,
        trigger_type: "email",
        trigger_id: trigger_id,
        title: "📧 Urgent: #{subject}",
        body: "From: #{from}\n\n#{snippet}",
        priority: "urgent",
        metadata: %{
          email_id: email.id,
          thread_id: email.thread_id,
          from: from
        }
      })

    # Get user and send notification
    case Hal.Repo.get(Hal.Accounts.User, user_id) do
      nil ->
        History.mark_failed(history.id, "User not found")

      user ->
        message = format_alert_message(from, subject, snippet)

        case Notifications.send(user, message, fallback: true, urgent: true) do
          {:ok, result} ->
            channel = to_string(result.channel)
            message_id = result[:message_id] || result[:message_ts] || result[:chat_id]
            History.mark_delivered(history.id, channel, to_string(message_id))

          {:error, reason} ->
            History.mark_failed(history.id, inspect(reason))
        end
    end
  end

  defp format_alert_message(from, subject, snippet) do
    """
    📧 *Urgent Email*

    *From:* #{from}
    *Subject:* #{subject}

    #{snippet}
    """
  end

  defp truncate(nil, _), do: ""
  defp truncate(text, max) when byte_size(text) <= max, do: text
  defp truncate(text, max), do: String.slice(text, 0, max) <> "..."
end
