defmodule HAL.Agents.Codex do
  @moduledoc """
  Delegation module for OpenAI Codex SDK.

  This module provides a bridge between Elixir and the OpenAI Codex SDK (TypeScript).
  It uses an Erlang Port to start a Node.js process and communicate via JSON lines.

  ## Benefits

  - Official Codex SDK (TypeScript, OpenAI's reference implementation)
  - Thread management with resume capability
  - Better error handling than CLI
  - Process isolation (Node crash won't crash Elixir)

  ## Architecture

  Claude decides to delegate → calls HAL.Agents.Codex → Codex SDK executes

  ## Usage

      # Start a coding session
      {:ok, session} = Codex.start_session("Build an auth system", project_path: "/path")

      # Continue the conversation
      {:ok, result} = Codex.run(session.id, "Now add tests")

      # Resume a previous session
      {:ok, session} = Codex.resume_session("codex-thread-id")

  ## Authentication

  The SDK uses OAuth tokens from ChatGPT login.
  Run `codex` CLI once to authenticate if needed.
  """

  use GenServer
  require Logger

  @type session_id :: String.t()
  @type codex_thread_id :: String.t()
  @type session :: %{
          id: session_id(),
          codex_thread_id: codex_thread_id() | nil,
          status: :pending | :running | :completed | :failed,
          task: String.t(),
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          result: map() | nil,
          error: String.t() | nil
        }

  @type run_opts :: [
          timeout: pos_integer(),
          model: String.t()
        ]

  # Default timeout for queries (10 minutes - Codex can take a while)
  @default_timeout 600_000

  # Port startup timeout
  @port_startup_timeout 30_000

  # Client API

  @doc """
  Start the Codex agent GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start a new Codex coding session.

  Creates a new thread and optionally runs an initial prompt.

  ## Options

    * `:project_path` - Path to the project directory (default: cwd)
    * `:timeout` - Max time to wait in milliseconds (default: 600_000 = 10 min)

  ## Returns

    * `{:ok, session}` - Session started successfully
    * `{:error, reason}` - Failed to start session
  """
  @spec start_session(String.t(), keyword()) :: {:ok, session()} | {:error, term()}
  def start_session(task, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(__MODULE__, {:start_session, task, opts}, timeout + 5_000)
  end

  @doc """
  Run a prompt on an existing session.

  ## Options

    * `:timeout` - Max time to wait in milliseconds (default: 600_000)

  ## Returns

    * `{:ok, result}` - Success with response text
    * `{:error, reason}` - Error with reason
  """
  @spec run(session_id(), String.t(), run_opts()) :: {:ok, String.t()} | {:error, term()}
  def run(session_id, prompt, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(__MODULE__, {:run, session_id, prompt, opts}, timeout + 5_000)
  end

  @doc """
  Resume a previous Codex session by its thread ID.

  Use this to continue a conversation from a previous session.

  ## Returns

    * `{:ok, session}` - Session resumed successfully
    * `{:error, reason}` - Failed to resume session
  """
  @spec resume_session(codex_thread_id()) :: {:ok, session()} | {:error, term()}
  def resume_session(codex_thread_id) do
    GenServer.call(__MODULE__, {:resume_session, codex_thread_id})
  end

  @doc """
  Check the status of a Codex session.
  """
  @spec check_status(session_id()) :: {:ok, session()} | {:error, :not_found}
  def check_status(session_id) do
    GenServer.call(__MODULE__, {:check_status, session_id})
  end

  @doc """
  Get the result of a completed Codex session.
  """
  @spec get_result(session_id()) :: {:ok, map()} | {:error, :not_found | :not_completed}
  def get_result(session_id) do
    GenServer.call(__MODULE__, {:get_result, session_id})
  end

  @doc """
  Cancel a running Codex session.
  """
  @spec cancel_session(session_id()) :: :ok | {:error, :not_found}
  def cancel_session(session_id) do
    GenServer.call(__MODULE__, {:cancel_session, session_id})
  end

  @doc """
  List all active sessions.
  """
  @spec list_sessions() :: [session()]
  def list_sessions do
    GenServer.call(__MODULE__, :list_sessions)
  end

  @doc """
  Check if the Codex SDK is available.
  """
  @spec available?() :: boolean()
  def available? do
    # Check CLI first (simpler), then SDK bridge
    cli_available?() or sdk_available?()
  end

  @doc """
  Check if Codex CLI is available.
  """
  def cli_available? do
    System.find_executable("codex") != nil
  end

  @doc """
  Check if SDK bridge is available.
  """
  def sdk_available? do
    case GenServer.call(__MODULE__, :get_status) do
      {:ok, %{status: :running}} -> true
      {:ok, %{status: :not_started}} -> bridge_exists?()
      {:ok, %{status: :starting}} -> true
      _ -> false
    end
  end

  @doc """
  Run a simple prompt via Codex CLI (non-interactive).

  This is a simpler alternative to the full SDK session management.
  Uses OAuth authentication from `codex login`.

  ## Options

    * `:working_dir` - Directory to run in (default: cwd)
    * `:timeout` - Max time in ms (default: 300_000 = 5 min)

  ## Returns

    * `{:ok, result}` - Success with response
    * `{:error, reason}` - Failure
  """
  @spec exec(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def exec(prompt, opts \\ []) do
    case System.find_executable("codex") do
      nil ->
        {:error, :codex_cli_not_found}

      codex_path ->
        working_dir = Keyword.get(opts, :working_dir, File.cwd!())
        timeout = Keyword.get(opts, :timeout, 300_000)

        # Use codex exec for non-interactive execution
        args = ["exec", prompt]

        task =
          Task.async(fn ->
            System.cmd(codex_path, args,
              cd: working_dir,
              stderr_to_stdout: true
            )
          end)

        case Task.yield(task, timeout) || Task.shutdown(task) do
          {:ok, {output, 0}} ->
            {:ok, String.trim(output)}

          {:ok, {error, code}} ->
            Logger.warning("Codex CLI exited with code #{code}: #{String.slice(error, 0, 200)}")
            {:error, {:exit_code, code, error}}

          nil ->
            {:error, :timeout}
        end
    end
  end

  # Check if the bridge.js file exists
  defp bridge_exists? do
    path = get_bridge_path()
    File.exists?(path)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    working_dir = Keyword.get(opts, :working_dir, File.cwd!())
    bridge_path = get_bridge_path()

    Logger.info("Starting HAL Codex SDK client...")

    state = %{
      port: nil,
      working_dir: working_dir,
      bridge_path: bridge_path,
      sessions: %{},
      pending_requests: %{},
      request_counter: 0,
      status: :not_started
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_session, task, opts}, from, state) do
    state = ensure_port_started(state)

    case state.status do
      :running ->
        session_id = generate_session_id()
        {request_id, state} = next_request_id(state)

        # First create the thread
        command = %{
          id: request_id,
          command: "start_thread",
          project_path: Keyword.get(opts, :project_path, state.working_dir)
        }

        send_command(state.port, command)

        session = %{
          id: session_id,
          codex_thread_id: nil,
          status: :pending,
          task: task,
          opts: opts,
          started_at: DateTime.utc_now(),
          completed_at: nil,
          result: nil,
          error: nil
        }

        timeout = Keyword.get(opts, :timeout, @default_timeout)
        timer_ref = Process.send_after(self(), {:request_timeout, request_id}, timeout)

        state = put_in(state.sessions[session_id], session)

        state =
          put_in(state.pending_requests[request_id], %{
            from: from,
            timer: timer_ref,
            type: :start_session,
            session_id: session_id,
            initial_task: task
          })

        {:noreply, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}

      status ->
        {:reply, {:error, {:not_running, status}}, state}
    end
  end

  @impl true
  def handle_call({:run, session_id, prompt, opts}, from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{codex_thread_id: nil} ->
        {:reply, {:error, :session_not_ready}, state}

      %{codex_thread_id: thread_id} = session ->
        state = ensure_port_started(state)

        case state.status do
          :running ->
            {request_id, state} = next_request_id(state)

            command = %{
              id: request_id,
              command: "run",
              thread_id: thread_id,
              prompt: prompt,
              options: %{
                model: Keyword.get(opts, :model),
                timeout: Keyword.get(opts, :timeout)
              }
            }

            send_command(state.port, command)

            timeout = Keyword.get(opts, :timeout, @default_timeout)
            timer_ref = Process.send_after(self(), {:request_timeout, request_id}, timeout)

            # Update session status
            session = %{session | status: :running}
            state = put_in(state.sessions[session_id], session)

            state =
              put_in(state.pending_requests[request_id], %{
                from: from,
                timer: timer_ref,
                type: :run,
                session_id: session_id
              })

            {:noreply, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}

          status ->
            {:reply, {:error, {:not_running, status}}, state}
        end
    end
  end

  @impl true
  def handle_call({:resume_session, codex_thread_id}, from, state) do
    state = ensure_port_started(state)

    case state.status do
      :running ->
        session_id = generate_session_id()
        {request_id, state} = next_request_id(state)

        command = %{
          id: request_id,
          command: "resume_thread",
          thread_id: codex_thread_id
        }

        send_command(state.port, command)

        session = %{
          id: session_id,
          codex_thread_id: codex_thread_id,
          status: :pending,
          task: "Resumed session",
          started_at: DateTime.utc_now(),
          completed_at: nil,
          result: nil,
          error: nil
        }

        state = put_in(state.sessions[session_id], session)

        state =
          put_in(state.pending_requests[request_id], %{
            from: from,
            timer: nil,
            type: :resume_session,
            session_id: session_id
          })

        {:noreply, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}

      status ->
        {:reply, {:error, {:not_running, status}}, state}
    end
  end

  @impl true
  def handle_call({:check_status, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil -> {:reply, {:error, :not_found}, state}
      session -> {:reply, {:ok, session}, state}
    end
  end

  @impl true
  def handle_call({:get_result, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil -> {:reply, {:error, :not_found}, state}
      %{status: :completed, result: result} -> {:reply, {:ok, result}, state}
      _ -> {:reply, {:error, :not_completed}, state}
    end
  end

  @impl true
  def handle_call({:cancel_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      session ->
        session = %{session | status: :failed, error: "Cancelled by user"}
        state = put_in(state.sessions[session_id], session)
        Logger.info("Cancelled Codex session #{session_id}")
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:list_sessions, _from, state) do
    sessions = Map.values(state.sessions)
    {:reply, sessions, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status_info = %{
      status: state.status,
      port_alive: state.port != nil,
      pending_requests: map_size(state.pending_requests),
      active_sessions: map_size(state.sessions),
      working_dir: state.working_dir
    }

    {:reply, {:ok, status_info}, state}
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    state = handle_port_line(line, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, {:noeol, _partial}}}, %{port: port} = state) do
    Logger.warning("Received partial line from port (buffer overflow)")
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) when is_binary(data) do
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
        {:noreply, state}

      {%{from: from, session_id: session_id}, pending} ->
        GenServer.reply(from, {:error, :timeout})

        # Mark session as failed
        state =
          case Map.get(state.sessions, session_id) do
            nil ->
              state

            session ->
              session = %{session | status: :failed, error: "Timeout"}
              put_in(state.sessions[session_id], session)
          end

        {:noreply, %{state | pending_requests: pending}}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    if status == 0 do
      Logger.debug("Codex SDK port exited normally")
    else
      Logger.warning("Codex SDK port exited with status: #{status}")
    end

    Enum.each(state.pending_requests, fn {_id, %{from: from, timer: timer}} ->
      if timer, do: Process.cancel_timer(timer)
      GenServer.reply(from, {:error, {:port_exited, status}})
    end)

    {:noreply, %{state | port: nil, status: :idle, pending_requests: %{}}}
  end

  @impl true
  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    Logger.warning("Codex SDK port crashed: #{inspect(reason)}")

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
        case Port.info(state.port) do
          nil ->
            :ok

          _info ->
            send_command(state.port, %{id: "shutdown", command: "shutdown"})
            Process.sleep(100)
            Port.close(state.port)
        end
      rescue
        ArgumentError -> :ok
      end
    end

    :ok
  end

  # Private Functions

  defp generate_session_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp get_bridge_path do
    priv_dir = :code.priv_dir(:hal) |> to_string()
    Path.join([priv_dir, "codex-sdk", "dist", "bridge.js"])
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

      node_path = System.find_executable("node")

      if node_path do
        port = Port.open({:spawn_executable, node_path}, [{:args, [bridge_path]} | port_opts])

        receive do
          {^port, {:data, {:eol, line}}} ->
            case Jason.decode(line) do
              {:ok, %{"id" => "init", "success" => true}} ->
                Logger.info("Codex SDK bridge ready")
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
    source_priv_dir = Path.join([File.cwd!(), "priv", "codex-sdk"])
    node_modules_path = Path.join(source_priv_dir, "node_modules")

    inherited_env =
      System.get_env()
      |> Enum.map(fn {key, value} ->
        {String.to_charlist(key), String.to_charlist(value)}
      end)

    override_env = [
      {~c"NODE_ENV", ~c"production"},
      {~c"NODE_PATH", String.to_charlist(node_modules_path)},
      {~c"TERM", ~c"xterm-256color"}
    ]

    inherited_env ++ override_env
  end

  defp ensure_port_started(%{status: status} = state)
       when status in [:not_started, :crashed, :idle] do
    case start_port(state) do
      {:ok, new_state} ->
        new_state

      {:error, reason} ->
        Logger.error("Failed to start Codex SDK port: #{inspect(reason)}")
        %{state | status: {:error, reason}}
    end
  end

  defp ensure_port_started(state), do: state

  defp next_request_id(state) do
    id = state.request_counter + 1
    request_id = "req-#{id}"
    {request_id, %{state | request_counter: id}}
  end

  defp send_command(port, command) do
    json = Jason.encode!(command)
    Port.command(port, json <> "\n")
  end

  defp maybe_update_thread_id(session, nil), do: session
  defp maybe_update_thread_id(session, ""), do: session

  defp maybe_update_thread_id(%{codex_thread_id: current} = session, thread_id)
       when is_binary(thread_id) do
    if current == thread_id do
      session
    else
      Map.put(session, :codex_thread_id, thread_id)
    end
  end

  defp maybe_update_thread_id(session, _), do: session

  defp handle_port_line(line, state) do
    case Jason.decode(line) do
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

  defp handle_response(request_id, response, state) do
    case Map.pop(state.pending_requests, request_id) do
      {nil, _state} ->
        if request_id != "init" and request_id != "system" do
          Logger.warning("Received response for unknown request: #{request_id}")
        end

        state

      {%{from: from, timer: timer, type: type} = request, remaining_requests} ->
        if timer, do: Process.cancel_timer(timer)
        session_id = Map.get(request, :session_id)

        {reply, state} =
          case {type, response} do
            {:start_session, %{"success" => true, "thread_id" => thread_id}} ->
              # Thread created.
              # By default we run the initial task synchronously (existing behavior), but callers
              # can opt out to make session creation fast (useful when invoked via MCP tools).
              initial_task = Map.get(request, :initial_task)
              session = Map.get(state.sessions, session_id)

              run_initial_task? =
                case session do
                  %{opts: opts} when is_list(opts) -> Keyword.get(opts, :run_initial_task, true)
                  _ -> true
                end

              session = %{session | codex_thread_id: thread_id}

              if run_initial_task? do
                session = %{session | status: :running}
                state = put_in(state.sessions[session_id], session)

                # Send the initial prompt
                {new_request_id, state} = next_request_id(state)

                command = %{
                  id: new_request_id,
                  command: "run",
                  thread_id: thread_id,
                  prompt: initial_task
                }

                send_command(state.port, command)

                # Queue up the follow-up request
                state =
                  put_in(state.pending_requests[new_request_id], %{
                    from: from,
                    timer: nil,
                    type: :initial_run,
                    session_id: session_id
                  })

                {:noreply, state}
              else
                session = %{session | status: :pending}
                state = put_in(state.sessions[session_id], session)
                {{:ok, session}, state}
              end

            {:initial_run, %{"success" => true, "result" => result} = response} ->
              session = Map.get(state.sessions, session_id)
              thread_id = Map.get(response, "thread_id")

              session =
                session
                |> maybe_update_thread_id(thread_id)
                |> Map.merge(%{
                  status: :completed,
                  completed_at: DateTime.utc_now(),
                  result: %{output: result}
                })

              state = put_in(state.sessions[session_id], session)
              {{:ok, session}, state}

            {:run, %{"success" => true, "result" => result} = response} ->
              session = Map.get(state.sessions, session_id)
              thread_id = Map.get(response, "thread_id")

              session =
                session
                |> maybe_update_thread_id(thread_id)
                |> Map.merge(%{
                  status: :completed,
                  result: %{output: result}
                })

              state = put_in(state.sessions[session_id], session)
              {{:ok, result}, state}

            {:resume_session, %{"success" => true}} ->
              session = Map.get(state.sessions, session_id)
              session = %{session | status: :running}
              state = put_in(state.sessions[session_id], session)
              {{:ok, session}, state}

            {_, %{"success" => false, "error" => error}} ->
              if session_id do
                session = Map.get(state.sessions, session_id)

                if session do
                  session = %{session | status: :failed, error: error}
                  state = put_in(state.sessions[session_id], session)
                  {{:error, error}, state}
                else
                  {{:error, error}, state}
                end
              else
                {{:error, error}, state}
              end

            {_, other} ->
              {{:error, {:unexpected_response, other}}, state}
          end

        case reply do
          :noreply ->
            # Already handled (queued follow-up request)
            %{state | pending_requests: remaining_requests}

          _ ->
            GenServer.reply(from, reply)
            %{state | pending_requests: remaining_requests}
        end
    end
  end
end
