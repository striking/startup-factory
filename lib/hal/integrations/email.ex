defmodule HAL.Integrations.Email do
  @moduledoc """
  Gmail API integration for email operations.

  This module provides functions to interact with Gmail API including:
  - Fetching unread emails with filters
  - Sending emails
  - Marking emails as read
  - Searching emails with queries

  ## Configuration

  Add to your config/runtime.exs:

      config :hal, HAL.Integrations.Email,
        client_id: System.get_env("GMAIL_CLIENT_ID"),
        client_secret: System.get_env("GMAIL_CLIENT_SECRET"),
        redirect_uri: System.get_env("GMAIL_REDIRECT_URI", "http://localhost:4000/auth/gmail/callback")

  ## OAuth Flow

  The module expects OAuth tokens to be provided. Token acquisition is not yet implemented.
  See `TODO: OAuth token acquisition flow` section below.

  ## Examples

      # Get unread emails
      {:ok, emails} = HAL.Integrations.Email.get_unread_emails(token, max_results: 10)

      # Send an email
      {:ok, message} = HAL.Integrations.Email.send_email(
        token,
        to: "user@example.com",
        subject: "Hello",
        body: "This is a test email"
      )

      # Mark email as read
      {:ok, _} = HAL.Integrations.Email.mark_as_read(token, message_id)

      # Search emails
      {:ok, emails} = HAL.Integrations.Email.search_emails(
        token,
        "from:example@gmail.com is:unread"
      )
  """

  require Logger

  @gmail_api_base "https://gmail.googleapis.com/gmail/v1"
  @user_id "me"
  @rate_limiter :email_rate_limiter
  @circuit_breaker :email_circuit_breaker

  # TODO: OAuth token acquisition flow
  # This module currently expects tokens to be passed in.
  # Future implementation should include:
  # - OAuth 2.0 authorization flow
  # - Token storage and refresh logic
  # - Token expiration handling
  # - Refresh token rotation

  @type token :: String.t()
  @type message_id :: String.t()
  @type email :: %{
          id: String.t(),
          thread_id: String.t(),
          snippet: String.t(),
          subject: String.t() | nil,
          from: String.t() | nil,
          to: String.t() | nil,
          date: String.t() | nil,
          body: String.t() | nil
        }

  @doc """
  Fetches unread emails with optional filters.

  ## Options

  - `:max_results` - Maximum number of messages to return (default: 10, max: 500)
  - `:label_ids` - List of label IDs to filter by (default: ["UNREAD", "INBOX"])
  - `:query` - Additional Gmail search query

  ## Examples

      # Get 10 most recent unread emails
      {:ok, emails} = get_unread_emails(token)

      # Get 50 unread emails with custom query
      {:ok, emails} = get_unread_emails(token, max_results: 50, query: "has:attachment")

      # Get unread emails from specific label
      {:ok, emails} = get_unread_emails(token, label_ids: ["UNREAD", "IMPORTANT"])
  """
  @spec get_unread_emails(token(), keyword()) :: {:ok, [email()]} | {:error, term()}
  def get_unread_emails(token, opts \\ []) do
    max_results = Keyword.get(opts, :max_results, 10)
    label_ids = Keyword.get(opts, :label_ids, ["UNREAD", "INBOX"])
    query = Keyword.get(opts, :query)

    # Build query parameters
    params = %{
      "maxResults" => max_results,
      "labelIds" => label_ids
    }

    params =
      if query do
        Map.put(params, "q", query)
      else
        params
      end

    result =
      HAL.Resilience.call(
        fn ->
          with {:ok, message_list} <- list_messages(token, params),
               {:ok, messages} <- fetch_message_details(token, message_list) do
            {:ok, messages}
          end
        end,
        circuit_breaker: @circuit_breaker,
        rate_limiter: @rate_limiter,
        retry: [
          max_attempts: 3,
          base_delay: 100,
          retry_on: &retryable_error?/1
        ]
      )

    handle_resilience_error(result)
  end

  @doc """
  Sends an email via Gmail API.

  ## Options

  - `:to` - Recipient email address (required)
  - `:subject` - Email subject (required)
  - `:body` - Email body (required)
  - `:cc` - CC recipients (optional)
  - `:bcc` - BCC recipients (optional)

  ## Examples

      {:ok, message} = send_email(token,
        to: "user@example.com",
        subject: "Meeting reminder",
        body: "Don't forget our meeting at 2pm"
      )

      {:ok, message} = send_email(token,
        to: "user@example.com",
        subject: "Team update",
        body: "Here's the latest update...",
        cc: "team@example.com"
      )
  """
  @spec send_email(token(), keyword()) :: {:ok, map()} | {:error, term()}
  def send_email(token, opts) do
    to = Keyword.fetch!(opts, :to)
    subject = Keyword.fetch!(opts, :subject)
    body = Keyword.fetch!(opts, :body)
    cc = Keyword.get(opts, :cc)
    bcc = Keyword.get(opts, :bcc)

    raw_message = build_mime_message(to, subject, body, cc, bcc)
    encoded_message = Base.url_encode64(raw_message, padding: false)

    url = "#{@gmail_api_base}/users/#{@user_id}/messages/send"

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    body_json = Jason.encode!(%{"raw" => encoded_message})

    result =
      HAL.Resilience.call(
        fn ->
          case HTTPoison.post(url, body_json, headers) do
            {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
              {:ok, Jason.decode!(response_body)}

            {:ok, %HTTPoison.Response{status_code: 429}} ->
              {:error, :rate_limited}

            {:ok, %HTTPoison.Response{status_code: status_code}} when status_code in 500..599 ->
              {:error, {:http_error, status_code}}

            {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
              Logger.error("Gmail API send error: #{status_code} - #{response_body}")
              {:error, {:api_error, status_code, response_body}}

            {:error, %HTTPoison.Error{reason: :timeout}} ->
              {:error, :timeout}

            {:error, %HTTPoison.Error{reason: reason}} ->
              Logger.error("Gmail API send request failed: #{inspect(reason)}")
              {:error, {:request_failed, reason}}
          end
        end,
        circuit_breaker: @circuit_breaker,
        rate_limiter: @rate_limiter,
        retry: [
          max_attempts: 2,
          base_delay: 200,
          retry_on: &retryable_error?/1
        ]
      )

    handle_resilience_error(result)
  end

  @doc """
  Marks an email as read by removing the UNREAD label.

  ## Examples

      {:ok, _} = mark_as_read(token, "message_id_123")
  """
  @spec mark_as_read(token(), message_id()) :: {:ok, map()} | {:error, term()}
  def mark_as_read(token, message_id) do
    url = "#{@gmail_api_base}/users/#{@user_id}/messages/#{message_id}/modify"

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    body_json = Jason.encode!(%{"removeLabelIds" => ["UNREAD"]})

    case HTTPoison.post(url, body_json, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        Logger.error("Gmail API mark as read error: #{status_code} - #{response_body}")
        {:error, {:api_error, status_code, response_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Gmail API mark as read request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  @doc """
  Searches emails using Gmail search query syntax.

  ## Query Examples

  - `"from:example@gmail.com"` - Emails from specific sender
  - `"is:unread"` - Unread emails
  - `"has:attachment"` - Emails with attachments
  - `"subject:meeting"` - Emails with "meeting" in subject
  - `"after:2024/01/01"` - Emails after a specific date
  - `"label:important"` - Emails with specific label

  You can combine queries with AND/OR operators and parentheses.

  ## Options

  - `:max_results` - Maximum number of messages to return (default: 10, max: 500)

  ## Examples

      {:ok, emails} = search_emails(token, "from:boss@company.com is:unread")

      {:ok, emails} = search_emails(token, "has:attachment after:2024/01/01", max_results: 50)
  """
  @spec search_emails(token(), String.t(), keyword()) :: {:ok, [email()]} | {:error, term()}
  def search_emails(token, query, opts \\ []) do
    max_results = Keyword.get(opts, :max_results, 10)

    params = %{
      "q" => query,
      "maxResults" => max_results
    }

    with {:ok, message_list} <- list_messages(token, params),
         {:ok, messages} <- fetch_message_details(token, message_list) do
      {:ok, messages}
    end
  end

  ## Private Functions

  # Lists messages matching the query
  defp list_messages(token, params) do
    url = "#{@gmail_api_base}/users/#{@user_id}/messages"

    headers = [
      {"Authorization", "Bearer #{token}"}
    ]

    query_string = URI.encode_query(params)
    full_url = "#{url}?#{query_string}"

    case HTTPoison.get(full_url, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"messages" => messages}} ->
            {:ok, messages}

          {:ok, %{}} ->
            # No messages found
            {:ok, []}

          {:error, reason} ->
            Logger.error("Failed to decode Gmail API response: #{inspect(reason)}")
            {:error, {:decode_error, reason}}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.error("Gmail API list error: #{status_code} - #{body}")
        {:error, {:api_error, status_code, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Gmail API list request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  # Fetches full details for a list of messages
  defp fetch_message_details(_token, []), do: {:ok, []}

  defp fetch_message_details(token, message_list) do
    messages =
      message_list
      |> Enum.map(fn %{"id" => id} ->
        case get_message(token, id) do
          {:ok, message} -> message
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, messages}
  end

  # Gets a single message with full details
  defp get_message(token, message_id) do
    url = "#{@gmail_api_base}/users/#{@user_id}/messages/#{message_id}"

    headers = [
      {"Authorization", "Bearer #{token}"}
    ]

    case HTTPoison.get(url, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, message_data} ->
            {:ok, parse_message(message_data)}

          {:error, reason} ->
            Logger.error("Failed to decode message: #{inspect(reason)}")
            {:error, {:decode_error, reason}}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.error("Gmail API get message error: #{status_code} - #{body}")
        {:error, {:api_error, status_code, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Gmail API get message request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  # Parses Gmail API message format to our simplified structure
  defp parse_message(message_data) do
    headers = get_in(message_data, ["payload", "headers"]) || []

    %{
      id: message_data["id"],
      thread_id: message_data["threadId"],
      snippet: message_data["snippet"],
      subject: find_header(headers, "Subject"),
      from: find_header(headers, "From"),
      to: find_header(headers, "To"),
      date: find_header(headers, "Date"),
      body: extract_body(message_data["payload"])
    }
  end

  # Finds a specific header value
  defp find_header(headers, name) do
    headers
    |> Enum.find(fn %{"name" => header_name} -> header_name == name end)
    |> case do
      %{"value" => value} -> value
      _ -> nil
    end
  end

  # Extracts email body from payload
  defp extract_body(nil), do: nil

  defp extract_body(payload) do
    cond do
      # Direct body in payload
      payload["body"]["data"] ->
        decode_body_data(payload["body"]["data"])

      # Multipart message
      payload["parts"] ->
        extract_body_from_parts(payload["parts"])

      true ->
        nil
    end
  end

  # Extracts body from multipart message parts
  defp extract_body_from_parts(parts) do
    # Try to find text/plain first, fall back to text/html
    text_part =
      Enum.find(parts, fn part ->
        part["mimeType"] == "text/plain"
      end) ||
        Enum.find(parts, fn part ->
          part["mimeType"] == "text/html"
        end)

    case text_part do
      %{"body" => %{"data" => data}} -> decode_body_data(data)
      _ -> nil
    end
  end

  # Decodes base64url encoded body data
  defp decode_body_data(data) do
    case Base.url_decode64(data, padding: false) do
      {:ok, decoded} -> decoded
      _ -> nil
    end
  end

  # Builds RFC 2822 compliant MIME message
  defp build_mime_message(to, subject, body, cc, bcc) do
    headers = [
      "To: #{to}",
      "Subject: #{subject}"
    ]

    headers =
      if cc do
        ["Cc: #{cc}" | headers]
      else
        headers
      end

    headers =
      if bcc do
        ["Bcc: #{bcc}" | headers]
      else
        headers
      end

    headers = Enum.reverse(headers)

    [
      Enum.join(headers, "\r\n"),
      "\r\n",
      body
    ]
    |> Enum.join()
  end

  # Determines if an error should trigger a retry
  defp retryable_error?({:error, error}) do
    case error do
      :timeout -> true
      :rate_limited -> true
      :connection_refused -> true
      {:http_error, status} when status in 500..599 -> true
      {:request_failed, _} -> true
      _ -> false
    end
  end

  defp retryable_error?(_), do: false

  # Handles errors from resilience wrapper
  defp handle_resilience_error({:ok, result}), do: {:ok, result}

  defp handle_resilience_error({:error, :circuit_open}) do
    {:error, "Email service is temporarily unavailable. Please try again in a few minutes."}
  end

  defp handle_resilience_error({:error, {:api_error, 401, _}}) do
    {:error, "Authentication failed. Please reconnect your Gmail account."}
  end

  defp handle_resilience_error({:error, {:api_error, 403, _}}) do
    {:error, "Access denied. Please check Gmail permissions."}
  end

  defp handle_resilience_error({:error, error}) do
    {:error, HAL.Resilience.format_error({:error, error})}
  end
end
