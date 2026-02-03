defmodule Hal.Tools.Handlers.MCP do
  @moduledoc """
  MCP (Model Context Protocol) tool wrapper.

  Exposes MCP servers/tools to the brain via HAL tools, while keeping execution
  inside HAL's policy + approvals boundary.
  """

  alias Hal.Tools.Executor

  @doc """
  Start a named MCP server connection from `~/.hal/mcp-servers.json`.
  """
  def start_named_connection(args, _opts) do
    name = Map.get(args, "name") || Map.get(args, :name)

    if is_binary(name) and String.trim(name) != "" do
      case HAL.MCP.Supervisor.start_named_connection(String.trim(name)) do
        {:ok, _pid} ->
          Executor.return_success("MCP connection started", %{name: name})

        {:error, :config_not_found} ->
          Executor.return_error("MCP config not found at ~/.hal/mcp-servers.json")

        {:error, :server_not_configured} ->
          Executor.return_error("MCP server not configured", %{name: name})

        {:error, reason} ->
          Executor.return_error("Failed to start MCP connection", %{
            name: name,
            reason: inspect(reason)
          })
      end
    else
      Executor.return_error("Missing required arg: name")
    end
  end

  @doc """
  List active MCP connections.
  """
  def list_connections(_args, _opts) do
    Executor.return_success("MCP connections", %{
      connections: HAL.MCP.Supervisor.list_connections()
    })
  end

  @doc """
  List tools for a named MCP connection.
  """
  def list_tools(args, _opts) do
    name = Map.get(args, "name") || Map.get(args, :name)

    if is_binary(name) and String.trim(name) != "" do
      case HAL.MCP.Supervisor.list_tools(String.trim(name)) do
        {:ok, tools} ->
          Executor.return_success("MCP tools listed", %{name: name, tools: tools})

        {:error, :connection_not_found} ->
          Executor.return_error("MCP connection not found", %{name: name})

        {:error, reason} ->
          Executor.return_error("Failed to list MCP tools", %{name: name, reason: inspect(reason)})
      end
    else
      Executor.return_error("Missing required arg: name")
    end
  end

  @doc """
  Call an MCP tool.
  """
  def call_tool(args, _opts) do
    name = Map.get(args, "name") || Map.get(args, :name)
    tool = Map.get(args, "tool") || Map.get(args, :tool)
    tool_args = Map.get(args, "arguments") || Map.get(args, :arguments) || %{}

    cond do
      not is_binary(name) or String.trim(name) == "" ->
        Executor.return_error("Missing required arg: name")

      not is_binary(tool) or String.trim(tool) == "" ->
        Executor.return_error("Missing required arg: tool")

      not is_map(tool_args) ->
        Executor.return_error("Invalid arg: arguments must be an object/map")

      true ->
        case HAL.MCP.Supervisor.call_tool(String.trim(name), String.trim(tool), tool_args) do
          {:ok, result} ->
            Executor.return_success("MCP tool executed", %{name: name, tool: tool, result: result})

          {:error, :connection_not_found} ->
            Executor.return_error("MCP connection not found", %{name: name})

          {:error, reason} ->
            Executor.return_error("MCP tool call failed", %{
              name: name,
              tool: tool,
              reason: inspect(reason)
            })
        end
    end
  end
end
