defmodule Hal.Tools do
  @moduledoc """
  Main entry point for HAL's tool system.

  Provides Claude Code with access to HAL's capabilities including:
  - Long-term semantic memory
  - Calendar management
  - Email operations
  - Task/todo management
  - Notifications

  ## Architecture

  The tools system consists of:

  1. **Definitions** (`Hal.Tools.Definitions`) - Anthropic-format tool schemas
  2. **Executor** (`Hal.Tools.Executor`) - Validates and routes tool calls
  3. **Handlers** (`Hal.Tools.Handlers.*`) - Implements tool logic
  4. **Interceptor** (`Hal.Tools.Interceptor`) - Detects and processes tool calls

  ## Integration with Claude Code

  Tools are provided to Claude Code via the `--append-system-prompt` parameter:

      system_prompt = Hal.Tools.system_prompt()
      ClaudeCode.prompt(session_id, message, system_prompt: system_prompt)

  Or use the convenience wrapper:

      ClaudeCode.prompt_with_hal_tools(session_id, message)

  ## Tool Execution Flow

  1. User sends message to HAL
  2. Message is sent to Claude Code with tool definitions
  3. Claude decides whether to use tools and returns tool calls
  4. Interceptor detects tool calls and executes them via Executor
  5. Results are sent back to Claude for final response
  6. Final response is returned to user

  ## Usage

      # Get all tool definitions
      tools = Hal.Tools.all()

      # Get system prompt with tools
      prompt = Hal.Tools.system_prompt()

      # Execute a tool directly
      {:ok, result} = Hal.Tools.execute("hal_memory_search",
        %{"query" => "preferences"},
        user_id: "user-uuid"
      )

  ## Development Status

  - ✅ Memory tools - Fully functional
  - 🚧 Calendar tools - Stub implementation
  - 🚧 Email tools - Stub implementation
  - 🚧 Task tools - Stub implementation
  - ✅ Notification tools - Functional via ChannelGateway
  """

  alias Hal.Tools.{Definitions, Executor, Interceptor}

  @doc """
  Returns all HAL tool definitions in Anthropic format.

  These can be provided to Claude Code to enable tool use.
  """
  @spec all() :: list(map())
  defdelegate all(), to: Definitions

  @doc """
  Returns a system prompt that includes all HAL tool definitions.

  This prompt can be passed to Claude Code via `--append-system-prompt`.
  """
  @spec system_prompt() :: String.t()
  defdelegate system_prompt(), to: Definitions, as: :as_system_prompt

  @doc """
  Executes a tool by name with the given arguments.

  ## Arguments

    * `tool_name` - The name of the tool to execute
    * `args` - Map of arguments for the tool
    * `opts` - Context options (user_id, session_id, etc.)

  ## Returns

    * `{:ok, result}` - Successful execution
    * `{:error, error}` - Execution failed
  """
  @spec execute(String.t(), map(), keyword()) :: {:ok, map()} | {:error, map()}
  defdelegate execute(tool_name, args, opts), to: Executor

  @doc """
  Checks if a Claude Code response contains tool calls.
  """
  @spec has_tool_calls?(map() | String.t()) :: boolean()
  defdelegate has_tool_calls?(response), to: Interceptor

  @doc """
  Executes all tool calls in a response and returns results.
  """
  @spec execute_tool_calls(map(), keyword()) :: {:ok, list(map())} | {:error, any()}
  defdelegate execute_tool_calls(response, opts), to: Interceptor

  @doc """
  Continues a conversation by sending tool results back to Claude Code.
  """
  @spec continue_with_results(String.t(), list(map()), keyword()) ::
          {:ok, map(), String.t()} | {:error, any()}
  defdelegate continue_with_results(session_id, tool_results, opts \\ []), to: Interceptor

  @doc """
  Handles the complete tool execution cycle.

  Detects tool calls, executes them, and continues the conversation
  with results until a final response is received.
  """
  @spec handle_tool_cycle(map(), String.t(), keyword(), keyword()) ::
          {:ok, map(), String.t()} | {:no_tools, map(), String.t()} | {:error, any()}
  defdelegate handle_tool_cycle(response, session_id, context_opts, prompt_opts \\ []),
    to: Interceptor
end
