defmodule HAL.Automation.Workers.Webhook do
  @moduledoc """
  Oban worker for processing incoming webhook events.

  This worker handles external webhook triggers that should initiate HAL actions.
  Common use cases include:
  - GitHub webhooks (PR opened, issue created, CI failed)
  - Stripe webhooks (payment received, subscription changed)
  - Custom integrations (n8n, Zapier, IFTTT)

  ## Job Args

    * `source` - The webhook source identifier (github, stripe, custom, etc.)
    * `event_type` - The type of event (pr_opened, payment_received, etc.)
    * `payload` - The webhook payload data
    * `session_id` - (optional) Session to process the webhook in context
    * `respond_via` - (optional) Channel to send notifications to

  ## Examples

      # Process a GitHub webhook
      %{
        source: "github",
        event_type: "pull_request.opened",
        payload: %{"repository" => %{"name" => "hal"}, "pull_request" => %{...}},
        session_id: "uuid",
        respond_via: %{"channel_type" => "slack", "channel_id" => "C12345"}
      }
      |> HAL.Automation.Workers.Webhook.new()
      |> Oban.insert()

  """

  use Oban.Worker,
    queue: :webhooks,
    max_attempts: 5,
    priority: 0

  require Logger

  alias Hal.Gateway.SessionManager
  alias Hal.Gateway.SessionServer

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    source = Map.fetch!(args, "source")
    event_type = Map.fetch!(args, "event_type")
    payload = Map.get(args, "payload", %{})
    session_id = Map.get(args, "session_id")
    respond_via = Map.get(args, "respond_via", %{})

    Logger.info("Processing webhook: #{source}/#{event_type}")

    case source do
      "github" ->
        process_github_webhook(event_type, payload, session_id, respond_via)

      "stripe" ->
        process_stripe_webhook(event_type, payload, session_id, respond_via)

      "n8n" ->
        process_n8n_webhook(event_type, payload, session_id, respond_via)

      "custom" ->
        process_custom_webhook(event_type, payload, session_id, respond_via)

      _ ->
        Logger.warning("Unknown webhook source: #{source}")
        :ok
    end
  end

  # Process GitHub webhooks
  defp process_github_webhook(event_type, payload, session_id, respond_via) do
    case event_type do
      "pull_request.opened" ->
        handle_pr_opened(payload, session_id, respond_via)

      "pull_request.merged" ->
        handle_pr_merged(payload, respond_via)

      "issues.opened" ->
        handle_issue_opened(payload, session_id, respond_via)

      "check_run.completed" ->
        if payload["conclusion"] == "failure" do
          handle_ci_failure(payload, respond_via)
        else
          Logger.debug("Check run completed with conclusion: #{payload["conclusion"]}")
          :ok
        end

      "push" ->
        handle_push(payload, respond_via)

      _ ->
        Logger.debug("Unhandled GitHub event: #{event_type}")
        :ok
    end
  end

  defp handle_pr_opened(payload, session_id, respond_via) do
    repo = get_in(payload, ["repository", "full_name"]) || "unknown"
    pr_number = get_in(payload, ["pull_request", "number"]) || "?"
    pr_title = get_in(payload, ["pull_request", "title"]) || "Untitled"
    pr_url = get_in(payload, ["pull_request", "html_url"]) || ""

    if session_id do
      # Ask Claude to review the PR
      prompt = """
      A new pull request was opened on #{repo}:
      PR ##{pr_number}: #{pr_title}
      URL: #{pr_url}

      Please review this PR and provide a summary of the changes and any concerns.
      """

      with {:ok, session_pid} <- get_session(session_id),
           {:ok, response} <- SessionServer.handle_message(session_pid, prompt, []) do
        send_notification(respond_via, "PR Review for ##{pr_number}:\n\n#{response}")
      end
    else
      # Just notify about the new PR
      message = "New PR opened on #{repo}: ##{pr_number} - #{pr_title}\n#{pr_url}"
      send_notification(respond_via, message)
    end

    :ok
  end

  defp handle_pr_merged(payload, respond_via) do
    repo = get_in(payload, ["repository", "full_name"]) || "unknown"
    pr_number = get_in(payload, ["pull_request", "number"]) || "?"
    pr_title = get_in(payload, ["pull_request", "title"]) || "Untitled"

    message = "PR ##{pr_number} merged on #{repo}: #{pr_title}"
    send_notification(respond_via, message)
    :ok
  end

  defp handle_issue_opened(payload, session_id, respond_via) do
    repo = get_in(payload, ["repository", "full_name"]) || "unknown"
    issue_number = get_in(payload, ["issue", "number"]) || "?"
    issue_title = get_in(payload, ["issue", "title"]) || "Untitled"
    issue_body = get_in(payload, ["issue", "body"]) || ""

    if session_id do
      prompt = """
      A new issue was opened on #{repo}:
      Issue ##{issue_number}: #{issue_title}

      #{String.slice(issue_body, 0, 500)}

      Please analyze this issue and suggest next steps or priority.
      """

      with {:ok, session_pid} <- get_session(session_id),
           {:ok, response} <- SessionServer.handle_message(session_pid, prompt, []) do
        send_notification(respond_via, "Issue Analysis for ##{issue_number}:\n\n#{response}")
      end
    else
      message = "New issue on #{repo}: ##{issue_number} - #{issue_title}"
      send_notification(respond_via, message)
    end

    :ok
  end

  defp handle_ci_failure(payload, respond_via) do
    repo = get_in(payload, ["repository", "full_name"]) || "unknown"
    check_name = get_in(payload, ["check_run", "name"]) || "CI"
    url = get_in(payload, ["check_run", "html_url"]) || ""

    message = "CI failure on #{repo}: #{check_name}\n#{url}"
    send_notification(respond_via, message)
    :ok
  end

  defp handle_push(payload, respond_via) do
    repo = get_in(payload, ["repository", "full_name"]) || "unknown"
    ref = Map.get(payload, "ref", "unknown")
    commits = Map.get(payload, "commits", [])
    commit_count = length(commits)

    if commit_count > 0 do
      message = "#{commit_count} commit(s) pushed to #{repo} on #{ref}"
      send_notification(respond_via, message)
    end

    :ok
  end

  # Process Stripe webhooks
  defp process_stripe_webhook(event_type, payload, _session_id, respond_via) do
    case event_type do
      "payment_intent.succeeded" ->
        amount = get_in(payload, ["data", "object", "amount"]) || 0
        currency = get_in(payload, ["data", "object", "currency"]) || "usd"
        formatted_amount = :io_lib.format("~.2f", [amount / 100]) |> to_string()

        message = "Payment received: #{formatted_amount} #{String.upcase(currency)}"
        send_notification(respond_via, message)

      "customer.subscription.created" ->
        message = "New subscription created!"
        send_notification(respond_via, message)

      "customer.subscription.deleted" ->
        message = "Subscription cancelled"
        send_notification(respond_via, message)

      _ ->
        Logger.debug("Unhandled Stripe event: #{event_type}")
    end

    :ok
  end

  # Process n8n workflow webhooks
  defp process_n8n_webhook(_event_type, payload, session_id, respond_via) do
    # n8n can send arbitrary prompts or commands
    prompt = Map.get(payload, "prompt")
    message = Map.get(payload, "message")

    cond do
      prompt && session_id ->
        # Execute the prompt in the session context
        with {:ok, session_pid} <- get_session(session_id),
             {:ok, response} <- SessionServer.handle_message(session_pid, prompt, []) do
          send_notification(respond_via, response)
        end

      message ->
        # Just forward the message
        send_notification(respond_via, message)

      true ->
        Logger.debug("n8n webhook with no actionable content")
    end

    :ok
  end

  # Process custom webhooks
  defp process_custom_webhook(event_type, payload, session_id, respond_via) do
    # Generic handler for custom webhooks
    prompt = Map.get(payload, "prompt")
    message = Map.get(payload, "message")

    cond do
      prompt && session_id ->
        with {:ok, session_pid} <- get_session(session_id),
             {:ok, response} <- SessionServer.handle_message(session_pid, prompt, []) do
          send_notification(respond_via, response)
        end

      message ->
        send_notification(respond_via, message)

      true ->
        Logger.info("Custom webhook received: #{event_type}")
    end

    :ok
  end

  # Helper functions

  defp get_session(session_id) when is_binary(session_id) do
    case Hal.Repo.get(Hal.Gateway.Session, session_id) do
      nil ->
        {:error, :session_not_found}

      session ->
        SessionManager.get_or_create_session(
          Hal.Gateway.SessionManager,
          session.channel_type,
          session.channel_id,
          session.user_id
        )
    end
  end

  defp get_session(_), do: {:error, :no_session}

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
          Logger.warning("Unknown channel type: #{channel_type}")
      end
    rescue
      e ->
        Logger.warning("Failed to send notification: #{Exception.message(e)}")
    end

    :ok
  end

  defp send_notification(_, _message), do: :ok
end
