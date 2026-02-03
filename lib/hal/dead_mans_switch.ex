defmodule HAL.DeadMansSwitch do
  @moduledoc """
  GenServer that sends periodic status reports to an admin channel.

  The DeadMansSwitch acts as a "heartbeat" for HAL, sending proactive
  status reports every 6 hours (by default) to confirm the system is
  operational and provide key metrics.

  ## Features

  - Sends status reports on a configurable schedule (default: 6 hours)
  - Collects system metrics: uptime, active sessions, messages today, memory usage
  - Sends via Telegram to a configured admin channel
  - Graceful handling if Telegram is unavailable
  - Manual trigger support for on-demand status reports

  ## Configuration

  The DeadMansSwitch can be configured via Application config:

      config :hal, HAL.DeadMansSwitch,
        admin_channel_id: "-1001234567890",
        check_interval_ms: :timer.hours(6)

  Or via start_link options:

      DeadMansSwitch.start_link(
        admin_channel_id: "-1001234567890",
        telegram_sender: Hal.Channels.Telegram.Sender,
        check_interval_ms: :timer.hours(6)
      )

  ## Message Format

  The status message includes:

  ```
  All systems operational HAL Status Report (2026-01-29 17:30:00 UTC)

  Uptime: 12h 34m
  Active Sessions: 5
  Messages Today: 127
  Memory: 342.5 MB

  All systems operational.
  ```
  """

  use GenServer
  require Logger

  @default_check_interval_ms :timer.hours(6)
  @default_dashboard_module Hal.Dashboard

  defstruct [
    :admin_channel_id,
    :telegram_sender,
    :check_interval_ms,
    :dashboard_module,
    :started_at
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the DeadMansSwitch GenServer.

  ## Options

    * `:name` - The name to register under (optional)
    * `:admin_channel_id` - Telegram channel ID for status reports (required)
    * `:telegram_sender` - Name/pid of the Telegram Sender GenServer
    * `:check_interval_ms` - Interval between check-ins (default: 6 hours)
    * `:dashboard_module` - Module providing dashboard functions (default: Hal.Dashboard)

  ## Examples

      DeadMansSwitch.start_link(
        name: HAL.DeadMansSwitch,
        admin_channel_id: "-1001234567890",
        telegram_sender: Hal.Channels.Telegram.Sender
      )
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    init_opts = Keyword.delete(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, init_opts, name: name)
    else
      GenServer.start_link(__MODULE__, init_opts)
    end
  end

  @doc """
  Gets the current uptime as a formatted string.

  ## Examples

      iex> DeadMansSwitch.get_uptime(HAL.DeadMansSwitch)
      "12h 34m"
  """
  @spec get_uptime(GenServer.server()) :: String.t()
  def get_uptime(server) do
    GenServer.call(server, :get_uptime)
  end

  @doc """
  Manually triggers a status report check-in.

  Useful for testing or when an immediate status update is needed.

  ## Examples

      iex> DeadMansSwitch.trigger_check_in(HAL.DeadMansSwitch)
      :ok
  """
  @spec trigger_check_in(GenServer.server()) :: :ok
  def trigger_check_in(server) do
    GenServer.cast(server, :trigger_check_in)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    admin_channel_id = Keyword.fetch!(opts, :admin_channel_id)
    telegram_sender = Keyword.get(opts, :telegram_sender)
    check_interval_ms = Keyword.get(opts, :check_interval_ms, @default_check_interval_ms)
    dashboard_module = Keyword.get(opts, :dashboard_module, @default_dashboard_module)

    state = %__MODULE__{
      admin_channel_id: admin_channel_id,
      telegram_sender: telegram_sender,
      check_interval_ms: check_interval_ms,
      dashboard_module: dashboard_module,
      started_at: System.monotonic_time(:millisecond)
    }

    # Schedule first check-in
    schedule_check_in(state)

    Logger.info(
      "DeadMansSwitch started, reporting to #{admin_channel_id} every #{format_interval(check_interval_ms)}"
    )

    {:ok, state}
  end

  @impl true
  def handle_info(:check_in, state) do
    send_status_report(state)
    schedule_check_in(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_uptime, _from, state) do
    uptime = calculate_uptime(state.started_at)
    {:reply, format_uptime(uptime), state}
  end

  @impl true
  def handle_cast(:trigger_check_in, state) do
    send_status_report(state)
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp schedule_check_in(state) do
    Process.send_after(self(), :check_in, state.check_interval_ms)
  end

  defp send_status_report(state) do
    metrics = collect_metrics(state)
    message = format_status_message(metrics)

    case send_to_telegram(state, message) do
      :ok ->
        Logger.debug("DeadMansSwitch: Status report sent successfully")

      {:error, reason} ->
        Logger.warning("DeadMansSwitch: Failed to send status report: #{inspect(reason)}")
    end
  end

  defp collect_metrics(state) do
    uptime_ms = calculate_uptime(state.started_at)
    dashboard = state.dashboard_module

    %{
      timestamp: DateTime.utc_now(),
      uptime: format_uptime(uptime_ms),
      active_sessions: dashboard.count_active_sessions(),
      messages_today: dashboard.count_messages_today(),
      memory_mb: get_memory_usage_mb()
    }
  end

  defp calculate_uptime(started_at) do
    System.monotonic_time(:millisecond) - started_at
  end

  defp get_memory_usage_mb do
    bytes = :erlang.memory(:total)
    Float.round(bytes / 1_048_576, 1)
  end

  defp format_status_message(metrics) do
    timestamp = Calendar.strftime(metrics.timestamp, "%Y-%m-%d %H:%M:%S UTC")

    """
    \u2705 HAL Status Report (#{timestamp})

    Uptime: #{metrics.uptime}
    Active Sessions: #{metrics.active_sessions}
    Messages Today: #{metrics.messages_today}
    Memory: #{metrics.memory_mb} MB

    All systems operational.
    """
    |> String.trim()
  end

  defp send_to_telegram(%{telegram_sender: nil}, _message) do
    Logger.debug("DeadMansSwitch: No Telegram sender configured, skipping")
    :ok
  end

  defp send_to_telegram(state, message) do
    # Try to call the send_message function on the configured sender
    # We use apply to allow for different sender implementations (mocks, real sender)
    case call_telegram_sender(state.telegram_sender, state.admin_channel_id, message) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_response, other}}
    end
  rescue
    e ->
      Logger.warning("DeadMansSwitch: Exception sending to Telegram: #{Exception.message(e)}")
      {:error, {:exception, e}}
  end

  defp call_telegram_sender(sender, chat_id, message) when is_atom(sender) do
    # Check if it's a named GenServer we can call
    if Process.whereis(sender) do
      # Use the same interface as Hal.Channels.Telegram.Sender
      apply_sender_call(sender, chat_id, message)
    else
      {:error, :sender_not_running}
    end
  end

  defp call_telegram_sender(sender, chat_id, message) when is_pid(sender) do
    if Process.alive?(sender) do
      apply_sender_call(sender, chat_id, message)
    else
      {:error, :sender_not_alive}
    end
  end

  defp apply_sender_call(sender, chat_id, message) do
    # Use GenServer call with the same message format as Hal.Channels.Telegram.Sender
    GenServer.call(sender, {:send_message, chat_id, message, []})
  end

  defp format_uptime(ms) when ms < 60_000 do
    "#{div(ms, 1000)}s"
  end

  defp format_uptime(ms) when ms < 3_600_000 do
    minutes = div(ms, 60_000)
    "#{minutes}m"
  end

  defp format_uptime(ms) when ms < 86_400_000 do
    hours = div(ms, 3_600_000)
    minutes = div(rem(ms, 3_600_000), 60_000)
    "#{hours}h #{minutes}m"
  end

  defp format_uptime(ms) do
    days = div(ms, 86_400_000)
    hours = div(rem(ms, 86_400_000), 3_600_000)
    "#{days}d #{hours}h"
  end

  defp format_interval(ms) when ms < 60_000, do: "#{div(ms, 1000)} seconds"
  defp format_interval(ms) when ms < 3_600_000, do: "#{div(ms, 60_000)} minutes"
  defp format_interval(ms), do: "#{div(ms, 3_600_000)} hours"
end
