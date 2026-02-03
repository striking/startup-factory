defmodule HAL.AI.AgentSDK do
  @moduledoc """
  Claude Agent SDK client using a Node.js Port.

  This module provides a bridge between Elixir and the Claude Agent SDK (TypeScript).
  It uses an Erlang Port to start a Node.js process and communicate via JSON lines.

  ## Benefits

  - Official Claude Agent SDK (TypeScript, Anthropic's reference implementation)
  - All Claude Code tools: Read, Edit, Bash, WebSearch, MCP, etc.
  - Session continuity via resume
  - Better streaming support than CLI
  - Process isolation (Node crash won't crash Elixir)

  ## Usage

      # Start the client (usually via supervisor)
      {:ok, pid} = HAL.AI.AgentSDK.start_link()

      # Send a prompt
      {:ok, result} = HAL.AI.AgentSDK.prompt("Fix the bug in app.ex")

      # With session continuity
      {:ok, result, session_id} = HAL.AI.AgentSDK.prompt_with_session(nil, "Hello")
      {:ok, result2, session_id} = HAL.AI.AgentSDK.prompt_with_session(session_id, "Remember that")

      # With options
      {:ok, result} = HAL.AI.AgentSDK.prompt("Refactor auth", allowed_tools: ["Read", "Edit"])

  ## Authentication

  The SDK uses OAuth tokens from ~/.claude/ directory (same as Claude Code CLI).
  No API key needed if you have a Claude subscription.
  """

  use GenServer
  require Logger

  alias Hal.Tools.Executor, as: ToolExecutor

  @type prompt_opts :: [
          allowed_tools: [String.t()],
          system_prompt: String.t(),
          timeout: pos_integer(),
          model: String.t()
        ]

  # Default timeout for queries (5 minutes)
  @default_timeout 300_000

  # Port startup timeout
  @port_startup_timeout 30_000

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Send a prompt to Claude Agent SDK.

  This is the primary interface matching ClaudePythonClient.

  ## Options

    * `:allowed_tools` - List of tools Claude can use (default: all built-in tools)
    * `:system_prompt` - Custom system prompt to append
    * `:timeout` - Max time to wait in milliseconds (default: 300_000 = 5 min)
    * `:model` - Model to use (default: claude-sonnet-4-5-20250929)

  ## Returns

    * `{:ok, result_string}` - Success with response text
    * `{:error, reason}` - Error with reason
  """
  @spec prompt(String.t(), prompt_opts()) :: {:ok, String.t()} | {:error, term()}
  def prompt(message, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(__MODULE__, {:prompt, message, opts}, timeout + 5_000)
  end

  @doc """
  Send a prompt with explicit session management.

  Returns session_id for conversation continuity.

  ## Options

  Same as `prompt/2`.

  ## Returns

    * `{:ok, result_string, session_id}` - Success with response and session ID
    * `{:error, reason}` - Error with reason
  """
  @spec prompt_with_session(String.t() | nil, String.t(), prompt_opts()) ::
          {:ok, String.t(), String.t() | nil} | {:error, term()}
  def prompt_with_session(session_id, message, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(__MODULE__, {:prompt_with_session, session_id, message, opts}, timeout + 5_000)
  end

  @doc """
  Create a new session (pre-warming).

  Returns a session ID that can be used with `prompt_with_session/3`.
  """
  @spec create_session() :: {:ok, String.t()} | {:error, term()}
  def create_session do
    GenServer.call(__MODULE__, :create_session)
  end

  @doc """
  Close a session to free resources.
  """
  @spec close_session(String.t()) :: :ok | {:error, term()}
  def close_session(session_id) do
    GenServer.call(__MODULE__, {:close_session, session_id})
  end

  @doc """
  Get the status of the Agent SDK port.
  """
  @spec get_status() :: {:ok, map()} | {:error, term()}
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Check if the Agent SDK is available (ready to use or already running).

  Returns true if:
  - The SDK is running and processing requests
  - The SDK is ready to start on first query (lazy startup)
  - The SDK has started but is initializing

  Returns false if:
  - The SDK crashed and hasn't recovered
  - The SDK failed to start due to missing bridge or dependencies
  """
  @spec available?() :: boolean()
  def available? do
    case get_status() do
      {:ok, %{status: :running}} -> true
      {:ok, %{status: :not_started}} -> bridge_exists?()
      {:ok, %{status: :starting}} -> true
      _ -> false
    end
  end

  # Check if the bridge.js file exists (indicates SDK is properly installed)
  defp bridge_exists? do
    path = get_bridge_path()
    File.exists?(path)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    working_dir = Keyword.get(opts, :working_dir, File.cwd!())
    bridge_path = get_bridge_path()

    Logger.info("Starting HAL Agent SDK client...")
    Logger.debug("Working directory: #{working_dir}")
    Logger.debug("Bridge path: #{bridge_path}")

    state = %{
      port: nil,
      working_dir: working_dir,
      bridge_path: bridge_path,
      pending_requests: %{},
      request_counter: 0,
      status: :starting
    }

    # Start port lazily on first query, or immediately if configured
    if Keyword.get(opts, :start_immediately, false) do
      case start_port(state) do
        {:ok, new_state} ->
          {:ok, new_state}

        {:error, reason} ->
          Logger.error("Failed to start Agent SDK port: #{inspect(reason)}")
          {:ok, %{state | status: {:error, reason}}}
      end
    else
      {:ok, %{state | status: :not_started}}
    end
  end

  @impl true
  def handle_call({:prompt, message, opts}, from, state) do
    state = ensure_port_started(state)

    case state.status do
      :running ->
        {request_id, state} = next_request_id(state)

        command = build_query_command(request_id, message, nil, opts)
        send_command(state.port, command)

        timeout = Keyword.get(opts, :timeout, @default_timeout)
        timer_ref = Process.send_after(self(), {:request_timeout, request_id}, timeout)

        state =
          put_in(state.pending_requests[request_id], %{
            from: from,
            timer: timer_ref,
            type: :prompt
          })

        {:noreply, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}

      status ->
        {:reply, {:error, {:not_running, status}}, state}
    end
  end

  @impl true
  def handle_call({:prompt_with_session, session_id, message, opts}, from, state) do
    state = ensure_port_started(state)

    case state.status do
      :running ->
        {request_id, state} = next_request_id(state)

        command = build_query_command(request_id, message, session_id, opts)
        send_command(state.port, command)

        timeout = Keyword.get(opts, :timeout, @default_timeout)
        timer_ref = Process.send_after(self(), {:request_timeout, request_id}, timeout)

        state =
          put_in(state.pending_requests[request_id], %{
            from: from,
            timer: timer_ref,
            type: :prompt_with_session
          })

        {:noreply, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}

      status ->
        {:reply, {:error, {:not_running, status}}, state}
    end
  end

  @impl true
  def handle_call(:create_session, from, state) do
    state = ensure_port_started(state)

    case state.status do
      :running ->
        {request_id, state} = next_request_id(state)

        command = %{
          id: request_id,
          command: "create_session"
        }

        send_command(state.port, command)

        state =
          put_in(state.pending_requests[request_id], %{
            from: from,
            timer: nil,
            type: :create_session
          })

        {:noreply, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}

      status ->
        {:reply, {:error, {:not_running, status}}, state}
    end
  end

  @impl true
  def handle_call({:close_session, session_id}, from, state) do
    case state.status do
      :running ->
        {request_id, state} = next_request_id(state)

        command = %{
          id: request_id,
          command: "close_session",
          session_id: session_id
        }

        send_command(state.port, command)

        state =
          put_in(state.pending_requests[request_id], %{
            from: from,
            timer: nil,
            type: :close_session
          })

        {:noreply, state}

      _ ->
        # If port not running, session is already gone
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status_info = %{
      status: state.status,
      port_alive: state.port != nil,
      pending_requests: map_size(state.pending_requests),
      working_dir: state.working_dir
    }

    {:reply, {:ok, status_info}, state}
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    # Complete line received (with :line option)
    state = handle_port_line(line, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, {:noeol, _partial}}}, %{port: port} = state) do
    # Partial line (buffer overflow) - we shouldn't hit this with 1MB buffer
    Logger.warning("Received partial line from port (buffer overflow)")
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) when is_binary(data) do
    # Fallback for raw binary data (shouldn't happen with :line option)
    lines = String.split(data, "\n", trim: true)

    state =
      Enum.reduce(lines, state, fn line, acc_state ->
        handle_port_line(line, acc_state)
      end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:request_timeout, request_id}, state) do
    case Map.pop(state.pending_requests, request_id) do
      {nil, _state} ->
        # Request already completed
        {:noreply, state}

      {%{from: from}, state} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | pending_requests: state.pending_requests}}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    # Port process exited - this is normal after completing a query
    # The bridge.js process exits after the SDK completes
    if status == 0 do
      Logger.debug("Agent SDK port exited normally (status 0)")
    else
      Logger.warning("Agent SDK port exited with status: #{status}")
    end

    # Cancel any pending requests (shouldn't be any if exit was clean)
    Enum.each(state.pending_requests, fn {_id, %{from: from, timer: timer}} ->
      if timer, do: Process.cancel_timer(timer)
      GenServer.reply(from, {:error, {:port_exited, status}})
    end)

    # Port is gone, set to nil so we can lazily restart on next request
    {:noreply, %{state | port: nil, status: :idle, pending_requests: %{}}}
  end

  @impl true
  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    Logger.warning("Agent SDK port crashed: #{inspect(reason)}")

    # Cancel all pending requests
    Enum.each(state.pending_requests, fn {_id, %{from: from, timer: timer}} ->
      if timer, do: Process.cancel_timer(timer)
      GenServer.reply(from, {:error, {:port_crashed, reason}})
    end)

    {:noreply, %{state | port: nil, status: :crashed, pending_requests: %{}}}
  end

  @impl true
  def handle_info({:EXIT, _pid, reason}, state) do
    Logger.warning("Linked process exited: #{inspect(reason)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.port do
      try do
        # Check if port is still alive before trying to interact with it
        case Port.info(state.port) do
          nil ->
            # Port already closed, nothing to do
            :ok

          _info ->
            # Send shutdown command
            send_command(state.port, %{id: "shutdown", command: "shutdown"})
            # Give it a moment then close
            Process.sleep(100)
            Port.close(state.port)
        end
      rescue
        ArgumentError ->
          # Port was already closed, ignore
          :ok
      end
    end

    :ok
  end

  ## Private Functions

  defp get_bridge_path do
    priv_dir = :code.priv_dir(:hal) |> to_string()
    Path.join([priv_dir, "agent-sdk", "dist", "bridge.js"])
  end

  defp start_port(state) do
    bridge_path = state.bridge_path

    unless File.exists?(bridge_path) do
      {:error, {:bridge_not_found, bridge_path}}
    else
      port_opts = [
        :binary,
        :exit_status,
        {:line, 1_000_000},
        {:cd, state.working_dir},
        {:env, get_port_env()}
      ]

      # Find node executable
      node_path = System.find_executable("node")

      if node_path do
        port = Port.open({:spawn_executable, node_path}, [{:args, [bridge_path]} | port_opts])

        # Wait for init message
        receive do
          {^port, {:data, {:eol, line}}} ->
            case Jason.decode(line) do
              {:ok, %{"id" => "init", "success" => true}} ->
                Logger.info("Agent SDK bridge ready")
                {:ok, %{state | port: port, status: :running}}

              {:ok, %{"success" => false, "error" => error}} ->
                Port.close(port)
                {:error, {:init_failed, error}}

              {:error, _} ->
                Port.close(port)
                {:error, {:invalid_init_response, line}}
            end
        after
          @port_startup_timeout ->
            Port.close(port)
            {:error, :startup_timeout}
        end
      else
        {:error, :node_not_found}
      end
    end
  end

  defp get_port_env do
    # Get the source priv directory (where node_modules lives)
    source_priv_dir = Path.join([File.cwd!(), "priv", "agent-sdk"])
    node_modules_path = Path.join(source_priv_dir, "node_modules")

    # Pass through ALL environment variables from the Elixir process
    # The Claude SDK internally spawns the claude CLI which needs full environment
    # to function properly (auth, temp dirs, XDG paths, etc.)
    inherited_env =
      System.get_env()
      |> Enum.map(fn {key, value} ->
        {String.to_charlist(key), String.to_charlist(value)}
      end)

    # Override/add specific values we need
    override_env = [
      {~c"NODE_ENV", ~c"production"},
      # Add NODE_PATH so Node.js can find modules in source directory
      {~c"NODE_PATH", String.to_charlist(node_modules_path)},
      # Ensure TERM is set (some tools need this)
      {~c"TERM", ~c"xterm-256color"},
      # Enable SDK debug logging to capture why claude CLI fails
      {~c"DEBUG_CLAUDE_AGENT_SDK", ~c"1"},
      # Also set CI=true which often disables TTY requirements
      {~c"CI", ~c"true"},
      # Force non-interactive mode
      {~c"NONINTERACTIVE", ~c"1"}
    ]

    # Merge: inherited_env first, then overrides (later values win)
    inherited_env ++ override_env
  end

  defp ensure_port_started(%{status: :not_started} = state) do
    case start_port(state) do
      {:ok, new_state} ->
        new_state

      {:error, reason} ->
        Logger.error("Failed to start Agent SDK port: #{inspect(reason)}")
        %{state | status: {:error, reason}}
    end
  end

  defp ensure_port_started(%{status: :crashed} = state) do
    Logger.info("Restarting crashed Agent SDK port...")

    case start_port(state) do
      {:ok, new_state} ->
        new_state

      {:error, reason} ->
        Logger.error("Failed to restart Agent SDK port: #{inspect(reason)}")
        %{state | status: {:error, reason}}
    end
  end

  defp ensure_port_started(state), do: state

  defp next_request_id(state) do
    id = state.request_counter + 1
    request_id = "req-#{id}"
    {request_id, %{state | request_counter: id}}
  end

  defp build_query_command(request_id, message, session_id, opts) do
    options = %{}

    options =
      if model = Keyword.get(opts, :model) do
        Map.put(options, :model, model)
      else
        options
      end

    options =
      if tools = Keyword.get(opts, :allowed_tools) do
        Map.put(options, :allowed_tools, tools)
      else
        options
      end

    options =
      if system_prompt = Keyword.get(opts, :system_prompt) do
        Map.put(options, :system_prompt, system_prompt)
      else
        options
      end

    # Only pass resume if session_id is a valid UUID (Claude's session ID format)
    # HAL's internal session IDs (like "hal-web-...") should NOT be passed to Claude
    options =
      if session_id && is_binary(session_id) && valid_uuid?(session_id) do
        Map.put(options, :resume, session_id)
      else
        options
      end

    %{
      id: request_id,
      command: "query",
      prompt: message,
      options: options,
      context: %{
        user_id: Keyword.get(opts, :user_id),
        hal_session_id: Keyword.get(opts, :hal_session_id),
        channel_type: Keyword.get(opts, :channel_type),
        channel_id: Keyword.get(opts, :channel_id)
      }
    }
  end

  defp send_command(port, command) do
    json = Jason.encode!(command)
    Port.command(port, json <> "\n")
  end

  defp handle_port_line(line, state) do
    case Jason.decode(line) do
      {:ok, %{"type" => "hal_tool_call"} = tool_call} ->
        handle_hal_tool_call(tool_call, state)

      {:ok, %{"id" => request_id} = response} ->
        handle_response(request_id, response, state)

      {:ok, other} ->
        Logger.debug("Received non-request response: #{inspect(other)}")
        state

      {:error, _} ->
        Logger.warning("Invalid JSON from port: #{String.slice(line, 0, 100)}")
        state
    end
  end

  defp handle_hal_tool_call(
         %{
           "id" => tool_call_id,
           "tool_name" => tool_name,
           "args" => args,
           "context" => context
         },
         %{port: port} = state
       )
       when is_binary(tool_call_id) and is_binary(tool_name) and is_map(context) do
    tool_opts =
      []
      |> maybe_put_opt(:user_id, context["user_id"])
      |> maybe_put_opt(:session_id, context["hal_session_id"])
      |> maybe_put_opt(:channel_type, context["channel_type"])
      |> maybe_put_opt(:channel_id, context["channel_id"])
      # When a tool needs human approval, wait (up to a short timeout) for the user
      # to approve it in the HAL UI, then continue the tool call. This matches
      # OpenClaw-style "resume on approval" behavior.
      |> Keyword.put(:approval_wait, true)
      |> Keyword.put(:approval_wait_timeout_ms, 110_000)

    args = if is_map(args), do: args, else: %{}

    if port do
      Task.start(fn ->
        result = ToolExecutor.execute(tool_name, args, tool_opts)

        response =
          case result do
            {:ok, tool_result} ->
              %{id: tool_call_id, command: "hal_tool_result", success: true, result: tool_result}

            {:error, tool_error} ->
              %{id: tool_call_id, command: "hal_tool_result", success: false, error: tool_error}
          end

        try do
          send_command(port, response)
        rescue
          _ -> :ok
        end
      end)
    end

    state
  end

  defp handle_hal_tool_call(_other, state), do: state

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, _key, ""), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp handle_response(request_id, response, state) do
    case Map.pop(state.pending_requests, request_id) do
      {nil, _state} ->
        # Unknown request (possibly init message)
        if request_id != "init" and request_id != "system" do
          Logger.warning("Received response for unknown request: #{request_id}")
        end

        state

      {%{from: from, timer: timer, type: type}, remaining_requests} ->
        if timer, do: Process.cancel_timer(timer)

        reply =
          case response do
            %{"success" => true, "result" => result, "session_id" => session_id} ->
              case type do
                :prompt -> {:ok, result || ""}
                :prompt_with_session -> {:ok, result || "", session_id}
                :create_session -> {:ok, session_id}
                :close_session -> :ok
              end

            %{"success" => true, "result" => result} ->
              case type do
                :prompt -> {:ok, result || ""}
                :prompt_with_session -> {:ok, result || "", nil}
                :create_session -> {:ok, nil}
                :close_session -> :ok
              end

            %{"success" => true} ->
              case type do
                :prompt -> {:ok, ""}
                :prompt_with_session -> {:ok, "", nil}
                :create_session -> {:ok, nil}
                :close_session -> :ok
              end

            %{"success" => false, "error" => error} ->
              {:error, error}

            other ->
              {:error, {:unexpected_response, other}}
          end

        GenServer.reply(from, reply)
        %{state | pending_requests: remaining_requests}
    end
  end

  # Check if a string is a valid UUID format (Claude session IDs are UUIDs)
  # HAL's internal session IDs (like "hal-web-...") are NOT valid UUIDs
  defp valid_uuid?(string) when is_binary(string) do
    case Regex.run(~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i, string) do
      [_] -> true
      _ -> false
    end
  end

  defp valid_uuid?(_), do: false
end
