defmodule HAL.MCP.Supervisor do
  @moduledoc """
  Supervisor for MCP client connections.

  Manages the lifecycle of MCP server connections, allowing HAL to
  connect to multiple MCP servers simultaneously.

  ## Usage

      # Start a named connection (supervised)
      {:ok, pid} = HAL.MCP.Supervisor.start_connection("slack", "npx @anthropics/mcp-server-slack")

      # Get connection by name
      pid = HAL.MCP.Supervisor.get_connection("slack")

      # Stop a connection
      :ok = HAL.MCP.Supervisor.stop_connection("slack")
  """

  use Supervisor
  require Logger

  @registry HAL.MCP.Registry

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Registry for tracking named connections
      {Registry, keys: :unique, name: @registry},

      # DynamicSupervisor for connection processes
      {DynamicSupervisor, name: HAL.MCP.ConnectionSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  @doc """
  Starts a new MCP connection.

  ## Arguments

    * `name` - Unique name for this connection
    * `command` - Command to spawn the MCP server
    * `opts` - Additional options (env, timeout, etc.)
  """
  @spec start_connection(String.t(), String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_connection(name, command, opts \\ []) do
    # Register with our registry
    opts = Keyword.put(opts, :name, {:via, Registry, {@registry, name}})
    opts = Keyword.put(opts, :server_name, name)

    spec = %{
      id: name,
      start: {HAL.MCP.Client, :connect, [command, opts]},
      restart: :transient
    }

    case DynamicSupervisor.start_child(HAL.MCP.ConnectionSupervisor, spec) do
      {:ok, pid} ->
        Logger.info("MCP: Started connection '#{name}'")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Starts a connection from the MCP servers config file.
  """
  @spec start_named_connection(String.t()) :: {:ok, pid()} | {:error, term()}
  def start_named_connection(name) do
    config_path = Path.expand("~/.hal/mcp-servers.json")

    case File.read(config_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, config} ->
            case Map.get(config, name) do
              nil ->
                {:error, :server_not_configured}

              %{"command" => cmd} = server_config ->
                args = Map.get(server_config, "args", [])
                env = Map.get(server_config, "env", %{})
                command = Enum.join([cmd | args], " ")
                start_connection(name, command, env: env)

              _ ->
                {:error, :invalid_server_config}
            end

          {:error, _} ->
            {:error, :invalid_config}
        end

      {:error, :enoent} ->
        {:error, :config_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a connection by name.
  """
  @spec get_connection(String.t()) :: pid() | nil
  def get_connection(name) do
    case Registry.lookup(@registry, name) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Stops a connection by name.
  """
  @spec stop_connection(String.t()) :: :ok | {:error, :not_found}
  def stop_connection(name) do
    case get_connection(name) do
      nil ->
        {:error, :not_found}

      pid ->
        DynamicSupervisor.terminate_child(HAL.MCP.ConnectionSupervisor, pid)
        Logger.info("MCP: Stopped connection '#{name}'")
        :ok
    end
  end

  @doc """
  Lists all active connections.
  """
  @spec list_connections() :: [String.t()]
  def list_connections do
    Registry.select(@registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @doc """
  Calls a tool on a named connection.

  Convenience function that looks up the connection by name.
  """
  @spec call_tool(String.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def call_tool(connection_name, tool_name, arguments \\ %{}) do
    case get_connection(connection_name) do
      nil -> {:error, :connection_not_found}
      pid -> HAL.MCP.Client.call_tool(pid, tool_name, arguments)
    end
  end

  @doc """
  Lists tools available on a named connection.
  """
  @spec list_tools(String.t()) :: {:ok, [map()]} | {:error, term()}
  def list_tools(connection_name) do
    case get_connection(connection_name) do
      nil -> {:error, :connection_not_found}
      pid -> HAL.MCP.Client.list_tools(pid)
    end
  end
end
