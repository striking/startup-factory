defmodule HAL.Integrations.Calendar do
  @moduledoc """
  Google Calendar integration with resilience patterns.

  This module provides a resilient interface to Google Calendar API with:
  - Retry logic with exponential backoff
  - Rate limiting (10 requests/second per Google's limits)
  - Circuit breaker protection
  - Graceful error handling
  - Request caching

  ## Configuration

      config :hal, HAL.Integrations.Calendar,
        client_id: System.get_env("GOOGLE_CLIENT_ID"),
        client_secret: System.get_env("GOOGLE_CLIENT_SECRET"),
        redirect_uri: "http://localhost:4000/auth/google/callback",
        rate_limit: 10,          # requests per second
        circuit_breaker: [
          failure_threshold: 5,
          timeout: 60_000
        ]

  ## Usage

      # List events
      {:ok, events} = HAL.Integrations.Calendar.list_events(user_token,
        calendar_id: "primary",
        time_min: DateTime.utc_now(),
        max_results: 10
      )

      # Create event
      {:ok, event} = HAL.Integrations.Calendar.create_event(user_token, %{
        summary: "Team Meeting",
        start: %{dateTime: "2024-01-20T10:00:00-07:00"},
        end: %{dateTime: "2024-01-20T11:00:00-07:00"}
      })

  ## Error Handling

  All functions return `{:ok, result}` or `{:error, reason}`.
  Errors are automatically retried for transient failures.
  """

  require Logger

  @base_url "https://www.googleapis.com/calendar/v3"
  @rate_limiter :calendar_rate_limiter
  @circuit_breaker :calendar_circuit_breaker

  # Client API

  @doc """
  Lists events from a calendar.

  ## Options

    * `:calendar_id` - Calendar ID (default: "primary")
    * `:time_min` - Minimum time (DateTime)
    * `:time_max` - Maximum time (DateTime)
    * `:max_results` - Maximum number of results (default: 10)
    * `:order_by` - Sort order: "startTime" or "updated"
  """
  def list_events(token, opts \\ []) do
    calendar_id = Keyword.get(opts, :calendar_id, "primary")

    query_params =
      opts
      |> Keyword.take([:time_min, :time_max, :max_results, :order_by])
      |> encode_query_params()

    url = "#{@base_url}/calendars/#{calendar_id}/events?#{query_params}"

    HAL.Resilience.call(
      fn -> make_request(:get, url, "", token) end,
      circuit_breaker: @circuit_breaker,
      rate_limiter: @rate_limiter,
      retry: [
        max_attempts: 3,
        base_delay: 100,
        retry_on: &retryable_error?/1
      ]
    )
    |> case do
      {:ok, %{"items" => items}} -> {:ok, items}
      {:ok, response} -> {:ok, response}
      error -> handle_error(error)
    end
  end

  @doc """
  Gets a specific event by ID.
  """
  def get_event(token, event_id, opts \\ []) do
    calendar_id = Keyword.get(opts, :calendar_id, "primary")
    url = "#{@base_url}/calendars/#{calendar_id}/events/#{event_id}"

    HAL.Resilience.call(
      fn -> make_request(:get, url, "", token) end,
      circuit_breaker: @circuit_breaker,
      rate_limiter: @rate_limiter,
      retry: [max_attempts: 3, retry_on: &retryable_error?/1]
    )
    |> handle_error()
  end

  @doc """
  Creates a new calendar event.

  ## Event Schema

      %{
        summary: "Event Title",
        description: "Event description",
        start: %{
          dateTime: "2024-01-20T10:00:00-07:00",
          timeZone: "America/Los_Angeles"
        },
        end: %{
          dateTime: "2024-01-20T11:00:00-07:00",
          timeZone: "America/Los_Angeles"
        },
        attendees: [
          %{email: "attendee@example.com"}
        ]
      }
  """
  def create_event(token, event_data, opts \\ []) do
    calendar_id = Keyword.get(opts, :calendar_id, "primary")
    url = "#{@base_url}/calendars/#{calendar_id}/events"

    body = Jason.encode!(event_data)

    HAL.Resilience.call(
      fn -> make_request(:post, url, body, token) end,
      circuit_breaker: @circuit_breaker,
      rate_limiter: @rate_limiter,
      retry: [
        max_attempts: 2,
        retry_on: &retryable_error?/1
      ]
    )
    |> handle_error()
  end

  @doc """
  Updates an existing event.
  """
  def update_event(token, event_id, updates, opts \\ []) do
    calendar_id = Keyword.get(opts, :calendar_id, "primary")
    url = "#{@base_url}/calendars/#{calendar_id}/events/#{event_id}"

    body = Jason.encode!(updates)

    HAL.Resilience.call(
      fn -> make_request(:patch, url, body, token) end,
      circuit_breaker: @circuit_breaker,
      rate_limiter: @rate_limiter,
      retry: [max_attempts: 2, retry_on: &retryable_error?/1]
    )
    |> handle_error()
  end

  @doc """
  Deletes an event.
  """
  def delete_event(token, event_id, opts \\ []) do
    calendar_id = Keyword.get(opts, :calendar_id, "primary")
    url = "#{@base_url}/calendars/#{calendar_id}/events/#{event_id}"

    HAL.Resilience.call(
      fn -> make_request(:delete, url, "", token) end,
      circuit_breaker: @circuit_breaker,
      rate_limiter: @rate_limiter,
      retry: [max_attempts: 2, retry_on: &retryable_error?/1]
    )
    |> case do
      {:ok, _} -> :ok
      error -> handle_error(error)
    end
  end

  @doc """
  Lists calendars for the authenticated user.
  """
  def list_calendars(token) do
    url = "#{@base_url}/users/me/calendarList"

    HAL.Resilience.call(
      fn -> make_request(:get, url, "", token) end,
      circuit_breaker: @circuit_breaker,
      rate_limiter: @rate_limiter,
      retry: [max_attempts: 3, retry_on: &retryable_error?/1]
    )
    |> case do
      {:ok, %{"items" => items}} -> {:ok, items}
      {:ok, response} -> {:ok, response}
      error -> handle_error(error)
    end
  end

  # Private Functions

  defp make_request(method, url, body, token) do
    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    opts = [timeout: 30_000, recv_timeout: 30_000]

    result =
      case method do
        :get -> HTTPoison.get(url, headers, opts)
        :post -> HTTPoison.post(url, body, headers, opts)
        :patch -> HTTPoison.patch(url, body, headers, opts)
        :delete -> HTTPoison.delete(url, headers, opts)
      end

    case result do
      {:ok, %{status_code: status, body: response_body}} when status in 200..299 ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %{status_code: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status_code: status}} when status in 500..599 ->
        {:error, {:http_error, status}}

      {:ok, %{status_code: status, body: response_body}} ->
        error = parse_error_response(response_body)
        {:error, {:http_error, status, error}}

      {:error, %{reason: :timeout}} ->
        {:error, :timeout}

      {:error, %{reason: :econnrefused}} ->
        {:error, :connection_refused}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_error_response(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"message" => message}}} -> message
      _ -> body
    end
  end

  defp retryable_error?({:error, error}) do
    case error do
      :timeout -> true
      :rate_limited -> true
      :connection_refused -> true
      {:http_error, status} when status in 500..599 -> true
      {:http_error, 429} -> true
      _ -> false
    end
  end

  defp retryable_error?(_), do: false

  defp handle_error({:ok, result}), do: {:ok, result}

  defp handle_error({:error, :circuit_open}) do
    {:error, "Calendar service is temporarily unavailable. Please try again in a few minutes."}
  end

  defp handle_error({:error, {:http_error, 401, _}}) do
    {:error, "Authentication failed. Please reconnect your Google Calendar."}
  end

  defp handle_error({:error, {:http_error, 403, _}}) do
    {:error, "Access denied. Please check calendar permissions."}
  end

  defp handle_error({:error, {:http_error, 404, _}}) do
    {:error, "Calendar or event not found."}
  end

  defp handle_error({:error, {:http_error, status, message}}) do
    {:error, "Calendar API error (#{status}): #{message}"}
  end

  defp handle_error({:error, error}) do
    {:error, HAL.Resilience.format_error({:error, error})}
  end

  defp encode_query_params(params) do
    params
    |> Enum.map(fn {key, value} ->
      key_str = key |> to_string() |> camelize()
      value_str = encode_value(value)
      "#{key_str}=#{URI.encode(value_str)}"
    end)
    |> Enum.join("&")
  end

  defp encode_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp encode_value(value) when is_binary(value), do: value
  defp encode_value(value), do: to_string(value)

  defp camelize(string) do
    string
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map_join(fn
      {part, 0} -> part
      {part, _} -> String.capitalize(part)
    end)
  end
end
