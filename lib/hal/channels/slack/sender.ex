defmodule HAL.Channels.Slack.Sender do
  @moduledoc """
  Sends messages via the Slack Web API.

  This module handles:
  - Sending messages to channels/DMs
  - Threaded replies
  - Rate limit handling with exponential backoff
  - Message formatting

  ## Usage

      # Send a simple message
      {:ok, response} = Sender.send_message("C1234567890", "Hello!")

      # Send a threaded reply
      {:ok, response} = Sender.send_message("C1234567890", "Reply text", thread_ts: "1234567890.123456")

  ## Rate Limiting

  Slack has rate limits on API calls. This module implements:
  - Automatic retry with exponential backoff on 429 responses
  - Max 3 retries before returning error
  """

  require Logger

  @slack_api_base "https://slack.com/api"
  @max_retries 3
  @base_delay_ms 1000

  @type send_opts :: [
          thread_ts: String.t(),
          reply_broadcast: boolean(),
          unfurl_links: boolean(),
          unfurl_media: boolean()
        ]

  @doc """
  Sends a message to a Slack channel or DM.

  ## Arguments

    * `channel` - Channel ID (C...), DM ID (D...), or user ID (U...)
    * `text` - Message text
    * `opts` - Options (see below)

  ## Options

    * `:thread_ts` - Thread timestamp for threaded replies
    * `:reply_broadcast` - Also send to channel when replying in thread
    * `:unfurl_links` - Enable link previews (default: true)
    * `:unfurl_media` - Enable media previews (default: true)
    * `:bot_token` - Override default bot token

  ## Returns

    * `{:ok, response_body}` - Success with Slack API response
    * `{:error, reason}` - Error with reason atom or string
  """
  @spec send_message(String.t(), String.t(), send_opts()) :: {:ok, map()} | {:error, term()}
  def send_message(channel, text, opts \\ []) do
    bot_token = Keyword.get(opts, :bot_token) || get_bot_token()

    payload =
      %{
        channel: channel,
        text: text
      }
      |> maybe_add_thread_ts(opts)
      |> maybe_add_reply_broadcast(opts)
      |> maybe_add_unfurl_opts(opts)

    do_post_message(payload, bot_token, 0)
  end

  @doc """
  Opens a direct message channel with a user.

  ## Arguments

    * `user_id` - Slack user ID (U...)

  ## Returns

    * `{:ok, channel_id}` - Success with DM channel ID
    * `{:error, reason}` - Error
  """
  @spec open_dm(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def open_dm(user_id, opts \\ []) do
    bot_token = Keyword.get(opts, :bot_token) || get_bot_token()

    payload = %{users: user_id}

    case post_api("conversations.open", payload, bot_token) do
      {:ok, %{"ok" => true, "channel" => %{"id" => channel_id}}} ->
        {:ok, channel_id}

      {:ok, %{"ok" => false, "error" => error}} ->
        {:error, error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Adds a reaction to a message.

  ## Arguments

    * `channel` - Channel ID
    * `timestamp` - Message timestamp
    * `emoji` - Emoji name without colons (e.g., "thumbsup")
  """
  @spec add_reaction(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def add_reaction(channel, timestamp, emoji, opts \\ []) do
    bot_token = Keyword.get(opts, :bot_token) || get_bot_token()

    payload = %{
      channel: channel,
      timestamp: timestamp,
      name: emoji
    }

    case post_api("reactions.add", payload, bot_token) do
      {:ok, %{"ok" => true} = response} ->
        {:ok, response}

      {:ok, %{"ok" => false, "error" => error}} ->
        {:error, error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp do_post_message(payload, bot_token, retry_count) when retry_count < @max_retries do
    case post_api("chat.postMessage", payload, bot_token) do
      {:ok, %{"ok" => true} = response} ->
        {:ok, response}

      {:ok, %{"ok" => false, "error" => "ratelimited"}} ->
        delay = calculate_backoff(retry_count)
        Logger.warning("Slack rate limited, retrying in #{delay}ms (attempt #{retry_count + 1})")
        Process.sleep(delay)
        do_post_message(payload, bot_token, retry_count + 1)

      {:ok, %{"ok" => false, "error" => error}} ->
        {:error, error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_post_message(_payload, _bot_token, _retry_count) do
    {:error, :max_retries_exceeded}
  end

  defp post_api(method, payload, bot_token) do
    url = "#{@slack_api_base}/#{method}"

    headers = [
      {"Authorization", "Bearer #{bot_token}"},
      {"Content-Type", "application/json; charset=utf-8"}
    ]

    body = Jason.encode!(payload)

    case HTTPoison.post(url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:error, :json_decode_error}
        end

      {:ok, %HTTPoison.Response{status_code: 429, headers: headers}} ->
        retry_after = get_retry_after(headers)
        Logger.warning("Slack API rate limited, retry after #{retry_after}s")
        {:ok, %{"ok" => false, "error" => "ratelimited"}}

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.error("Slack API error: status=#{status_code}, body=#{body}")
        {:error, {:http_error, status_code}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Slack API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_bot_token do
    Application.get_env(:hal, HAL.Channels.Slack)[:bot_token] ||
      raise "Slack bot token not configured. Set SLACK_BOT_TOKEN environment variable."
  end

  defp maybe_add_thread_ts(payload, opts) do
    case Keyword.get(opts, :thread_ts) do
      nil -> payload
      ts -> Map.put(payload, :thread_ts, ts)
    end
  end

  defp maybe_add_reply_broadcast(payload, opts) do
    case Keyword.get(opts, :reply_broadcast) do
      true -> Map.put(payload, :reply_broadcast, true)
      _ -> payload
    end
  end

  defp maybe_add_unfurl_opts(payload, opts) do
    payload
    |> maybe_put(:unfurl_links, Keyword.get(opts, :unfurl_links))
    |> maybe_put(:unfurl_media, Keyword.get(opts, :unfurl_media))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp calculate_backoff(retry_count) do
    # Exponential backoff with jitter
    base = @base_delay_ms * :math.pow(2, retry_count)
    jitter = :rand.uniform(round(base * 0.3))
    round(base + jitter)
  end

  defp get_retry_after(headers) do
    headers
    |> Enum.find(fn {key, _} -> String.downcase(key) == "retry-after" end)
    |> case do
      {_, value} -> String.to_integer(value)
      nil -> 1
    end
  end
end
