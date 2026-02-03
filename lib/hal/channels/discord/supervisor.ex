defmodule Hal.Channels.Discord.Supervisor do
  @moduledoc """
  Supervisor for the Discord channel subsystem.

  Manages the Discord bot connection using Nostrum, including:
  - Nostrum.Bot for gateway connection
  - Consumer for handling events

  ## Configuration

  Discord integration requires the following environment variables:
  - `DISCORD_BOT_TOKEN` - Bot token from Discord Developer Portal

  Configuration in config/runtime.exs:

      config :hal, :discord,
        enabled: true,
        token: System.get_env("DISCORD_BOT_TOKEN")

  ## Starting

  The supervisor is started as part of the HAL application when
  Discord is enabled:

      # In application.ex children list:
      {Hal.Channels.Discord.Supervisor, []}

  ## Nostrum Integration

  Nostrum handles the Discord gateway connection automatically.
  This supervisor starts Nostrum.Bot with our Consumer module
  which receives all Discord events.
  """

  use Supervisor
  require Logger

  @doc """
  Starts the Discord supervisor.

  ## Options

    * `:name` - Name to register the supervisor (default: __MODULE__)
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(_opts) do
    if enabled?() do
      Logger.info("Discord: Starting Discord integration")

      children = [
        # Nostrum.Bot handles the gateway connection
        # It will automatically start our Consumer
        {Nostrum.Bot, bot_options()}
      ]

      Supervisor.init(children, strategy: :one_for_one)
    else
      Logger.info("Discord: Integration disabled (no token configured)")
      # Return empty children list - supervisor starts but does nothing
      Supervisor.init([], strategy: :one_for_one)
    end
  end

  @doc """
  Checks if Discord integration is enabled.

  Returns true if:
  - :hal, :discord, :enabled is true
  - A bot token is configured
  """
  @spec enabled?() :: boolean()
  def enabled? do
    config = Application.get_env(:hal, :discord, [])

    case config do
      config when is_list(config) ->
        Keyword.get(config, :enabled, false) and has_token?(config)

      _ ->
        false
    end
  end

  @doc """
  Returns the configured Discord bot token.
  """
  @spec get_token() :: String.t() | nil
  def get_token do
    config = Application.get_env(:hal, :discord, [])
    Keyword.get(config, :token)
  end

  # Private Functions

  defp bot_options do
    %{
      name: Hal.DiscordBot,
      consumer: Hal.Channels.Discord.Consumer,
      intents: [
        :direct_messages,
        :guild_messages,
        :message_content
      ],
      wrapped_token: fn -> get_token() end
    }
  end

  defp has_token?(config) do
    case Keyword.get(config, :token) do
      nil -> false
      "" -> false
      _token -> true
    end
  end
end
