defmodule Hal.AI.ClaudePythonClient do
  @moduledoc """
  Claude Agent SDK client using Python via ErlPort.

  This module provides a bridge between Elixir and the Claude Agent SDK (Python).
  It uses ErlPort to start a Python process and call Claude SDK functions.

  ## Benefits

  - Official Claude Agent SDK (all Claude Code tools)
  - Keeps Elixir/OTP architecture
  - Process isolation (Python crash won't crash Elixir)
  - All Claude Code features: Read, Edit, Bash, WebSearch, MCP, etc.
  - Model delegation tools (gemini, codex, jules) for cost optimization

  ## Usage

      # Start the client
      {:ok, pid} = ClaudePythonClient.start_link(working_dir: "/path/to/project")

      # Send a prompt
      {:ok, result} = ClaudePythonClient.prompt("Fix the bug in app.ex")

      # With specific tools
      {:ok, result} = ClaudePythonClient.prompt(
        "Refactor auth module",
        allowed_tools: ["Read", "Edit", "Bash"]
      )

      # With model delegation tools (enabled by default)
      {:ok, result} = ClaudePythonClient.prompt(
        "Count all test files",
        include_model_tools: true  # Claude can delegate to gemini/codex/jules
      )

  ## Model Delegation

  Claude automatically has access to three cost-optimization tools:

  - **gemini** - Fast, cheap queries ($0.15/1M tokens, 400x cheaper)
  - **codex** - Code generation ($15/1M tokens, 4x cheaper)
  - **jules** - Async background tasks ($10/1M tokens, 6x cheaper)

  Claude learns from conversation history which models work best for which tasks.
  """

  use GenServer
  require Logger

  alias Hal.AI.ClaudeCredentials

  @type prompt_opts :: [
          allowed_tools: [String.t()],
          timeout: pos_integer()
        ]

  @type tool_execution :: %{
          tool: String.t(),
          input: map(),
          result: {:ok, any()} | {:error, any()},
          duration_ms: non_neg_integer()
        }

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Send a prompt to Claude Agent SDK.

  ## Options

    * `:allowed_tools` - List of tools Claude can use (default: all built-in tools)
    * `:include_model_tools` - Enable model delegation tools (default: true)
    * `:return_raw` - Return raw messages for tool extraction (default: false)
    * `:timeout` - Max time to wait in milliseconds (default: 300_000 = 5 min)

  ## Examples

      {:ok, result} = ClaudePythonClient.prompt("List files in current directory")

      {:ok, result} = ClaudePythonClient.prompt(
        "Fix bug in app.ex",
        allowed_tools: ["Read", "Edit", "Bash"],
        timeout: 60_000
      )

      # Enable model delegation (default: enabled)
      {:ok, result} = ClaudePythonClient.prompt(
        "Count all test files",
        include_model_tools: true
      )

      # Get raw messages for tool extraction
      {:ok, {result, messages}} = ClaudePythonClient.prompt(
        "Fix bug",
        return_raw: true
      )
  """
  @spec prompt(String.t(), prompt_opts()) :: {:ok, String.t()} | {:error, term()}
  def prompt(message, opts \\ []) do
    GenServer.call(__MODULE__, {:prompt, message, opts}, get_timeout(opts))
  end

  @doc """
  Get the status of the Python agent.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Create a Python client for a session.

  Called when a new session starts.
  """
  @spec create_session_client(String.t()) :: {:ok, map()} | {:error, term()}
  def create_session_client(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:create_session_client, session_id})
  end

  @doc """
  Close a Python client for a session.

  Called when a session terminates.
  """
  @spec close_session_client(String.t()) :: {:ok, map()} | {:error, term()}
  def close_session_client(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:close_session_client, session_id})
  end

  @doc """
  Prompt with explicit session management using persistent client.
  """
  @spec prompt_with_session(String.t(), String.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, term()}
  def prompt_with_session(session_id, message, opts \\ [])
      when is_binary(session_id) and is_binary(message) do
    GenServer.call(
      __MODULE__,
      {:prompt_with_session, session_id, message, opts},
      get_timeout(opts)
    )
  end

  @doc """
  Get status of a session client (for debugging).
  """
  @spec get_session_client_status(String.t()) :: {:ok, map()} | {:error, term()}
  def get_session_client_status(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:get_session_client_status, session_id})
  end

  @doc """
  Extract tool executions from the response messages.

  ## Returns

    * A list of tool execution maps with fields: `tool`, `input`, `result`, `duration_ms`

  ## Examples

      iex> messages = [%{"type" => "tool_use", "tool" => "read", "input" => %{"path" => "/tmp/file"}, ...}]
      iex> ClaudePythonClient.extract_tool_executions(messages)
      [%{tool: "read", input: %{"path" => "/tmp/file"}, result: {:ok, "..."}, duration_ms: 123}]
  """
  @spec extract_tool_executions(list()) :: [tool_execution()]
  def extract_tool_executions(messages) when is_list(messages) do
    messages
    |> Enum.filter(&is_tool_message?/1)
    |> Enum.map(&parse_tool_execution/1)
    |> Enum.reject(&is_nil/1)
  end

  def extract_tool_executions(_), do: []

  ## Server Callbacks

  @impl true
  def init(opts) do
    working_dir = Keyword.get(opts, :working_dir, File.cwd!())
    python_path = Path.join(File.cwd!(), "python")

    Logger.info("Starting Claude Python client...")
    Logger.debug("Working directory: #{working_dir}")
    Logger.debug("Python path: #{python_path}")

    # Get Claude credentials (OAuth token or API key)
    env_vars = ClaudeCredentials.get_env_vars()

    if map_size(env_vars) == 0 do
      Logger.warning("""
      No Claude credentials found!

      Please either:
      1. Set ANTHROPIC_API_KEY environment variable
      2. Set CLAUDE_CODE_OAUTH_TOKEN environment variable
      3. Run 'claude setup-token' to authenticate with Claude subscription
      """)
    else
      # Log which auth method we're using
      cond do
        Map.has_key?(env_vars, "CLAUDE_CODE_OAUTH_TOKEN") ->
          Logger.info("Using Claude OAuth token (Claude subscription)")

          # Check subscription info
          case ClaudeCredentials.get_subscription_info() do
            {:ok, info} ->
              Logger.info(
                "Subscription: #{info.subscription_type}, Tier: #{info.rate_limit_tier}"
              )

            _ ->
              :ok
          end

        Map.has_key?(env_vars, "ANTHROPIC_API_KEY") ->
          Logger.info("Using Anthropic API key")

        true ->
          :ok
      end
    end

    # Start Python process with ErlPort
    case start_python_process(python_path, env_vars) do
      {:ok, python_pid} ->
        # Initialize Claude agent in Python
        case :python.call(python_pid, :claude_agent, :init, [to_charlist(working_dir)]) do
          result when is_binary(result) or is_list(result) ->
            result_str = to_string(result)

            if String.starts_with?(result_str, "initialized:") do
              # Validate SDK is available
              status = :python.call(python_pid, :claude_agent, :get_status, [])
              status_map = to_map(status)

              if not status_map["sdk_available"] do
                Logger.error("Claude Agent SDK not available in Python environment!")
                :python.stop(python_pid)
                {:stop, :sdk_not_installed}
              else
                Logger.info("Claude Agent SDK initialized successfully")

                Logger.info(
                  "SDK Status: Python #{status_map["python_version"]}, Auth: #{status_map["auth_method"]}"
                )

                {:ok,
                 %{
                   python_pid: python_pid,
                   working_dir: working_dir,
                   python_path: python_path
                 }}
              end
            else
              Logger.error("Failed to initialize Claude agent: #{result_str}")
              :python.stop(python_pid)
              {:stop, {:init_failed, result_str}}
            end

          error ->
            Logger.error("Failed to initialize Claude agent: #{inspect(error)}")
            :python.stop(python_pid)
            {:stop, {:init_failed, error}}
        end

      {:error, reason} ->
        Logger.error("Failed to start Python process: #{inspect(reason)}")
        {:stop, {:python_start_failed, reason}}
    end
  end

  @impl true
  def handle_call({:prompt, message, opts}, _from, state) do
    allowed_tools = Keyword.get(opts, :allowed_tools, nil)
    return_raw = Keyword.get(opts, :return_raw, false)
    include_model_tools = Keyword.get(opts, :include_model_tools, true)
    system_prompt = Keyword.get(opts, :system_prompt, nil)

    Logger.info("Prompting Claude Agent SDK: #{String.slice(message, 0..100)}")

    # Call Python function via ErlPort
    result =
      try do
        # Convert allowed_tools to charlist if present
        tools_arg =
          if allowed_tools do
            Enum.map(allowed_tools, &to_charlist/1)
          else
            :undefined
          end

        # Get model tools configuration if enabled
        custom_tools_arg =
          if include_model_tools do
            get_model_tools_config()
          else
            :undefined
          end

        # Pass system_prompt as binary (ErlPort will handle conversion)
        system_prompt_arg =
          if system_prompt do
            # Keep as Elixir string/binary
            system_prompt
          else
            :undefined
          end

        messages =
          :python.call(
            state.python_pid,
            :claude_agent,
            :prompt,
            [to_charlist(message), tools_arg, custom_tools_arg, system_prompt_arg]
          )

        if return_raw do
          # Return both the parsed result and raw messages for tool extraction
          case parse_messages(messages) do
            {:ok, result} -> {:ok, {result, messages}}
            error -> error
          end
        else
          parse_messages(messages)
        end
      rescue
        error ->
          Logger.error("Error calling Python: #{inspect(error)}")
          {:error, {:python_error, error}}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status =
      try do
        python_status = :python.call(state.python_pid, :claude_agent, :get_status, [])
        # Convert Python dict with charlist keys to Elixir map with string keys
        {:ok, to_map(python_status)}
      rescue
        error ->
          {:error, error}
      end

    {:reply, status, state}
  end

  @impl true
  def handle_call({:create_session_client, session_id}, _from, state) do
    Logger.info("Creating Python client for session: #{session_id}")

    result =
      try do
        response =
          :python.call(
            state.python_pid,
            :claude_agent,
            :create_client,
            [to_charlist(session_id)]
          )

        case response do
          resp when is_map(resp) or is_list(resp) ->
            {:ok, to_map(resp)}

          _ ->
            {:error, {:unexpected_response, response}}
        end
      rescue
        error ->
          Logger.error("Error creating session client: #{inspect(error)}")
          {:error, {:python_error, error}}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:close_session_client, session_id}, _from, state) do
    Logger.info("Closing Python client for session: #{session_id}")

    result =
      try do
        response =
          :python.call(
            state.python_pid,
            :claude_agent,
            :close_client,
            [to_charlist(session_id)]
          )

        case response do
          resp when is_map(resp) or is_list(resp) ->
            {:ok, to_map(resp)}

          _ ->
            {:error, {:unexpected_response, response}}
        end
      rescue
        error ->
          Logger.error("Error closing session client: #{inspect(error)}")
          {:error, {:python_error, error}}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:prompt_with_session, session_id, message, opts}, _from, state) do
    allowed_tools = Keyword.get(opts, :allowed_tools, nil)
    return_raw = Keyword.get(opts, :return_raw, false)
    include_model_tools = Keyword.get(opts, :include_model_tools, true)
    system_prompt = Keyword.get(opts, :system_prompt, nil)

    Logger.debug("Prompting with session client #{session_id}: #{String.slice(message, 0..100)}")

    result =
      try do
        tools_arg =
          if allowed_tools do
            Enum.map(allowed_tools, &to_charlist/1)
          else
            :undefined
          end

        # Get model tools configuration if enabled
        custom_tools_arg =
          if include_model_tools do
            get_model_tools_config()
          else
            :undefined
          end

        system_prompt_arg =
          if system_prompt do
            system_prompt
          else
            :undefined
          end

        messages =
          :python.call(
            state.python_pid,
            :claude_agent,
            :query_with_client,
            [
              to_charlist(session_id),
              to_charlist(message),
              tools_arg,
              custom_tools_arg,
              system_prompt_arg
            ]
          )

        if return_raw do
          case parse_messages(messages) do
            {:ok, result} -> {:ok, {result, messages}}
            error -> error
          end
        else
          parse_messages(messages)
        end
      rescue
        error ->
          Logger.error("Error in prompt_with_session: #{inspect(error)}")
          {:error, {:python_error, error}}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_session_client_status, session_id}, _from, state) do
    result =
      try do
        response =
          :python.call(
            state.python_pid,
            :claude_agent,
            :get_client_status,
            [to_charlist(session_id)]
          )

        {:ok, to_map(response)}
      rescue
        error ->
          {:error, {:python_error, error}}
      end

    {:reply, result, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("Stopping Claude Python client")
    :python.stop(state.python_pid)
    :ok
  end

  ## Private Functions

  defp start_python_process(python_path, env_vars) do
    try do
      # Use system Python3 with virtualenv
      venv_python = Path.join([python_path, "venv", "bin", "python3"])

      # Convert env_vars to charlists for ErlPort
      python_env =
        Enum.map(env_vars, fn {key, value} ->
          {to_charlist(key), to_charlist(value)}
        end)

      python_opts =
        if File.exists?(venv_python) do
          Logger.debug("Using virtualenv Python: #{venv_python}")

          [
            python_path: [to_charlist(python_path)],
            python: to_charlist(venv_python),
            env: python_env
          ]
        else
          Logger.debug("Using system Python3")

          [
            python_path: [to_charlist(python_path)],
            python: ~c"python3",
            env: python_env
          ]
        end

      {:ok, pid} = :python.start(python_opts)
      Logger.debug("Python process started: #{inspect(pid)}")

      # Test connection
      test_result = :python.call(pid, :claude_agent, :test_connection, [])
      Logger.debug("Test connection: #{inspect(test_result)}")

      {:ok, pid}
    rescue
      error ->
        {:error, error}
    end
  end

  defp parse_messages(messages) when is_list(messages) do
    Logger.debug("Received #{length(messages)} messages from Claude SDK")

    # Find result message - look in the last message which contains the final result
    result =
      Enum.find_value(Enum.reverse(messages), fn msg ->
        case msg do
          # Direct result string
          result when is_binary(result) ->
            result

          # Result in dict/map (handle both string keys and charlist keys)
          msg_map when is_map(msg_map) or is_list(msg_map) ->
            msg_dict = to_map(msg_map)

            cond do
              # Check for result field (string key)
              Map.has_key?(msg_dict, "result") ->
                msg_dict["result"]

              # Check for result field (charlist key)
              Map.has_key?(msg_dict, :result) ->
                charlist_to_string(msg_dict[:result])

              # Check for error field (string key)
              Map.has_key?(msg_dict, "error") ->
                {:error, msg_dict["error"]}

              # Check for error field (charlist key)
              Map.has_key?(msg_dict, :error) ->
                {:error, charlist_to_string(msg_dict[:error])}

              true ->
                nil
            end

          _ ->
            nil
        end
      end)

    case result do
      nil ->
        # No explicit result found in any message
        # This should not happen with Claude SDK, but fallback gracefully
        Logger.warning("No result field found in Claude SDK response, using full message list")
        {:ok, "No result field found in response"}

      {:error, error} ->
        {:error, error}

      result when is_binary(result) ->
        {:ok, result}

      result when is_list(result) ->
        {:ok, charlist_to_string(result)}

      result ->
        {:ok, to_string(result)}
    end
  end

  defp parse_messages(error) do
    Logger.error("Unexpected response from Python: #{inspect(error)}")
    {:error, {:unexpected_response, error}}
  end

  defp to_map(list) when is_list(list) do
    # ErlPort returns dicts as keyword lists
    Enum.into(list, %{}, fn
      {key, value} when is_binary(key) or is_atom(key) ->
        {to_string(key), value}

      {key, value} when is_list(key) ->
        {to_string(key), value}

      other ->
        Logger.warning("Unexpected list item: #{inspect(other)}")
        {"unknown", other}
    end)
  end

  defp to_map(map) when is_map(map) do
    # Convert charlist keys to string keys
    map
    |> Enum.map(fn
      {key, value} when is_list(key) ->
        {charlist_to_string(key), value}

      {key, value} when is_binary(key) or is_atom(key) ->
        {to_string(key), value}

      other ->
        other
    end)
    |> Enum.into(%{})
  end

  defp charlist_to_string(charlist) when is_list(charlist) do
    # Check if it's a valid charlist (all integers 0-255)
    if Enum.all?(charlist, &is_integer/1) do
      List.to_string(charlist)
    else
      inspect(charlist)
    end
  rescue
    _ -> inspect(charlist)
  end

  defp charlist_to_string(other), do: to_string(other)

  defp get_timeout(opts) do
    Keyword.get(opts, :timeout, 300_000)
  end

  # Private helpers for tool execution extraction

  defp is_tool_message?(msg) when is_map(msg) or is_list(msg) do
    msg_map = to_map(msg)

    Map.get(msg_map, "type") in ["tool_use", "tool_result", "tool_execution"] or
      Map.get(msg_map, "tool") != nil
  end

  defp is_tool_message?(_), do: false

  defp parse_tool_execution(msg) when is_map(msg) or is_list(msg) do
    msg_map = to_map(msg)

    try do
      tool_name = get_tool_name(msg_map)
      input = get_input(msg_map)
      result = get_result(msg_map)
      duration_ms = get_duration(msg_map)

      if tool_name do
        %{
          tool: tool_name,
          input: input || %{},
          result: result || {:ok, nil},
          duration_ms: duration_ms || 0
        }
      else
        nil
      end
    rescue
      _ -> nil
    end
  end

  defp parse_tool_execution(_), do: nil

  defp get_tool_name(msg_map) do
    Map.get(msg_map, "tool") || Map.get(msg_map, "name")
  end

  defp get_input(msg_map) do
    Map.get(msg_map, "input") || Map.get(msg_map, "params") || %{}
  end

  defp get_result(msg_map) do
    case Map.get(msg_map, "result") do
      nil ->
        # Try to find result in the message
        case Map.get(msg_map, "output") do
          nil -> {:ok, Map.get(msg_map, "content")}
          output -> {:ok, output}
        end

      result ->
        {:ok, result}
    end
  end

  defp get_duration(msg_map) do
    case Map.get(msg_map, "duration_ms") do
      nil -> 0
      duration when is_integer(duration) -> duration
      _ -> 0
    end
  end

  # Get model tools configuration for Python
  defp get_model_tools_config do
    # Convert Elixir list to format Python expects
    [
      [
        {~c"name", ~c"gemini"},
        {~c"description",
         ~c"Fast, cheap model for simple queries. Cost: $0.15/1M tokens (400x cheaper than me!). Best for: file operations, simple queries, counting."},
        {~c"input_schema",
         [
           {~c"type", ~c"object"},
           {~c"properties",
            [
              {~c"prompt",
               [
                 {~c"type", ~c"string"},
                 {~c"description", ~c"The query to send to Gemini"}
               ]}
            ]},
           {~c"required", [~c"prompt"]}
         ]}
      ],
      [
        {~c"name", ~c"codex"},
        {~c"description",
         ~c"Code generation specialist. Cost: $15/1M tokens (4x cheaper than me). Best for: writing code, implementing features, fixing bugs."},
        {~c"input_schema",
         [
           {~c"type", ~c"object"},
           {~c"properties",
            [
              {~c"prompt",
               [
                 {~c"type", ~c"string"},
                 {~c"description", ~c"The code generation task to send to Codex"}
               ]}
            ]},
           {~c"required", [~c"prompt"]}
         ]}
      ],
      [
        {~c"name", ~c"jules"},
        {~c"description",
         ~c"Async background task specialist. Cost: $10/1M tokens (6x cheaper than me). Best for: large refactoring, long-running tasks."},
        {~c"input_schema",
         [
           {~c"type", ~c"object"},
           {~c"properties",
            [
              {~c"prompt",
               [
                 {~c"type", ~c"string"},
                 {~c"description", ~c"The background task to send to Jules"}
               ]}
            ]},
           {~c"required", [~c"prompt"]}
         ]}
      ]
    ]
  end
end
