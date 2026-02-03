defmodule HAL.ToolRunner do
  @moduledoc """
  Executes tools with validation and telemetry tracking.

  The ToolRunner is responsible for:
  - Finding the correct tool module from a list of available tools
  - Validating that arguments are in the correct format (map)
  - Executing the tool and handling errors gracefully
  - Emitting telemetry events for monitoring and observability

  ## Tool Module Contract

  Tool modules must implement:
  - `schema/0` - Returns a map with at least a `:name` key
  - `execute/1` - Takes a map of arguments and returns `{:ok, result}` or `{:error, reason}`

  ## Example Tool Module

      defmodule MyTool do
        def schema, do: %{name: "my_tool"}

        def execute(%{"input" => value}) do
          {:ok, "Processed: \#{value}"}
        end
      end

  ## Usage

      tools = [MyTool, AnotherTool]

      case HAL.ToolRunner.execute("my_tool", %{"input" => "hello"}, tools) do
        {:ok, result} -> IO.puts("Success: \#{result}")
        {:error, reason} -> IO.puts("Error: \#{reason}")
      end

  ## Telemetry Events

  This module emits the following telemetry events:

  - `[:hal, :tools, :execute]` - Emitted after tool execution
    - Measurements: `%{duration: integer}` (in native time units)
    - Metadata: `%{tool: String.t(), result: :ok | :error}`
  """

  require Logger

  @doc """
  Executes a tool by name with the given arguments.

  ## Arguments

  - `tool_name` - String name of the tool to execute (must match `tool.schema().name`)
  - `args` - Map of arguments to pass to the tool's `execute/1` function
  - `tools` - List of available tool modules

  ## Returns

  - `{:ok, term()}` - Tool executed successfully, returns the result
  - `{:error, String.t()}` - Error occurred (tool not found, invalid args, or execution failed)

  ## Error Cases

  - `{:error, "Tool not found: tool_name"}` - No tool with that name exists
  - `{:error, "Invalid arguments for tool_name"}` - Args is not a map
  - `{:error, "Tool execution failed: error_details"}` - Tool raised an exception

  ## Examples

      iex> HAL.ToolRunner.execute("read_file", %{"path" => "/tmp/test.txt"}, [ReadFileTool])
      {:ok, "file contents..."}

      iex> HAL.ToolRunner.execute("nonexistent", %{}, [])
      {:error, "Tool not found: nonexistent"}
  """
  @spec execute(tool_name :: String.t(), args :: term(), tools :: [module()]) ::
          {:ok, term()} | {:error, String.t()}
  def execute(tool_name, args, tools) do
    case find_tool(tool_name, tools) do
      nil ->
        {:error, "Tool not found: #{tool_name}"}

      tool_module ->
        if is_map(args) do
          execute_tool(tool_name, tool_module, args)
        else
          {:error, "Invalid arguments for #{tool_name}"}
        end
    end
  end

  # Private Functions

  @spec find_tool(String.t(), [module()]) :: module() | nil
  defp find_tool(tool_name, tools) do
    Enum.find(tools, fn tool_module ->
      schema = tool_module.schema()
      schema.name == tool_name
    end)
  end

  @spec execute_tool(String.t(), module(), map()) :: {:ok, term()} | {:error, String.t()}
  defp execute_tool(tool_name, tool_module, args) do
    start_time = System.monotonic_time()

    try do
      result = tool_module.execute(args)
      duration = System.monotonic_time() - start_time

      case result do
        {:ok, value} ->
          emit_telemetry(tool_name, duration, :ok)
          {:ok, value}

        {:error, reason} ->
          emit_telemetry(tool_name, duration, :error)
          {:error, reason}
      end
    rescue
      exception ->
        duration = System.monotonic_time() - start_time
        emit_telemetry(tool_name, duration, :error)

        error_message = Exception.message(exception)
        Logger.error("Tool #{tool_name} execution failed: #{error_message}")

        {:error, "Tool execution failed: #{error_message}"}
    end
  end

  @spec emit_telemetry(String.t(), integer(), :ok | :error) :: :ok
  defp emit_telemetry(tool_name, duration, result) do
    :telemetry.execute(
      [:hal, :tools, :execute],
      %{duration: duration},
      %{tool: tool_name, result: result}
    )
  end
end
