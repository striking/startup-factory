defmodule HAL.MCP.Client do
  @moduledoc """
  MCP (Model Context Protocol) client for HAL.

  Enables HAL to connect to and use external MCP servers via stdio transport.
  This bridges HAL with the broader MCP ecosystem (50+ integrations).

  ## How It Works

  1. Spawn MCP server process via command
  2. Communicate via JSON-RPC 2.0 over stdio
  3. Discover available tools/resources
  4. Call tools and return results

  ## Usage

      # Start a server connection
      {:ok, conn} = HAL.MCP.Client.connect("npx @anthropics/mcp-server-slack")

      # List available tools
      {:ok, tools} = HAL.MCP.Client.list_tools(conn)

      # Call a tool
      {:ok, result} = HAL.MCP.Client.call_tool(conn, "send_message", %{
        channel: "#general",
        text: "Hello from HAL!"
      })

      # Disconnect
      :ok = HAL.MCP.Client.disconnect(conn)

  ## Server Configuration

  MCP servers can be configured in `~/.hal/mcp-servers.json`:

      {
        "slack": {
          "command": "npx",
          "args": ["@anthropics/mcp-server-slack"],
          "env": {"SLACK_TOKEN": "xoxb-..."}
        }
      }
  """

  use GenServer
  require Logger

  @json_rpc_version "2.0"
  @mcp_version "2024-11-05"
  @capabilities %{
    "roots" => %{"listChanged" => true},
    "sampling" => %{}
  }

  defstruct [
    :port,
    :server_name,
    :server_info,
    :capabilities,
    :request_id,
    :pending_requests,
    :tools,
    :resources
  ]

  # ============================================
  # Client API
  # ============================================

  @doc """
  Connects to an MCP server.

  ## Options

    * `:name` - Name to register the connection under
    * `:env` - Environment variables for the server process
    * `:timeout` - Connection timeout in ms (default: 30000)
  """
  @spec connect(String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def connect(command, opts \\ []) do
    name = Keyword.get(opts, :name)
    init_opts = [{:command, command} | opts]

    if name do
      GenServer.start_link(__MODULE__, init_opts, name: name)
    else
      GenServer.start_link(__MODULE__, init_opts)
    end
  end

  @doc """
  Connects to a named MCP server from configuration.

  Reads server config from `~/.hal/mcp-servers.json`.
  """
  @spec connect_named(String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def connect_named(server_name, opts \\ []) do
    case load_server_config(server_name) do
      {:ok, config} ->
        command = build_command(config)
        env = Map.get(config, "env", %{})
        connect(command, Keyword.merge(opts, env: env, server_name: server_name))

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists available tools from the connected MCP server.
  """
  @spec list_tools(GenServer.server()) :: {:ok, [map()]} | {:error, term()}
  def list_tools(conn) do
    GenServer.call(conn, :list_tools, 30_000)
  end

  @doc """
  Lists available resources from the connected MCP server.
  """
  @spec list_resources(GenServer.server()) :: {:ok, [map()]} | {:error, term()}
  def list_resources(conn) do
    GenServer.call(conn, :list_resources, 30_000)
  end

  @doc """
  Calls a tool on the MCP server.
  """
  @spec call_tool(GenServer.server(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def call_tool(conn, tool_name, arguments \\ %{}) do
    GenServer.call(conn, {:call_tool, tool_name, arguments}, 60_000)
  end

  @doc """
  Reads a resource from the MCP server.
  """
  @spec read_resource(GenServer.server(), String.t()) :: {:ok, term()} | {:error, term()}
  def read_resource(conn, uri) do
    GenServer.call(conn, {:read_resource, uri}, 30_000)
  end

  @doc """
  Disconnects from the MCP server.
  """
  @spec disconnect(GenServer.server()) :: :ok
  def disconnect(conn) do
    GenServer.stop(conn, :normal)
  end

  @doc """
  Gets information about the connected server.
  """
  @spec server_info(GenServer.server()) :: map() | nil
  def server_info(conn) do
    GenServer.call(conn, :server_info)
  end

  # ============================================
  # Server Callbacks
  # ============================================

  @impl true
  def init(opts) do
    command = Keyword.fetch!(opts, :command)
    env = Keyword.get(opts, :env, %{})
    server_name = Keyword.get(opts, :server_name, "unknown")

    # Parse command into executable and args
    [executable | args] = String.split(command, " ")

    # Build environment
    env_list = Enum.map(env, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    # Spawn the MCP server process
    port_opts = [
      :binary,
      :exit_status,
      {:line, 65536},
      {:env, env_list},
      args: args
    ]

    port = Port.open({:spawn_executable, find_executable(executable)}, port_opts)

    state = %__MODULE__{
      port: port,
      server_name: server_name,
      request_id: 1,
      pending_requests: %{},
      tools: nil,
      resources: nil
    }

    # Initialize the connection
    {:ok, state, {:continue, :initialize}}
  end

  @impl true
  def handle_continue(:initialize, state) do
    # Send initialize request
    request = %{
      "jsonrpc" => @json_rpc_version,
      "id" => state.request_id,
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => @mcp_version,
        "capabilities" => @capabilities,
        "clientInfo" => %{
          "name" => "HAL",
          "version" => "1.0.0"
        }
      }
    }

    send_request(state.port, request)

    state = %{
      state
      | request_id: state.request_id + 1,
        pending_requests: Map.put(state.pending_requests, 1, {:init, self()})
    }

    {:noreply, state}
  end

  @impl true
  def handle_call(:list_tools, from, state) do
    if state.tools do
      {:reply, {:ok, state.tools}, state}
    else
      request = build_request(state.request_id, "tools/list", %{})
      send_request(state.port, request)

      state = %{
        state
        | request_id: state.request_id + 1,
          pending_requests: Map.put(state.pending_requests, state.request_id, {:list_tools, from})
      }

      {:noreply, state}
    end
  end

  @impl true
  def handle_call(:list_resources, from, state) do
    if state.resources do
      {:reply, {:ok, state.resources}, state}
    else
      request = build_request(state.request_id, "resources/list", %{})
      send_request(state.port, request)

      state = %{
        state
        | request_id: state.request_id + 1,
          pending_requests:
            Map.put(state.pending_requests, state.request_id, {:list_resources, from})
      }

      {:noreply, state}
    end
  end

  @impl true
  def handle_call({:call_tool, tool_name, arguments}, from, state) do
    request =
      build_request(state.request_id, "tools/call", %{
        "name" => tool_name,
        "arguments" => arguments
      })

    send_request(state.port, request)

    state = %{
      state
      | request_id: state.request_id + 1,
        pending_requests: Map.put(state.pending_requests, state.request_id, {:call_tool, from})
    }

    {:noreply, state}
  end

  @impl true
  def handle_call({:read_resource, uri}, from, state) do
    request =
      build_request(state.request_id, "resources/read", %{
        "uri" => uri
      })

    send_request(state.port, request)

    state = %{
      state
      | request_id: state.request_id + 1,
        pending_requests:
          Map.put(state.pending_requests, state.request_id, {:read_resource, from})
    }

    {:noreply, state}
  end

  @impl true
  def handle_call(:server_info, _from, state) do
    {:reply, state.server_info, state}
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    case Jason.decode(line) do
      {:ok, message} ->
        handle_mcp_message(message, state)

      {:error, _} ->
        Logger.debug("MCP: Non-JSON line: #{line}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("MCP server exited with status: #{status}")
    {:stop, {:server_exited, status}, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("MCP: Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.port do
      Port.close(state.port)
    end

    :ok
  end

  # ============================================
  # Private Functions
  # ============================================

  defp handle_mcp_message(%{"id" => id, "result" => result}, state) do
    case Map.pop(state.pending_requests, id) do
      {{:init, _pid}, pending} ->
        # Initialize completed
        Logger.info("MCP: Connected to server: #{inspect(result["serverInfo"])}")

        # Send initialized notification
        notification = %{
          "jsonrpc" => @json_rpc_version,
          "method" => "notifications/initialized"
        }

        send_request(state.port, notification)

        state = %{
          state
          | server_info: result["serverInfo"],
            capabilities: result["capabilities"],
            pending_requests: pending
        }

        {:noreply, state}

      {{:list_tools, from}, pending} ->
        tools = result["tools"] || []
        GenServer.reply(from, {:ok, tools})
        {:noreply, %{state | tools: tools, pending_requests: pending}}

      {{:list_resources, from}, pending} ->
        resources = result["resources"] || []
        GenServer.reply(from, {:ok, resources})
        {:noreply, %{state | resources: resources, pending_requests: pending}}

      {{:call_tool, from}, pending} ->
        GenServer.reply(from, {:ok, result})
        {:noreply, %{state | pending_requests: pending}}

      {{:read_resource, from}, pending} ->
        GenServer.reply(from, {:ok, result})
        {:noreply, %{state | pending_requests: pending}}

      {nil, _} ->
        Logger.warning("MCP: Received response for unknown request: #{id}")
        {:noreply, state}
    end
  end

  defp handle_mcp_message(%{"id" => id, "error" => error}, state) do
    case Map.pop(state.pending_requests, id) do
      {{_, from}, pending} when is_tuple(from) ->
        GenServer.reply(from, {:error, error})
        {:noreply, %{state | pending_requests: pending}}

      _ ->
        Logger.error("MCP: Error response: #{inspect(error)}")
        {:noreply, state}
    end
  end

  defp handle_mcp_message(%{"method" => method, "params" => params}, state) do
    Logger.debug("MCP: Received notification: #{method} - #{inspect(params)}")
    {:noreply, state}
  end

  defp handle_mcp_message(message, state) do
    Logger.debug("MCP: Unknown message: #{inspect(message)}")
    {:noreply, state}
  end

  defp build_request(id, method, params) do
    %{
      "jsonrpc" => @json_rpc_version,
      "id" => id,
      "method" => method,
      "params" => params
    }
  end

  defp send_request(port, request) do
    json = Jason.encode!(request)
    Port.command(port, json <> "\n")
  end

  defp find_executable("npx"), do: System.find_executable("npx")
  defp find_executable("node"), do: System.find_executable("node")
  defp find_executable(cmd), do: System.find_executable(cmd) || cmd

  defp load_server_config(server_name) do
    config_path = Path.expand("~/.hal/mcp-servers.json")

    case File.read(config_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, config} ->
            case Map.get(config, server_name) do
              nil -> {:error, :server_not_configured}
              server_config -> {:ok, server_config}
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

  defp build_command(%{"command" => cmd, "args" => args}) do
    Enum.join([cmd | args], " ")
  end

  defp build_command(%{"command" => cmd}) do
    cmd
  end
end
