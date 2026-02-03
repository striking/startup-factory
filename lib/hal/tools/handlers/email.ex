defmodule Hal.Tools.Handlers.Email do
  @moduledoc """
  Handler for HAL email tool operations.

  Uses Gmail API when the user has connected their Google account.
  Returns helpful error if not connected.
  """

  require Logger
  alias Hal.Tools.Executor
  alias HAL.Credentials
  alias HAL.Integrations.Email, as: GmailAPI

  @doc """
  Get unread emails from user's inbox.

  ## Arguments

    * `args` - Map containing:
      * `"limit"` - Optional result limit (default: 10)
      * `"from"` - Optional sender filter
      * `"subject_contains"` - Optional subject filter
    * `opts` - Context options with `:user_id`
  """
  @spec get_unread(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def get_unread(args, opts) do
    _user_id = Keyword.fetch!(opts, :user_id)
    limit = Map.get(args, "limit", 10)
    from_filter = Map.get(args, "from")
    subject_filter = Map.get(args, "subject_contains")

    case Credentials.get_google_token() do
      {:ok, access_token} ->
        # Build Gmail query
        query_parts = ["is:unread"]

        query_parts =
          if from_filter, do: query_parts ++ ["from:#{from_filter}"], else: query_parts

        query_parts =
          if subject_filter, do: query_parts ++ ["subject:#{subject_filter}"], else: query_parts

        query = Enum.join(query_parts, " ")

        case GmailAPI.search_emails(access_token, query, max_results: limit) do
          {:ok, emails} ->
            formatted_emails = Enum.map(emails, &format_email/1)
            count = length(formatted_emails)

            Executor.return_success(
              "Found #{count} unread #{pluralize("email", count)}",
              %{
                emails: formatted_emails,
                filters: %{from: from_filter, subject_contains: subject_filter}
              }
            )

          {:error, reason} ->
            Logger.error("Gmail API error: #{inspect(reason)}")
            Executor.return_error("Failed to fetch emails", reason)
        end

      {:error, :not_found} ->
        Executor.return_error(
          "Google credentials not configured",
          "Please add Google credentials at ~/.hal/credentials/google.json"
        )

      {:error, :no_refresh_token} ->
        Executor.return_error(
          "Google authentication expired",
          "Please update your Google credentials at ~/.hal/credentials/google.json"
        )

      {:error, reason} ->
        Logger.error("Token error: #{inspect(reason)}")
        Executor.return_error("Authentication error", inspect(reason))
    end
  rescue
    e ->
      Logger.error("Email get_unread failed: #{Exception.message(e)}")
      Executor.return_error("Email get_unread failed", Exception.message(e))
  end

  @doc """
  Send an email.

  ## Arguments

    * `args` - Map containing:
      * `"to"` - Recipient email (string or array)
      * `"subject"` - Email subject
      * `"body"` - Email body
      * `"cc"` - Optional CC recipients
      * `"bcc"` - Optional BCC recipients
    * `opts` - Context options with `:user_id`
  """
  @spec send_email(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def send_email(args, opts) do
    _user_id = Keyword.fetch!(opts, :user_id)

    to = normalize_recipients(Map.get(args, "to"))
    subject = Map.get(args, "subject")
    body = Map.get(args, "body")
    cc = Map.get(args, "cc")
    bcc = Map.get(args, "bcc")

    cond do
      is_nil(to) or to == "" ->
        Executor.return_error("Missing required argument: to")

      is_nil(subject) ->
        Executor.return_error("Missing required argument: subject")

      is_nil(body) ->
        Executor.return_error("Missing required argument: body")

      true ->
        case Credentials.get_google_token() do
          {:ok, access_token} ->
            email_opts = [to: to, subject: subject, body: body]
            email_opts = if cc, do: Keyword.put(email_opts, :cc, cc), else: email_opts
            email_opts = if bcc, do: Keyword.put(email_opts, :bcc, bcc), else: email_opts

            case GmailAPI.send_email(access_token, email_opts) do
              {:ok, result} ->
                Executor.return_success(
                  "Email sent successfully to #{to}",
                  %{
                    id: result["id"],
                    thread_id: result["threadId"],
                    to: to,
                    subject: subject,
                    sent_at: DateTime.utc_now() |> DateTime.to_iso8601()
                  }
                )

              {:error, reason} ->
                Logger.error("Gmail send error: #{inspect(reason)}")
                Executor.return_error("Failed to send email", reason)
            end

          {:error, :not_found} ->
            Executor.return_error(
              "Google credentials not configured",
              "Please add Google credentials at ~/.hal/credentials/google.json"
            )

          {:error, :no_refresh_token} ->
            Executor.return_error(
              "Google authentication expired",
              "Please update your Google credentials at ~/.hal/credentials/google.json"
            )

          {:error, reason} ->
            Logger.error("Token error: #{inspect(reason)}")
            Executor.return_error("Authentication error", inspect(reason))
        end
    end
  rescue
    e ->
      Logger.error("Email send failed: #{Exception.message(e)}")
      Executor.return_error("Email send failed", Exception.message(e))
  end

  # Private helpers

  defp format_email(email) do
    %{
      id: email.id,
      thread_id: email.thread_id,
      from: email.from,
      to: email.to,
      subject: email.subject,
      snippet: email.snippet,
      date: email.date,
      body_preview: truncate(email.body, 500)
    }
  end

  defp normalize_recipients(nil), do: nil
  defp normalize_recipients(recipients) when is_list(recipients), do: Enum.join(recipients, ", ")
  defp normalize_recipients(recipient) when is_binary(recipient), do: recipient

  defp truncate(nil, _), do: nil
  defp truncate(text, max_length) when byte_size(text) <= max_length, do: text
  defp truncate(text, max_length), do: String.slice(text, 0, max_length) <> "..."

  defp pluralize(word, 1), do: word
  defp pluralize(word, _), do: "#{word}s"
end
