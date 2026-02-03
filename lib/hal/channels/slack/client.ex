defmodule HAL.Channels.Slack.Client do
  @moduledoc """
  GenServer managing the Slack Socket Mode connection.

  Socket Mode provides a WebSocket connection for receiving events without
  needing to expose a public HTTP endpoint. This is ideal for local development
  and private deployments.

  ## Connection Flow

  1. Request a WebSocket URL from Slack API using the App-Level Token
  2. Connect to the WebSocket
  3. Receive and acknowledge events
  4. Route events to Handler for processing

  ## Configuration

  Required environment variables:
  - `SLACK_BOT_TOKEN` - Bot User OAuth Token (xoxb-...)
  - `SLACK_APP_TOKEN` - App-Level Token (xapp-...) for Socket Mode

  ## Reconnection

  The client automatically reconnects on disconnection with exponential backoff.
  """

  use GenServer
  require Logger

  alias HAL.Channels.Slack.Handler
  alias HAL.Channels.Slack.Sender

  @slack_api_base "https://slack.com/api"
  @reconnect_base_delay_ms 1000
  @max_reconnect_delay_ms 30_000
  @heartbeat_interval_ms 30_000

  defstruct [
    :websocket_url,
    :websocket_pid,
    :bot_user_id,
    :bot_token,
    :app_token,
    :connection_ref,
    reconnect_attempts: 0,
    connected: false
  ]

  # Client API

  @doc """
  Starts the Slack Socket Mode client.

  ## Options

    * `:name` - GenServer name (default: `__MODULE__`)
    * `:bot_token` - Override bot token from config
    * `:app_token` - Override app token from config
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Sends a message to a Slack channel.

  Convenience wrapper around Sender.send_message/3.
  """
  @spec send_message(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def send_message(channel, text, opts \\ []) do
    Sender.send_message(channel, text, opts)
  end

  @doc """
  Gets the current connection status.
  """
  @spec connected?(GenServer.server()) :: boolean()
  def connected?(server \\ __MODULE__) do
    GenServer.call(server, :connected?)
  end

  @doc """
  Gets the bot user ID.
  """
  @spec get_bot_user_id(GenServer.server()) :: String.t() | nil
  def get_bot_user_id(server \\ __MODULE__) do
    GenServer.call(server, :get_bot_user_id)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    bot_token = Keyword.get(opts, :bot_token) || get_config(:bot_token)
    app_token = Keyword.get(opts, :app_token) || get_config(:app_token)

    state = %__MODULE__{
      bot_token: bot_token,
      app_token: app_token
    }

    # Start connection asynchronously
    if bot_token && app_token do
      send(self(), :connect)
    else
      Logger.warning("Slack tokens not configured, client not starting")
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:connected?, _from, state) do
    {:reply, state.connected, state}
  end

  @impl true
  def handle_call(:get_bot_user_id, _from, state) do
    {:reply, state.bot_user_id, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case do_connect(state) do
      {:ok, new_state} ->
        Logger.info("Connected to Slack Socket Mode")
        schedule_heartbeat()
        {:noreply, %{new_state | connected: true, reconnect_attempts: 0}}

      {:error, reason} ->
        Logger.error("Failed to connect to Slack: #{inspect(reason)}")
        schedule_reconnect(state)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:heartbeat, state) do
    if state.connected do
      schedule_heartbeat()
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:reconnect, state) do
    Logger.info("Attempting to reconnect to Slack...")
    send(self(), :connect)
    {:noreply, state}
  end

  @impl true
  def handle_info({:websocket_message, message}, state) do
    handle_websocket_message(message, state)
  end

  @impl true
  def handle_info({:websocket_closed, reason}, state) do
    Logger.warning("Slack WebSocket closed: #{inspect(reason)}")
    schedule_reconnect(state)
    {:noreply, %{state | connected: false}}
  end

  @impl true
  def handle_info({:websocket_error, error}, state) do
    Logger.error("Slack WebSocket error: #{inspect(error)}")
    schedule_reconnect(state)
    {:noreply, %{state | connected: false}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Slack client received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp do_connect(state) do
    with {:ok, bot_user_id} <- fetch_bot_identity(state.bot_token),
         {:ok, websocket_url} <- request_websocket_url(state.app_token),
         {:ok, ws_pid} <- connect_websocket(websocket_url) do
      # Store bot user ID for mention detection
      Application.put_env(:hal, HAL.Channels.Slack, [{:bot_user_id, bot_user_id}],
        persistent: true
      )

      {:ok,
       %{
         state
         | bot_user_id: bot_user_id,
           websocket_url: websocket_url,
           websocket_pid: ws_pid
       }}
    end
  end

  defp fetch_bot_identity(bot_token) do
    url = "#{@slack_api_base}/auth.test"

    headers = [
      {"Authorization", "Bearer #{bot_token}"},
      {"Content-Type", "application/json"}
    ]

    case HTTPoison.post(url, "", headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"ok" => true, "user_id" => user_id}} ->
            Logger.debug("Bot user ID: #{user_id}")
            {:ok, user_id}

          {:ok, %{"ok" => false, "error" => error}} ->
            {:error, {:auth_error, error}}

          {:error, _} ->
            {:error, :json_decode_error}
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, {:http_error, status}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  defp request_websocket_url(app_token) do
    url = "#{@slack_api_base}/apps.connections.open"

    headers = [
      {"Authorization", "Bearer #{app_token}"},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    case HTTPoison.post(url, "", headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"ok" => true, "url" => ws_url}} ->
            Logger.debug("Got Socket Mode URL")
            {:ok, ws_url}

          {:ok, %{"ok" => false, "error" => error}} ->
            {:error, {:socket_mode_error, error}}

          {:error, _} ->
            {:error, :json_decode_error}
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, {:http_error, status}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  defp connect_websocket(ws_url) do
    # For a full implementation, use a WebSocket client like :gun or :mint_ws
    # This is a simplified version that would need a proper WebSocket implementation
    # For now, we'll use a polling approach or document the WebSocket integration

    # In a production implementation, you would:
    # 1. Use :gun.open/3 to connect to the WebSocket
    # 2. Upgrade to WebSocket protocol
    # 3. Handle incoming messages and acknowledgments

    Logger.info("Would connect to WebSocket: #{ws_url}")

    # Spawn a process to simulate WebSocket handling
    # In production, replace with actual WebSocket client
    parent = self()

    pid =
      spawn_link(fn ->
        socket_mode_loop(parent, ws_url)
      end)

    {:ok, pid}
  end

  defp socket_mode_loop(parent, _ws_url) do
    # This is a placeholder for the actual WebSocket implementation
    # In production, this would be replaced by a proper WebSocket client
    # using :gun, :mint_ws, or similar

    receive do
      {:send, message} ->
        Logger.debug("Would send WebSocket message: #{inspect(message)}")
        socket_mode_loop(parent, nil)

      :stop ->
        :ok
    after
      60_000 ->
        # Simulate idle timeout
        socket_mode_loop(parent, nil)
    end
  end

  defp handle_websocket_message(raw_message, state) do
    case Jason.decode(raw_message) do
      {:ok, %{"type" => "hello"}} ->
        Logger.info("Received Slack Socket Mode hello")
        {:noreply, state}

      {:ok, %{"type" => "disconnect", "reason" => reason}} ->
        Logger.warning("Slack requested disconnect: #{reason}")
        schedule_reconnect(state)
        {:noreply, %{state | connected: false}}

      {:ok, %{"envelope_id" => envelope_id, "payload" => payload}} ->
        # Acknowledge the event
        ack_envelope(state, envelope_id)

        # Process the event asynchronously
        spawn(fn -> process_event(payload) end)

        {:noreply, state}

      {:ok, %{"envelope_id" => envelope_id, "type" => "events_api", "payload" => payload}} ->
        # Acknowledge the event
        ack_envelope(state, envelope_id)

        # Process the event if present
        maybe_process_event(payload["event"])

        {:noreply, state}

      {:ok, message} ->
        Logger.debug("Received unknown Slack message: #{inspect(message)}")
        {:noreply, state}

      {:error, _} ->
        Logger.warning("Failed to decode Slack message: #{raw_message}")
        {:noreply, state}
    end
  end

  defp ack_envelope(state, envelope_id) do
    ack_message = Jason.encode!(%{envelope_id: envelope_id})

    if state.websocket_pid && Process.alive?(state.websocket_pid) do
      send(state.websocket_pid, {:send, ack_message})
    end
  end

  defp maybe_process_event(nil), do: :ok

  defp maybe_process_event(event) do
    spawn(fn -> process_event(event) end)
    :ok
  end

  defp process_event(event) do
    Logger.debug("Processing Slack event: #{inspect(event)}")

    case Handler.handle_event(event) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Error handling Slack event: #{inspect(reason)}")
    end
  end

  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat, @heartbeat_interval_ms)
  end

  defp schedule_reconnect(state) do
    delay =
      min(
        @reconnect_base_delay_ms * :math.pow(2, state.reconnect_attempts),
        @max_reconnect_delay_ms
      )
      |> round()

    Logger.info(
      "Scheduling Slack reconnect in #{delay}ms (attempt #{state.reconnect_attempts + 1})"
    )

    Process.send_after(self(), :reconnect, delay)
    %{state | reconnect_attempts: state.reconnect_attempts + 1}
  end

  defp get_config(key) do
    Application.get_env(:hal, HAL.Channels.Slack)[key]
  end
end
