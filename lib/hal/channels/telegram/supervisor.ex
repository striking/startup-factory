defmodule Hal.Channels.Telegram.Supervisor do
  @moduledoc """
  Supervisor for the Telegram channel subsystem.

  This supervisor manages all Telegram-related processes:
  - Bot: The ExGram bot module that handles Telegram updates
  - Handler: Processes incoming messages and routes to Gateway
  - Sender: Sends responses back to Telegram

  ## Architecture

  ```
  Telegram.Supervisor
  ├── Telegram.Bot (ExGram bot + polling/webhook)
  ├── Telegram.Handler (message processing GenServer)
  └── Telegram.Sender (response sending GenServer)
  ```

  ## Configuration

  Configure in `config/runtime.exs`:

      config :hal, Hal.Channels.Telegram,
        bot_token: System.get_env("TELEGRAM_BOT_TOKEN"),
        enabled: true

  ## Usage

  The supervisor is started as part of the HAL application supervision tree
  after the Gateway is ready. It can also be started manually for testing:

      {:ok, pid} = Hal.Channels.Telegram.Supervisor.start_link([])
  """

  use Supervisor

  require Logger

  @doc """
  Starts the Telegram subsystem supervisor.

  ## Options

    * `:name` - The name to register the supervisor under (default: `__MODULE__`)
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    config = get_config()

    if config[:enabled] do
      Logger.info("Starting Telegram connector...")
      start_children(opts, config)
    else
      Logger.info("Telegram connector disabled, skipping startup")
      # Return empty children list but still start supervisor
      Supervisor.init([], strategy: :one_for_one)
    end
  end

  defp start_children(opts, config) do
    bot_token = config[:bot_token]

    if bot_token && bot_token != "" do
      do_start_children(opts, bot_token)
    else
      Logger.warning("TELEGRAM_BOT_TOKEN not set, Telegram connector will not start")
      Supervisor.init([], strategy: :one_for_one)
    end
  end

  defp do_start_children(opts, bot_token) do
    # Handler and Sender names for injection
    handler_name = Keyword.get(opts, :handler_name, Hal.Channels.Telegram.Handler)
    sender_name = Keyword.get(opts, :sender_name, Hal.Channels.Telegram.Sender)

    children = [
      # Sender for sending messages back to Telegram
      {Hal.Channels.Telegram.Sender, name: sender_name, bot_token: bot_token},

      # Handler for processing incoming messages
      {Hal.Channels.Telegram.Handler,
       name: handler_name,
       sender_name: sender_name,
       session_manager: Keyword.get(opts, :session_manager, Hal.Gateway.SessionManager),
       router: Keyword.get(opts, :router, Hal.Gateway.Router)},

      # ExGram bot with polling
      {Hal.Channels.Telegram.Bot, method: :polling, token: bot_token, handler_name: handler_name}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp get_config do
    Application.get_env(:hal, __MODULE__, [])
    |> Keyword.put_new(:enabled, false)
    |> Keyword.put_new(:bot_token, nil)
  end

  @doc """
  Returns whether the Telegram connector is enabled.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    config = get_config()
    config[:enabled] && config[:bot_token] && config[:bot_token] != ""
  end
end
