defmodule Hal.Tools.Interceptor do
  @moduledoc """
  Intercepts and executes tool calls from Claude Code responses.

  When Claude Code returns tool invocations (tool_use blocks), this module
  parses them, executes the tools, and returns results that can be sent
  back to Claude in a continuation.

  ## Tool Call Format

  Claude Code returns tool calls in the response as structured data.
  This module detects tool calls, executes them, and formats results.

  ## Usage

      # Check if response contains tool calls
      if Interceptor.has_tool_calls?(response) do
        # Execute tools and get results
        {:ok, results} = Interceptor.execute_tool_calls(response, context_opts)

        # Continue conversation with tool results
        Interceptor.continue_with_results(session_id, results)
      end

  ## Integration with Session Server

  The SessionServer should check responses for tool calls and automatically
  execute them, then continue the conversation with results.
  """

  require Logger

  alias Hal.Tools.Executor
  alias Hal.AI.ClaudeCode

  @doc """
  Checks if a Claude Code response contains tool calls.

  Tool calls are indicated by the presence of tool_use blocks or
  specific markers in the response.

  ## Examples

      iex> Interceptor.has_tool_calls?(%{result: "Some text", tool_use: [...]})
      true

      iex> Interceptor.has_tool_calls?(%{result: "Just text"})
      false
  """
  @spec has_tool_calls?(map() | String.t()) :: boolean()
  def has_tool_calls?(response) when is_map(response) do
    # Check for tool_use key in response
    Map.has_key?(response, :tool_use) and length(response.tool_use) > 0
  end

  def has_tool_calls?(_response), do: false

  @doc """
  Extracts tool calls from a Claude Code response.

  Returns a list of tool call maps, each containing:
  - `id`: Tool use ID for tracking
  - `name`: Tool name
  - `input`: Tool arguments

  ## Examples

      iex> Interceptor.extract_tool_calls(response)
      [
        %{
          id: "toolu_123",
          name: "hal_memory_search",
          input: %{"query" => "preferences"}
        }
      ]
  """
  @spec extract_tool_calls(map()) :: list(map())
  def extract_tool_calls(%{tool_use: tool_uses}) when is_list(tool_uses) do
    tool_uses
  end

  def extract_tool_calls(_response), do: []

  @doc """
  Executes tool calls and returns results.

  ## Arguments

    * `response` - Claude Code response containing tool calls
    * `opts` - Context options:
      * `:user_id` - User UUID (required)
      * `:session_id` - Session UUID (optional)
      * `:channel_type` - Channel type (optional)
      * `:channel_id` - Channel ID (optional)

  ## Returns

    * `{:ok, results}` - List of tool results (always succeeds, errors are included in results)

  ## Examples

      iex> Interceptor.execute_tool_calls(response, user_id: "uuid")
      {:ok, [
        %{
          tool_use_id: "toolu_123",
          content: %{success: true, result: [...]}
        }
      ]}
  """
  @spec execute_tool_calls(map(), keyword()) :: {:ok, list(map())}
  def execute_tool_calls(response, opts) do
    tool_calls = extract_tool_calls(response)

    if Enum.empty?(tool_calls) do
      {:ok, []}
    else
      results =
        Enum.map(tool_calls, fn tool_call ->
          execute_single_tool(tool_call, opts)
        end)

      {:ok, results}
    end
  end

  @doc """
  Continues a conversation by sending tool results back to Claude Code.

  This sends the tool results to Claude so it can process them and
  generate a final response to the user.

  ## Arguments

    * `session_id` - Claude session ID
    * `tool_results` - List of tool result maps
    * `opts` - Options for ClaudeCode.prompt/3

  ## Returns

    * `{:ok, response, session_id}` - Claude's response after processing tool results
    * `{:error, reason}` - If continuation fails
  """
  @spec continue_with_results(String.t(), list(map()), keyword()) ::
          {:ok, map(), String.t()} | {:error, any()}
  def continue_with_results(session_id, tool_results, opts \\ []) do
    # Format tool results as a continuation message
    message = format_tool_results_message(tool_results)

    Logger.debug("Continuing conversation with tool results: #{inspect(tool_results)}")

    # Send back to Claude
    ClaudeCode.prompt_with_hal_tools(session_id, message, opts)
  end

  @doc """
  Full tool execution cycle: detect, execute, and continue.

  This is a convenience function that handles the complete flow:
  1. Check if response has tool calls
  2. If yes, execute them
  3. Continue conversation with results
  4. Return final response

  ## Arguments

    * `response` - Initial Claude response (may contain tool calls)
    * `session_id` - Claude session ID
    * `context_opts` - Context options (user_id, etc.)
    * `prompt_opts` - Options for Claude prompt

  ## Returns

    * `{:ok, final_response, session_id}` - Final response after tool execution
    * `{:no_tools, response, session_id}` - Original response if no tools
    * `{:error, reason}` - If execution fails
  """
  @spec handle_tool_cycle(map(), String.t(), keyword(), keyword()) ::
          {:ok, map(), String.t()} | {:no_tools, map(), String.t()} | {:error, any()}
  def handle_tool_cycle(response, session_id, context_opts, prompt_opts \\ []) do
    if has_tool_calls?(response) do
      {:ok, tool_results} = execute_tool_calls(response, context_opts)

      # Continue with results
      case continue_with_results(session_id, tool_results, prompt_opts) do
        {:ok, final_response, new_session_id} ->
          # Recursively handle in case the new response also has tool calls
          handle_tool_cycle(final_response, new_session_id, context_opts, prompt_opts)

        {:error, reason} ->
          {:error, reason}
      end
    else
      # No tool calls, return original response
      {:no_tools, response, session_id}
    end
  end

  # Private helpers

  defp execute_single_tool(tool_call, opts) do
    %{id: tool_use_id, name: name, input: input} = tool_call

    Logger.info("Executing tool: #{name}")

    case Executor.execute(name, input, opts) do
      {:ok, result} ->
        %{
          tool_use_id: tool_use_id,
          type: "tool_result",
          content: result
        }

      {:error, error} ->
        %{
          tool_use_id: tool_use_id,
          type: "tool_result",
          content: error,
          is_error: true
        }
    end
  end

  defp format_tool_results_message(tool_results) do
    # Format as a simple message that Claude can understand
    results_text =
      tool_results
      |> Enum.map(fn result ->
        """
        Tool: #{result.tool_use_id}
        Result: #{Jason.encode!(result.content, pretty: true)}
        """
      end)
      |> Enum.join("\n\n")

    """
    Tool execution results:

    #{results_text}

    Please process these results and respond to the user.
    """
  end
end
