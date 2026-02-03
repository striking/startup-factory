defmodule Hal.Gateway do
  @moduledoc """
  Main supervisor for the HAL Gateway subsystem.

  The Gateway manages all session-related processes including:
  - Registry for fast session lookups
  - DynamicSupervisor for spawning session GenServers
  - SessionManager for session lifecycle management
  - SessionCleaner for cleaning up archived sessions
  - Router for routing incoming messages to sessions

  ## Architecture

  ```
  Gateway (Supervisor)
  ├── Registry (HAL.SessionRegistry)
  ├── DynamicSupervisor (HAL.SessionSupervisor)
  ├── SessionManager (GenServer)
  ├── SessionCleaner (GenServer)
  └── Router (GenServer)
  ```

  ## Spawn-on-Demand Session Management

  HAL uses a spawn-on-demand pattern for session management, inspired by
  production systems like ChatGPT and Moltbot:

  ### Session Lifecycle

  1. **Spawn**: When first message arrives, SessionManager spawns SessionServer
     via DynamicSupervisor
  2. **Active**: Session loads message history from DB and processes messages
  3. **Inactivity**: After 30 minutes without messages, session auto-terminates
  4. **Termination**: Pending messages are flushed to DB before shutdown
  5. **Re-spawn**: Next message spawns a new session, loading previous history

  ### Benefits

  - **Memory Efficiency**: Memory usage scales with active users, not total users
  - **No Manual Cleanup**: Sessions auto-terminate when idle
  - **Fast Startup**: <100ms session spawn latency (acceptable for chat)
  - **State Preservation**: Full conversation history preserved in PostgreSQL
  - **Fault Tolerance**: Crashed sessions automatically recover on next message

  ### Configuration

  - Inactivity timeout: 30 minutes (configurable via @inactivity_timeout_ms)
  - Message flush interval: 5 minutes or every 10 messages
  - Max in-memory messages: 100 (older messages remain in DB)

  ## Usage

      # Typically started as part of the application supervision tree
      children = [
        Hal.Gateway
      ]

      # Or with custom names for testing
      Hal.Gateway.start_link(
        name: :my_gateway,
        registry_name: :my_registry,
        dynamic_supervisor_name: :my_supervisor,
        session_manager_name: :my_session_manager,
        session_cleaner_name: :my_session_cleaner,
        router_name: :my_router
      )
  """

  use Supervisor

  @default_registry_name Hal.SessionRegistry
  @default_supervisor_name Hal.SessionSupervisor
  @default_session_manager_name Hal.Gateway.SessionManager
  @default_router_name Hal.Gateway.Router
  @default_session_cleaner_name Hal.Gateway.SessionCleaner

  @type option ::
          {:name, atom()}
          | {:registry_name, atom()}
          | {:dynamic_supervisor_name, atom()}
          | {:session_manager_name, atom()}
          | {:router_name, atom()}
          | {:session_cleaner_name, atom()}

  @doc """
  Starts the Gateway supervisor.

  ## Options

    * `:name` - The name to register the supervisor under (default: `Hal.Gateway`)
    * `:registry_name` - Name for the session Registry (default: `Hal.SessionRegistry`)
    * `:dynamic_supervisor_name` - Name for the DynamicSupervisor (default: `Hal.SessionSupervisor`)
    * `:session_manager_name` - Name for the SessionManager (default: `Hal.Gateway.SessionManager`)
    * `:session_cleaner_name` - Name for the SessionCleaner (default: `Hal.Gateway.SessionCleaner`)
    * `:router_name` - Name for the Router (default: `Hal.Gateway.Router`)
  """
  @spec start_link([option()]) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    registry_name = Keyword.get(opts, :registry_name, @default_registry_name)
    supervisor_name = Keyword.get(opts, :dynamic_supervisor_name, @default_supervisor_name)
    session_manager_name = Keyword.get(opts, :session_manager_name, @default_session_manager_name)
    session_cleaner_name = Keyword.get(opts, :session_cleaner_name, @default_session_cleaner_name)
    router_name = Keyword.get(opts, :router_name, @default_router_name)

    children = [
      # Registry for fast session lookups by {channel_type, channel_id, user_id}
      {Registry, keys: :unique, name: registry_name},

      # DynamicSupervisor for spawning session GenServers
      {DynamicSupervisor, strategy: :one_for_one, name: supervisor_name},

      # SessionManager manages session lifecycle
      {Hal.Gateway.SessionManager,
       name: session_manager_name,
       registry_name: registry_name,
       dynamic_supervisor_name: supervisor_name},

      # SessionCleaner cleans up idle sessions periodically
      {Hal.Gateway.SessionCleaner, name: session_cleaner_name, registry_name: registry_name},

      # Router routes incoming messages to sessions
      {Hal.Gateway.Router, name: router_name, session_manager_name: session_manager_name}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Returns the default names used by the Gateway.
  Useful for looking up processes started with default configuration.
  """
  @spec default_names() :: map()
  def default_names do
    %{
      registry: @default_registry_name,
      supervisor: @default_supervisor_name,
      session_manager: @default_session_manager_name,
      session_cleaner: @default_session_cleaner_name,
      router: @default_router_name
    }
  end
end
