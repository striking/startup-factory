defmodule Hal.Gateway.Router do
  @moduledoc """
  Routes incoming messages to appropriate sessions.

  The Router is responsible for:
  - Determining if the bot should respond to a message
  - Parsing message content (removing bot mentions)
  - Getting or creating the appropriate session
  - Delegating message handling to the session

  ## Routing Rules

  1. **DMs (Direct Messages)**: Always respond
  2. **Group Messages with @mention**: Respond
  3. **Group Messages without @mention**: Ignore

  ## Message Format

  Messages should be maps with at least:

      %{
        channel_type: "telegram" | "slack" | "discord",
        channel_id: "unique_channel_identifier",
        user_id: "user_uuid",
        content: "message text",
        is_dm: true | false,
        mentions_bot: true | false
      }

  ## Usage

      # Route a message (typically called by channel connectors)
      case Router.route_message(router_name, message) do
        {:ok, response} -> send_response(response)
        :ignored -> :ok
        {:error, reason} -> handle_error(reason)
      end
  """

  use GenServer
  require Logger

  alias Hal.Gateway.SessionManager
  alias Hal.Gateway.SessionServer
  alias Hal.Security

  defstruct [:session_manager_name]

  @bot_mention_patterns [
    # @hal or @HAL
    ~r/^@hal\s*/i,
    # Slack-style <@U123456>
    ~r/^<@[\w]+>\s*/,
    # hal: prefix
    ~r/^hal:\s*/i
  ]

  # Client API

  @doc """
  Starts the Router.

  ## Options

    * `:name` - The name to register the GenServer under
    * `:session_manager_name` - Name of the SessionManager to use
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Routes an incoming message to the appropriate session.

  ## Arguments

    * `server` - The Router server
    * `message` - Message map (see module docs for format)
    * `opts` - Options passed to the session (e.g., `:ai_client` for testing)

  ## Returns

    * `{:ok, response}` - Message was handled, response text returned
    * `:ignored` - Message was ignored (group message without mention)
    * `{:error, reason}` - Error occurred
  """
  @spec route_message(GenServer.server(), map(), keyword()) ::
          {:ok, String.t()} | :ignored | {:error, term()}
  def route_message(server, message, opts \\ []) do
    GenServer.call(server, {:route_message, message, opts}, 120_000)
  end

  @doc """
  Determines if the bot should respond to a message.

  Returns `true` for:
  - DMs (direct messages)
  - Group messages that mention the bot

  Returns `false` for:
  - Group messages without bot mention
  """
  @spec should_respond?(map()) :: boolean()
  def should_respond?(%{is_dm: true}), do: true
  def should_respond?(%{"is_dm" => true}), do: true
  def should_respond?(%{mentions_bot: true}), do: true
  def should_respond?(%{"mentions_bot" => true}), do: true
  def should_respond?(_), do: false

  @doc """
  Parses message content, removing bot mentions.

  Examples:

      iex> Router.parse_message_content("@hal what is Elixir?")
      "what is Elixir?"

      iex> Router.parse_message_content("<@U123> help me")
      "help me"
  """
  @spec parse_message_content(String.t()) :: String.t()
  def parse_message_content(content) do
    content
    |> String.trim()
    |> remove_bot_mentions()
    |> String.trim()
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    session_manager_name = Keyword.fetch!(opts, :session_manager_name)

    state = %__MODULE__{
      session_manager_name: session_manager_name
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:route_message, message, opts}, _from, state) do
    result = do_route_message(state, message, opts)
    {:reply, result, state}
  end

  # Private Functions

  defp do_route_message(state, message, opts) do
    if should_respond?(message) do
      case Security.authorize_inbound(message) do
        :allow ->
          handle_message(state, message, opts)

        :ignored ->
          :ignored

        {:respond, response} when is_binary(response) ->
          {:ok, response}

        {:error, reason} ->
          {:error, reason}
      end
    else
      :ignored
    end
  end

  defp handle_message(state, message, opts) do
    channel_type = get_channel_type(message)
    channel_id = get_string(message, :channel_id)
    user_id = get_string(message, :user_id)
    content = get_string(message, :content) || get_string(message, :text)

    if is_nil(channel_type) or is_nil(channel_id) or is_nil(user_id) or is_nil(content) do
      {:error, :invalid_message}
    else
      # Parse content (remove mentions)
      parsed_content = parse_message_content(content)

      # Get or create session
      case SessionManager.get_or_create_session(
             state.session_manager_name,
             channel_type,
             channel_id,
             user_id
           ) do
        {:ok, session_pid} ->
          # Send message to session
          SessionServer.handle_message(session_pid, parsed_content, opts)

        {:error, reason} ->
          Logger.error("Failed to get/create session: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp remove_bot_mentions(content) do
    Enum.reduce(@bot_mention_patterns, content, fn pattern, acc ->
      Regex.replace(pattern, acc, "")
    end)
  end

  defp get_string(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp get_channel_type(message) do
    case Map.get(message, :channel_type) || Map.get(message, "channel_type") do
      nil -> nil
      type when is_atom(type) -> Atom.to_string(type)
      type when is_binary(type) -> type
      other -> to_string(other)
    end
  end
end
