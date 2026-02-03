defmodule HAL.AgentRegistry do
  @moduledoc """
  A presence-aware registry for tracking agents in the HAL system.

  The AgentRegistry provides:
  - Agent registration with metadata (role, capabilities, status)
  - Automatic cleanup when agent processes crash/terminate
  - PubSub-based presence notifications (join/leave)
  - Direct agent-to-agent messaging

  ## Architecture

  Each agent is identified by a unique `agent_id` (string). When an agent joins,
  it can optionally provide a `pid` for process monitoring - if that process dies,
  the agent is automatically unregistered.

  ## PubSub Topics

  - `"agent:registry"` - Presence events (join/leave broadcasts)
  - `"agent:<agent_id>"` - Direct messages to specific agents

  ## Usage

      # Register an agent (from the agent's process)
      HAL.AgentRegistry.join("researcher", %{role: "research", status: "available"})

      # List all registered agents
      HAL.AgentRegistry.list_agents()
      #=> [%{agent_id: "researcher", metadata: %{role: "research"}, ...}]

      # Send a message from one agent to another
      HAL.AgentRegistry.send_to_agent("researcher", "planner", "Found 3 relevant docs")

      # Subscribe to presence changes in a LiveView
      HAL.AgentRegistry.subscribe()
      # Receives: {:agent_joined, info}, {:agent_left, id, reason}

      # Leave the registry
      HAL.AgentRegistry.leave("researcher")

  ## Integration with HAL Systems

  The AgentRegistry complements (not replaces) existing HAL systems:
  - **HAL.AgentState** - Persistent state across restarts (JSONL + ETS)
  - **AgentRegistry** - Runtime presence tracking (who's online right now)
  - **HAL.Gateway.SessionManager** - User session lifecycle

  Future use cases:
  - Multi-agent workflows with specialized sub-agents
  - Agent capability matching for task routing
  - Distributed agent coordination
  """

  use GenServer
  require Logger

  @pubsub Hal.PubSub
  @registry_topic "agent:registry"

  # Agent info stored in state
  @type agent_info :: %{
          agent_id: String.t(),
          metadata: map(),
          pid: pid() | nil,
          monitor_ref: reference() | nil,
          joined_at: DateTime.t()
        }

  @type state :: %{
          agents: %{String.t() => agent_info()},
          monitors: %{reference() => String.t()}
        }

  # ============================================
  # Client API
  # ============================================

  @doc """
  Starts the AgentRegistry.

  Typically started as part of the supervision tree in application.ex.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers an agent with the registry.

  ## Options

  - `:pid` - Optional PID to monitor. If provided, the agent will be
    automatically unregistered when this process terminates.
    Defaults to `self()` if called from a process.

  ## Examples

      # Register with current process monitoring
      HAL.AgentRegistry.join("my-agent", %{role: "worker"})

      # Register without process monitoring (manual cleanup required)
      HAL.AgentRegistry.join("external-agent", %{role: "external"}, pid: nil)

      # Register with specific process monitoring
      HAL.AgentRegistry.join("worker-1", %{role: "worker"}, pid: worker_pid)
  """
  @spec join(String.t(), map(), keyword()) :: :ok | {:error, :already_registered}
  def join(agent_id, metadata \\ %{}, opts \\ []) do
    pid = Keyword.get(opts, :pid, self())
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:join, agent_id, metadata, pid})
  end

  @doc """
  Unregisters an agent from the registry.

  Returns `:ok` even if the agent wasn't registered.
  """
  @spec leave(String.t(), keyword()) :: :ok
  def leave(agent_id, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:leave, agent_id})
  end

  @doc """
  Lists all currently registered agents.

  Returns a list of agent info maps.
  """
  @spec list_agents(keyword()) :: [agent_info()]
  def list_agents(opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, :list_agents)
  end

  @doc """
  Gets info for a specific agent by ID.

  Returns `nil` if the agent is not registered.
  """
  @spec get_agent(String.t(), keyword()) :: agent_info() | nil
  def get_agent(agent_id, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:get_agent, agent_id})
  end

  @doc """
  Sends a message from one agent to another.

  Uses PubSub to deliver the message to the target agent's topic.
  The target agent must be subscribed to their topic to receive messages.

  ## Returns

  - `:ok` - Message was broadcast (doesn't guarantee delivery)
  - `{:error, :not_found}` - Target agent is not registered

  ## Examples

      HAL.AgentRegistry.send_to_agent("planner", "researcher", {:request, "find docs on X"})
  """
  @spec send_to_agent(String.t(), String.t(), term(), keyword()) :: :ok | {:error, :not_found}
  def send_to_agent(from_id, to_id, message, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:send_to_agent, from_id, to_id, message})
  end

  @doc """
  Subscribes the current process to registry presence events.

  After subscribing, the process will receive:
  - `{:agent_joined, agent_info}` - When an agent joins
  - `{:agent_left, agent_id, reason}` - When an agent leaves

  ## Examples

      # In a LiveView
      def mount(_params, _session, socket) do
        if connected?(socket), do: HAL.AgentRegistry.subscribe()
        {:ok, socket}
      end

      def handle_info({:agent_joined, info}, socket) do
        # Handle new agent
        {:noreply, socket}
      end
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @registry_topic)
  end

  @doc """
  Unsubscribes the current process from registry presence events.
  """
  @spec unsubscribe() :: :ok
  def unsubscribe do
    Phoenix.PubSub.unsubscribe(@pubsub, @registry_topic)
  end

  @doc """
  Subscribes to direct messages for a specific agent.

  The subscribing process will receive messages sent via `send_to_agent/4`
  in the format: `{:agent_message, from_id, message}`

  ## Examples

      HAL.AgentRegistry.subscribe_agent("my-agent")
      # Later receives: {:agent_message, "planner", {:task, "do something"}}
  """
  @spec subscribe_agent(String.t()) :: :ok | {:error, term()}
  def subscribe_agent(agent_id) do
    Phoenix.PubSub.subscribe(@pubsub, agent_topic(agent_id))
  end

  @doc """
  Unsubscribes from direct messages for a specific agent.
  """
  @spec unsubscribe_agent(String.t()) :: :ok
  def unsubscribe_agent(agent_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, agent_topic(agent_id))
  end

  @doc """
  Updates metadata for a registered agent.

  ## Examples

      HAL.AgentRegistry.update_metadata("researcher", %{status: "busy"})
  """
  @spec update_metadata(String.t(), map(), keyword()) :: :ok | {:error, :not_found}
  def update_metadata(agent_id, metadata_updates, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:update_metadata, agent_id, metadata_updates})
  end

  # ============================================
  # Server Callbacks
  # ============================================

  @impl true
  def init(_opts) do
    state = %{
      agents: %{},
      monitors: %{}
    }

    Logger.info("[AgentRegistry] Started")
    {:ok, state}
  end

  @impl true
  def handle_call({:join, agent_id, metadata, pid}, _from, state) do
    if Map.has_key?(state.agents, agent_id) do
      {:reply, {:error, :already_registered}, state}
    else
      # Set up process monitoring if pid provided
      {monitor_ref, monitors} =
        if pid do
          ref = Process.monitor(pid)
          {ref, Map.put(state.monitors, ref, agent_id)}
        else
          {nil, state.monitors}
        end

      agent_info = %{
        agent_id: agent_id,
        metadata: metadata,
        pid: pid,
        monitor_ref: monitor_ref,
        joined_at: DateTime.utc_now()
      }

      new_agents = Map.put(state.agents, agent_id, agent_info)
      new_state = %{state | agents: new_agents, monitors: monitors}

      # Broadcast join event
      broadcast_presence({:agent_joined, agent_info})
      Logger.info("[AgentRegistry] Agent joined: #{agent_id}")

      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:leave, agent_id}, _from, state) do
    {new_state, _} = do_leave(state, agent_id, :voluntary)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:list_agents, _from, state) do
    agents =
      state.agents
      |> Map.values()
      |> Enum.sort_by(& &1.joined_at, DateTime)

    {:reply, agents, state}
  end

  @impl true
  def handle_call({:get_agent, agent_id}, _from, state) do
    {:reply, Map.get(state.agents, agent_id), state}
  end

  @impl true
  def handle_call({:send_to_agent, from_id, to_id, message}, _from, state) do
    if Map.has_key?(state.agents, to_id) do
      Phoenix.PubSub.broadcast(@pubsub, agent_topic(to_id), {:agent_message, from_id, message})
      {:reply, :ok, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:update_metadata, agent_id, metadata_updates}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      agent_info ->
        updated_info = %{agent_info | metadata: Map.merge(agent_info.metadata, metadata_updates)}
        new_agents = Map.put(state.agents, agent_id, updated_info)
        {:reply, :ok, %{state | agents: new_agents}}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.get(state.monitors, ref) do
      nil ->
        {:noreply, state}

      agent_id ->
        Logger.info("[AgentRegistry] Agent process down: #{agent_id} (#{inspect(reason)})")
        {new_state, _} = do_leave(state, agent_id, {:process_down, reason})
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("[AgentRegistry] Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ============================================
  # Private Functions
  # ============================================

  defp do_leave(state, agent_id, reason) do
    case Map.pop(state.agents, agent_id) do
      {nil, _} ->
        {state, nil}

      {agent_info, remaining_agents} ->
        monitors = cleanup_monitor(state.monitors, agent_info.monitor_ref)
        new_state = %{state | agents: remaining_agents, monitors: monitors}

        # Broadcast leave event
        broadcast_presence({:agent_left, agent_id, reason})
        Logger.info("[AgentRegistry] Agent left: #{agent_id} (#{inspect(reason)})")

        {new_state, agent_info}
    end
  end

  # Monitor cleanup helper - uses pattern matching for clarity
  defp cleanup_monitor(monitors, nil), do: monitors

  defp cleanup_monitor(monitors, ref) do
    Process.demonitor(ref, [:flush])
    Map.delete(monitors, ref)
  end

  defp broadcast_presence(event) do
    Phoenix.PubSub.broadcast(@pubsub, @registry_topic, event)
  end

  defp agent_topic(agent_id), do: "agent:#{agent_id}"
end
