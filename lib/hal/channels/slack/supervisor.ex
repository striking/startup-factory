defmodule HAL.Channels.Slack.Supervisor do
  @moduledoc """
  Supervisor for the Slack channel subsystem.

  This supervisor manages:
  - `HAL.Channels.Slack.Client` - Socket Mode connection and event receiving
  - (Handler and Sender are stateless modules, not supervised processes)

  ## Supervision Strategy

  Uses `:one_for_one` strategy - if the Client crashes, only it is restarted.
  The Client has built-in reconnection logic with exponential backoff.

  ## Configuration

  The Slack subsystem requires the following configuration:

      config :hal, HAL.Channels.Slack,
        bot_token: System.get_env("SLACK_BOT_TOKEN"),
        app_token: System.get_env("SLACK_APP_TOKEN")

  ## Usage

  Typically started as part of the main application supervision tree:

      children = [
        # ... other children
        HAL.Channels.Slack.Supervisor
      ]

  Or with options:

      {HAL.Channels.Slack.Supervisor, name: :custom_slack_supervisor}
  """

  use Supervisor

  require Logger

  alias HAL.Channels.Slack.Client

  @doc """
  Starts the Slack supervisor.

  ## Options

    * `:name` - The name to register the supervisor under (default: `__MODULE__`)
    * `:client_opts` - Options passed to the Client GenServer
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    # Check if Slack is configured
    slack_config = Application.get_env(:hal, HAL.Channels.Slack, [])
    bot_token = slack_config[:bot_token]
    app_token = slack_config[:app_token]

    if bot_token && app_token do
      Logger.info("Starting Slack channel supervisor")

      client_opts = Keyword.get(opts, :client_opts, [])

      children = [
        {Client, client_opts}
      ]

      Supervisor.init(children, strategy: :one_for_one)
    else
      Logger.info("Slack tokens not configured, skipping Slack supervisor")
      # Return empty children list - supervisor starts but does nothing
      Supervisor.init([], strategy: :one_for_one)
    end
  end

  @doc """
  Checks if the Slack subsystem is properly configured.

  Returns `true` if both bot_token and app_token are set.
  """
  @spec configured?() :: boolean()
  def configured? do
    config = Application.get_env(:hal, HAL.Channels.Slack, [])
    !!(config[:bot_token] && config[:app_token])
  end

  @doc """
  Returns the current status of the Slack connection.

  ## Returns

    * `:connected` - WebSocket is connected
    * `:disconnected` - WebSocket is not connected
    * `:not_configured` - Slack tokens not set
    * `:not_running` - Supervisor/Client not running
  """
  @spec status() :: :connected | :disconnected | :not_configured | :not_running
  def status do
    cond do
      !configured?() ->
        :not_configured

      !Process.whereis(Client) ->
        :not_running

      Client.connected?() ->
        :connected

      true ->
        :disconnected
    end
  end
end
