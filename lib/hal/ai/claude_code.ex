defmodule Hal.AI.ClaudeCode do
  @moduledoc """
  Wrapper module for the Claude Code CLI.

  This module provides an Elixir interface to the Claude Code CLI, enabling
  programmatic interaction with Claude Code from HAL. It supports:

  - Session continuity via the `--resume` flag
  - Configurable tool permissions via `--allowedTools`
  - Custom system prompts via `--append-system-prompt`
  - Structured JSON output for parsing
  - Timeout handling for long-running tasks

  ## Usage

      # New conversation
      {:ok, response, session_id} = Hal.AI.ClaudeCode.prompt(nil, "Hello, Claude!")

      # Continue existing conversation
      {:ok, response, session_id} = Hal.AI.ClaudeCode.prompt(session_id, "Follow up question")

      # With options
      {:ok, response, session_id} = Hal.AI.ClaudeCode.prompt(nil, "Help me code",
        allowed_tools: "Bash,Read,Write,Edit",
        system_prompt: "You are a coding assistant",
        timeout: 120_000
      )

  ## Response Structure

  For JSON output format (default), the response is a map with:

      %{
        result: "The text response from Claude",
        session_id: "abc123-session-id",
        is_error: false,
        cost: 0.0042,
        duration_ms: 1523,
        usage: %{
          input_tokens: 150,
          output_tokens: 45
        }
      }

  For text output format, the response is the raw text string.

  ## Error Handling

  Returns `{:error, reason}` for:
  - Command execution failures (non-zero exit code)
  - JSON parsing errors
  - Timeout errors
  - Empty responses
  """

  require Logger

  @default_timeout 60_000
  @default_output_format "json"

  @type session_id :: String.t() | nil
  @type message :: String.t()
  @type response :: map() | String.t()

  @type option ::
          {:allowed_tools, String.t()}
          | {:system_prompt, String.t()}
          | {:timeout, pos_integer()}
          | {:output_format, String.t()}
          | {:cmd_executor, function()}

  @doc """
  Sends a prompt to Claude Code CLI and returns the response.

  ## Arguments

    * `session_id` - Optional session ID for resuming conversations. Pass `nil` for new conversations.
    * `message` - The prompt message to send to Claude.
    * `opts` - Keyword list of options:
      * `:allowed_tools` - Tools that execute without permission prompts (e.g., "Bash,Read,Write,Edit")
      * `:system_prompt` - Additional system prompt to append (uses --append-system-prompt)
      * `:timeout` - Timeout in milliseconds (default: 60000)
      * `:output_format` - Output format: "json" (default) or "text"
      * `:cmd_executor` - Function for executing commands (for testing)

  ## Returns

    * `{:ok, response, session_id}` - Success with response and session ID for continuity
    * `{:error, reason}` - Error with reason (string or map)

  ## Examples

      # Simple prompt
      {:ok, response, session_id} = Hal.AI.ClaudeCode.prompt(nil, "What is Elixir?")

      # With session continuity
      {:ok, response, session_id} = Hal.AI.ClaudeCode.prompt("abc123", "Tell me more")

      # With custom options
      {:ok, response, session_id} = Hal.AI.ClaudeCode.prompt(nil, "List files",
        allowed_tools: "Bash(ls:*),Read",
        timeout: 30_000
      )
  """
  @spec prompt(session_id(), message(), [option()]) ::
          {:ok, response(), session_id()} | {:error, any()}
  def prompt(session_id, message, opts \\ []) do
    output_format = Keyword.get(opts, :output_format, @default_output_format)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    cmd_executor = Keyword.get(opts, :cmd_executor, &default_cmd_executor/3)

    args = build_args(session_id, message, opts)

    Logger.debug("Executing Claude Code CLI: claude #{Enum.join(args, " ")}")

    try do
      case cmd_executor.("claude", args, timeout: timeout) do
        {output, 0} ->
          parse_response(output, output_format)

        {output, _exit_code} ->
          parse_error_response(output, output_format)
      end
    rescue
      e in RuntimeError ->
        if String.contains?(Exception.message(e), "timeout") do
          {:error, "Command timed out after #{timeout}ms"}
        else
          {:error, "Command execution failed: #{Exception.message(e)}"}
        end
    end
  end

  @doc """
  Returns the default set of allowed tools for Claude Code.

  These tools allow Claude to read, write, and edit files, as well as
  execute bash commands. Customize this list based on your security
  requirements.
  """
  @spec default_tools() :: String.t()
  def default_tools do
    "Read,Write,Edit,Bash,Glob,Grep,WebSearch,WebFetch"
  end

  @doc """
  Builds a system prompt that includes HAL tool definitions.

  This allows Claude Code to use HAL's capabilities for memory, calendar,
  email, tasks, and notifications.

  ## Options

    * `:include_tools` - Whether to include HAL tools (default: true)
    * `:custom_instructions` - Additional instructions to append

  ## Returns

  String containing tool definitions and instructions.
  """
  @spec build_hal_system_prompt(keyword()) :: String.t()
  def build_hal_system_prompt(opts \\ []) do
    include_tools = Keyword.get(opts, :include_tools, true)
    custom = Keyword.get(opts, :custom_instructions, "")

    # Prime Directives are ALWAYS first and immutable.
    # Identity comes from SoulLoader (.claude/ + workspace files).
    identity = HAL.Autonomy.SoulLoader.load_identity_context()

    identity =
      if identity == "" do
        """
        You are HAL, a proactive AI assistant with access to the user's
        calendar, email, tasks, and long-term memory.

        You can take actions on behalf of the user when appropriate.
        Always confirm before taking irreversible actions (sending emails,
        deleting data, etc.).
        """
      else
        identity
      end

    base_prompt = HAL.Core.PrimeDirectives.as_context() <> "\n\n" <> identity

    prompt =
      if include_tools do
        tools_section = Hal.Tools.Definitions.as_system_prompt()
        base_prompt <> "\n\n" <> tools_section
      else
        base_prompt
      end

    if custom != "" do
      prompt <> "\n\n" <> custom
    else
      prompt
    end
  end

  @doc """
  Prompts Claude Code with HAL tools enabled.

  This is a convenience wrapper around `prompt/3` that automatically
  includes HAL tool definitions in the system prompt.

  ## Arguments

    * `session_id` - Optional session ID for resuming conversations
    * `message` - The prompt message to send to Claude
    * `opts` - Keyword list of options (same as `prompt/3`)
      * Additional option: `:include_hal_tools` - Include HAL tools (default: true)

  ## Returns

    * `{:ok, response, session_id}` - Success with response and session ID
    * `{:error, reason}` - Error with reason

  ## Examples

      # With HAL tools
      {:ok, response, session_id} = ClaudeCode.prompt_with_hal_tools(nil, "What's on my calendar?")

      # Without HAL tools
      {:ok, response, session_id} = ClaudeCode.prompt_with_hal_tools(nil, "Help me code",
        include_hal_tools: false
      )
  """
  @spec prompt_with_hal_tools(session_id(), message(), [option()]) ::
          {:ok, response(), session_id()} | {:error, any()}
  def prompt_with_hal_tools(session_id, message, opts \\ []) do
    include_hal_tools = Keyword.get(opts, :include_hal_tools, true)

    # Build system prompt with HAL tools
    hal_prompt = build_hal_system_prompt(include_tools: include_hal_tools)

    # Merge with any existing system prompt
    existing_prompt = Keyword.get(opts, :system_prompt, "")

    system_prompt =
      if existing_prompt != "" do
        hal_prompt <> "\n\n" <> existing_prompt
      else
        hal_prompt
      end

    # Update opts with combined system prompt
    opts = Keyword.put(opts, :system_prompt, system_prompt)

    # Call standard prompt function
    prompt(session_id, message, opts)
  end

  @doc """
  Builds the command line arguments for the Claude Code CLI.

  ## Arguments

    * `session_id` - Optional session ID for resuming (nil for new session)
    * `message` - The prompt message
    * `opts` - Keyword options

  ## Returns

  List of command line argument strings.
  """
  @spec build_args(session_id(), message(), keyword()) :: [String.t()]
  def build_args(session_id, message, opts) do
    output_format = Keyword.get(opts, :output_format, @default_output_format)

    args = [
      "-p",
      message,
      "--output-format",
      output_format
    ]

    args = maybe_add_resume(args, session_id)
    args = maybe_add_allowed_tools(args, opts)
    args = maybe_add_system_prompt(args, opts)

    args
  end

  @doc """
  Parses the response from Claude Code CLI.

  ## Arguments

    * `output` - Raw output string from the CLI
    * `format` - The output format ("json" or "text")

  ## Returns

    * `{:ok, response, session_id}` - For successful responses
    * `{:error, reason}` - For error responses or parse failures
  """
  @spec parse_response(String.t(), String.t()) ::
          {:ok, response(), session_id()} | {:error, any()}
  def parse_response(output, format)

  def parse_response("", _format) do
    {:error, "Empty response from Claude Code CLI"}
  end

  def parse_response(output, "text") do
    {:ok, String.trim(output), nil}
  end

  def parse_response(output, "json") do
    case Jason.decode(output) do
      {:ok, %{"is_error" => true} = error_data} ->
        {:error, atomize_keys(error_data)}

      {:ok, data} ->
        response = atomize_keys(data)
        session_id = Map.get(response, :session_id)
        {:ok, response, session_id}

      {:error, _reason} ->
        {:error, "Failed to parse JSON response: #{String.slice(output, 0, 100)}"}
    end
  end

  # Private functions

  defp default_cmd_executor(cmd, args, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    # Use Port for better control over the process and timeout handling
    port_opts = [:binary, :exit_status, :stderr_to_stdout, args: args]
    port = Port.open({:spawn_executable, System.find_executable(cmd)}, port_opts)

    collect_port_output(port, "", timeout)
  end

  defp collect_port_output(port, acc, timeout) do
    receive do
      {^port, {:data, data}} ->
        collect_port_output(port, acc <> data, timeout)

      {^port, {:exit_status, exit_code}} ->
        {acc, exit_code}
    after
      timeout ->
        # Kill the port/process on timeout
        Port.close(port)
        raise RuntimeError, "timeout"
    end
  end

  defp parse_error_response(output, "text") do
    {:error, String.trim(output)}
  end

  defp parse_error_response(output, "json") do
    case Jason.decode(output) do
      {:ok, data} ->
        {:error, atomize_keys(data)}

      {:error, _reason} ->
        {:error, "Command failed with output: #{String.slice(output, 0, 200)}"}
    end
  end

  defp maybe_add_resume(args, nil), do: args

  defp maybe_add_resume(args, session_id) do
    args ++ ["--resume", session_id]
  end

  defp maybe_add_allowed_tools(args, opts) do
    case Keyword.get(opts, :allowed_tools) do
      nil -> args
      tools -> args ++ ["--allowedTools", tools]
    end
  end

  defp maybe_add_system_prompt(args, opts) do
    case Keyword.get(opts, :system_prompt) do
      nil -> args
      prompt -> args ++ ["--append-system-prompt", prompt]
    end
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), atomize_keys(v)}
      {k, v} -> {k, atomize_keys(v)}
    end)
  end

  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  defp atomize_keys(value), do: value
end
