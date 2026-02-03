defmodule HAL.Workers.SendMessage do
  @moduledoc """
  Oban worker for reliable outbound message delivery with rate limiting.

  Queues messages for delivery through various channels (Telegram, Slack, Discord)
  with per-channel rate limiting and automatic retry on failure.

  ## Rate Limits

  Each channel has platform-specific rate limits:
  - Telegram: 30 msg/sec globally, 1 msg/sec per group
  - Slack: 1 msg/sec per channel (Web API rate limit)
  - Discord: 50 msg/sec globally

  ## Job Args

    * `channel_type` - "telegram" | "slack" | "discord"
    * `channel_id` - Platform-specific channel identifier
    * `content` - Message text to send
    * `opts` - Platform-specific options (reply_to, parse_mode, etc.)
    * `priority` - 0 (highest) to 9 (lowest), default 5

  ## Queue Configuration

  Uses the `:messages` queue which should be configured with:

      config :hal, Oban,
        queues: [
          messages: [limit: 30, rate_limit: [allowed: 30, period: :timer.seconds(1)]]
        ]

  ## Usage

      # Queue a Telegram message
      %{
        channel_type: "telegram",
        channel_id: "123456789",
        content: "Hello!",
        opts: %{parse_mode: "Markdown"}
      }
      |> HAL.Workers.SendMessage.new()
      |> Oban.insert()

      # Queue with priority (0 = urgent, 9 = lowest)
      HAL.Workers.SendMessage.queue_message("telegram", "123", "Urgent!", priority: 0)

  ## Telemetry Events

  - `[:hal, :message, :sent]` - Message sent successfully
  - `[:hal, :message, :failed]` - Message failed after retries
  - `[:hal, :message, :rate_limited]` - Hit rate limit, will retry
  """

  use Oban.Worker,
    queue: :messages,
    max_attempts: 5,
    priority: 5

  require Logger

  alias Hal.Channels.Telegram.Sender, as: TelegramSender
  alias HAL.Channels.Slack.Sender, as: SlackSender
  alias Hal.Channels.Discord.Sender, as: DiscordSender

  @type channel_type :: String.t()
  @type channel_id :: String.t()
  @type send_opts :: map()

  # Rate limit windows (milliseconds)
  @rate_limits %{
    "telegram" => %{global: 30, per_channel: 1000},
    "slack" => %{global: 50, per_channel: 1000},
    "discord" => %{global: 50, per_channel: 20}
  }

  # Client API

  @doc """
  Queues a message for delivery.

  ## Options

    * `:priority` - Job priority 0-9 (default: 5)
    * `:scheduled_at` - Schedule for future delivery
    * All other options are passed to the channel sender

  ## Examples

      queue_message("telegram", "123456", "Hello!")
      queue_message("slack", "C123", "Hello!", thread_ts: "123.456")
      queue_message("discord", "123", "Hello!", priority: 0)
  """
  @spec queue_message(channel_type(), channel_id(), String.t(), keyword()) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  def queue_message(channel_type, channel_id, content, opts \\ []) do
    {job_opts, send_opts} = extract_job_opts(opts)

    args = %{
      channel_type: channel_type,
      channel_id: to_string(channel_id),
      content: content,
      opts: Map.new(send_opts)
    }

    args
    |> new(job_opts)
    |> Oban.insert()
  end

  @doc """
  Queues a message with high priority (for urgent notifications).
  """
  @spec queue_urgent(channel_type(), channel_id(), String.t(), keyword()) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  def queue_urgent(channel_type, channel_id, content, opts \\ []) do
    queue_message(channel_type, channel_id, content, Keyword.put(opts, :priority, 0))
  end

  @doc """
  Sends a message immediately without queueing.

  Use this for interactive responses where latency matters.
  Falls back to direct sender calls without rate limiting protection.
  """
  @spec send_now(channel_type(), channel_id(), String.t(), keyword()) ::
          :ok | {:ok, map()} | {:error, term()}
  def send_now(channel_type, channel_id, content, opts \\ []) do
    do_send(channel_type, channel_id, content, Map.new(opts))
  end

  # Oban Worker Implementation

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt}) do
    channel_type = Map.fetch!(args, "channel_type")
    channel_id = Map.fetch!(args, "channel_id")
    content = Map.fetch!(args, "content")
    opts = Map.get(args, "opts", %{})

    Logger.debug("Sending message to #{channel_type}:#{channel_id} (attempt #{attempt})")

    # Check if we should rate limit
    case check_rate_limit(channel_type, channel_id) do
      :ok ->
        perform_send(channel_type, channel_id, content, opts)

      {:wait, ms} ->
        Logger.debug("Rate limited for #{channel_type}:#{channel_id}, snoozing #{ms}ms")
        emit_rate_limited(channel_type, channel_id)
        {:snooze, div(ms, 1000) + 1}
    end
  end

  # Private Functions

  defp perform_send(channel_type, channel_id, content, opts) do
    case do_send(channel_type, channel_id, content, opts) do
      :ok ->
        record_send(channel_type, channel_id)
        emit_sent(channel_type, channel_id, content)
        :ok

      {:ok, _response} ->
        record_send(channel_type, channel_id)
        emit_sent(channel_type, channel_id, content)
        :ok

      {:error, :rate_limited} ->
        # Platform rate limited - snooze and retry
        Logger.warning("Platform rate limit hit for #{channel_type}:#{channel_id}")
        emit_rate_limited(channel_type, channel_id)
        {:snooze, 5}

      {:error, reason} = error ->
        Logger.error(
          "Failed to send message to #{channel_type}:#{channel_id}: #{inspect(reason)}"
        )

        emit_failed(channel_type, channel_id, reason)
        error
    end
  end

  defp do_send("telegram", channel_id, content, opts) do
    sender = telegram_sender()

    if sender do
      send_opts = convert_telegram_opts(opts)
      TelegramSender.send_message(sender, channel_id, content, send_opts)
    else
      {:error, :telegram_not_configured}
    end
  end

  defp do_send("slack", channel_id, content, opts) do
    send_opts = convert_slack_opts(opts)
    SlackSender.send_message(channel_id, content, send_opts)
  end

  defp do_send("discord", channel_id, content, opts) do
    send_opts = convert_discord_opts(opts)
    DiscordSender.send_message(channel_id, content, send_opts)
  end

  defp do_send(channel_type, _channel_id, _content, _opts) do
    {:error, {:unknown_channel_type, channel_type}}
  end

  # Option conversion for each platform

  defp convert_telegram_opts(opts) do
    opts
    |> Enum.map(fn
      {"parse_mode", v} -> {:parse_mode, v}
      {"reply_to_message_id", v} -> {:reply_to_message_id, v}
      {"disable_notification", v} -> {:disable_notification, v}
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
      pair -> pair
    end)
  end

  defp convert_slack_opts(opts) do
    opts
    |> Enum.map(fn
      {"thread_ts", v} -> {:thread_ts, v}
      {"reply_broadcast", v} -> {:reply_broadcast, v}
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
      pair -> pair
    end)
  end

  defp convert_discord_opts(opts) do
    opts
    |> Enum.map(fn
      {"reply_to", v} -> {:reply_to, v}
      {"embed", v} -> {:embed, v}
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
      pair -> pair
    end)
  end

  # Rate limiting using ETS

  defp check_rate_limit(channel_type, channel_id) do
    limits = Map.get(@rate_limits, channel_type, %{global: 50, per_channel: 100})
    now = System.monotonic_time(:millisecond)
    key = {channel_type, channel_id}

    # Get last send time for this channel
    case :persistent_term.get({:hal_message_rate, key}, nil) do
      nil ->
        :ok

      last_send ->
        elapsed = now - last_send
        min_interval = limits.per_channel

        if elapsed < min_interval do
          {:wait, min_interval - elapsed}
        else
          :ok
        end
    end
  rescue
    # persistent_term not initialized
    ArgumentError -> :ok
  end

  defp record_send(channel_type, channel_id) do
    now = System.monotonic_time(:millisecond)
    key = {channel_type, channel_id}

    try do
      :persistent_term.put({:hal_message_rate, key}, now)
    rescue
      ArgumentError -> :ok
    end
  end

  # Telemetry

  defp emit_sent(channel_type, channel_id, content) do
    :telemetry.execute(
      [:hal, :message, :sent],
      %{content_length: String.length(content)},
      %{channel_type: channel_type, channel_id: channel_id}
    )
  end

  defp emit_failed(channel_type, channel_id, reason) do
    :telemetry.execute(
      [:hal, :message, :failed],
      %{},
      %{channel_type: channel_type, channel_id: channel_id, reason: reason}
    )
  end

  defp emit_rate_limited(channel_type, channel_id) do
    :telemetry.execute(
      [:hal, :message, :rate_limited],
      %{},
      %{channel_type: channel_type, channel_id: channel_id}
    )
  end

  # Helpers

  defp extract_job_opts(opts) do
    job_keys = [:priority, :scheduled_at, :max_attempts, :tags, :unique]

    job_opts =
      opts
      |> Keyword.take(job_keys)

    send_opts =
      opts
      |> Keyword.drop(job_keys)

    {job_opts, send_opts}
  end

  defp telegram_sender do
    # Try to find running Telegram sender
    try do
      Process.whereis(Hal.Channels.Telegram.Sender)
    catch
      _, _ -> nil
    end
  end
end
