defmodule Hal.Gateway.SessionServer do
  @moduledoc """
  GenServer representing an individual conversation session.

  Each SessionServer holds the state for a single conversation, including:
  - Session metadata (channel_type, channel_id, user_id)
  - Claude Code session ID for continuity
  - In-memory message history (last 100 messages)
  - Pending messages to be flushed to database
  - Last activity timestamp for inactivity tracking

  ## Session Lifecycle (Spawn-on-Demand)

  Sessions are spawned on-demand when the first message arrives:
  - SessionManager creates SessionServer via DynamicSupervisor
  - SessionServer loads message history from database on init
  - Session remains active as long as messages are being sent
  - After 30 minutes of inactivity, session auto-terminates
  - On termination, pending messages are flushed to database
  - Next message will spawn a new session (loading previous history)

  ## Message Flow

  1. User sends message via `handle_message/2`
  2. Last activity timestamp is updated
  3. Message is added to in-memory history
  4. Message is sent to Claude Code via `send_to_claude/3`
  5. Response is added to in-memory history
  6. Messages are periodically flushed to database

  ## Persistence

  Messages are persisted to the database:
  - After every 10 new messages
  - Every 5 minutes (periodic flush)
  - On explicit `flush_to_db/1` call
  - Before session termination (inactivity or shutdown)

  ## Inactivity Timeout

  Sessions auto-terminate after 30 minutes of inactivity to conserve memory.
  The inactivity timer resets on every message. This ensures:
  - Memory usage scales with active users, not total users
  - No manual session cleanup needed
  - Conversation history is preserved in database

  ## Usage

      # Typically created via SessionManager, not directly
      {:ok, pid} = SessionServer.start_link(
        session_id: "uuid",
        channel_type: "telegram",
        channel_id: "chat_123",
        user_id: "user_uuid",
        registry_name: Hal.SessionRegistry
      )

      # Handle incoming message
      {:ok, response} = SessionServer.handle_message(pid, "Hello!")

      # Get session state
      state = SessionServer.get_state(pid)
  """

  use GenServer
  require Logger

  alias Hal.Gateway.Message, as: MessageSchema
  alias Hal.Gateway.Session, as: SessionSchema
  alias HAL.Memory
  alias HAL.Turns.Runner, as: TurnRunner
  alias Hal.Repo

  import Ecto.Query

  @max_messages_in_memory 100
  # 5 minutes
  @flush_interval_ms 5 * 60 * 1000
  # Flush after this many new messages
  @flush_threshold 10
  # 30 minutes inactivity → idle state
  @idle_timeout_ms 30 * 60 * 1000
  # 2 hours in idle → terminate (configurable via SessionManager LRU)
  @archive_timeout_ms 2 * 60 * 60 * 1000
  # Session states:
  # - :active - Normal operation with full message history
  # - :idle - Minimal state, messages cleared, fast to reactivate
  @type session_state :: :active | :idle

  defstruct [
    :session_id,
    :channel_type,
    :channel_id,
    :user_id,
    :claude_session_id,
    :registry_name,
    :last_activity,
    # Session state for LRU caching
    state: :active,
    messages: [],
    pending_messages: [],
    loaded_memories: [],
    settings: %{},
    metadata: %{}
  ]

  # Client API

  @doc """
  Starts a SessionServer.

  ## Options

    * `:session_id` - The database session ID (required)
    * `:channel_type` - The channel type (required)
    * `:channel_id` - The channel ID (required)
    * `:user_id` - The user ID (required)
    * `:claude_session_id` - Existing Claude session ID for continuity (optional)
    * `:registry_name` - Name of the Registry for lookups (required)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Handles an incoming user message.

  Sends the message to Claude Code and returns the response.

  ## Options

    * `:ai_client` - Function for sending to AI (for testing)

  ## Returns

    * `{:ok, response}` - Success with the AI response text
    * `{:error, reason}` - Error with reason
  """
  @spec handle_message(pid(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def handle_message(pid, content, opts \\ []) do
    GenServer.call(pid, {:handle_message, content, opts}, 120_000)
  end

  @doc """
  Sends a message directly to Claude Code.

  Unlike `handle_message/2`, this doesn't add the message to history.
  Useful for system messages or commands.

  ## Returns

    * `{:ok, response, session_id}` - Success with response and Claude session ID
    * `{:error, reason}` - Error with reason
  """
  @spec send_to_claude(pid(), String.t(), keyword()) ::
          {:ok, map(), String.t() | nil} | {:error, term()}
  def send_to_claude(pid, content, opts \\ []) do
    GenServer.call(pid, {:send_to_claude, content, opts}, 120_000)
  end

  @doc """
  Gets the current session state.

  Returns a map with session metadata and message history.
  """
  @spec get_state(pid()) :: map()
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Returns whether the session is in idle state (minimal memory footprint).
  """
  @spec is_idle?(pid()) :: boolean()
  def is_idle?(pid) do
    GenServer.call(pid, :is_idle?)
  end

  @doc """
  Manually transitions session to idle state.
  Useful for memory pressure situations.
  """
  @spec go_idle(pid()) :: :ok
  def go_idle(pid) do
    GenServer.cast(pid, :go_idle)
  end

  @doc """
  Forces a flush of pending messages to the database.
  """
  @spec flush_to_db(pid()) :: :ok
  def flush_to_db(pid) do
    GenServer.call(pid, :flush_to_db)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    channel_type = Keyword.fetch!(opts, :channel_type)
    channel_id = Keyword.fetch!(opts, :channel_id)
    user_id = Keyword.fetch!(opts, :user_id)
    claude_session_id = Keyword.get(opts, :claude_session_id)
    registry_name = Keyword.fetch!(opts, :registry_name)

    # Register in Registry
    key = {channel_type, channel_id, user_id}
    {:ok, _} = Registry.register(registry_name, key, %{session_id: session_id})

    # Load existing messages from database
    messages = load_messages_from_db(session_id)

    # Memory context injection is handled centrally by the TurnRunner/AI Router.
    # Keep this field for future per-session caching, but don't preload here.
    memories = []

    state = %__MODULE__{
      session_id: session_id,
      channel_type: channel_type,
      channel_id: channel_id,
      user_id: user_id,
      claude_session_id: claude_session_id,
      registry_name: registry_name,
      last_activity: DateTime.utc_now(),
      messages: messages,
      pending_messages: [],
      loaded_memories: memories
    }

    # Schedule periodic flush
    schedule_flush()

    # Schedule inactivity check
    schedule_inactivity_check()

    Logger.debug("SessionServer started for #{channel_type}:#{channel_id}")

    {:ok, state}
  end

  @impl true
  def handle_call({:handle_message, content, opts}, _from, state) do
    ai_client = Keyword.get(opts, :ai_client)

    # Reactivate from idle if necessary
    state = if state.state == :idle, do: reactivate_from_idle(state), else: state

    # Update last activity
    now = DateTime.utc_now()
    state = %{state | last_activity: now}

    # Add user message
    user_message = %{
      role: "user",
      content: content,
      inserted_at: DateTime.truncate(now, :second)
    }

    state = add_message(state, user_message)

    # Include conversation history for context (last N messages, excluding the one we just added)
    conversation_history = get_recent_messages_for_context(state.messages)

    turn_opts =
      opts
      |> Keyword.delete(:ai_client)
      |> Keyword.put(:user_id, state.user_id)
      |> Keyword.put(:channel_type, state.channel_type)
      |> Keyword.put(:channel_id, state.channel_id)
      |> Keyword.put(:hal_session_id, state.session_id)
      |> Keyword.put(:session_id, state.claude_session_id)
      |> Keyword.put(:conversation_history, conversation_history)
      |> maybe_put_ai_client(ai_client)

    case TurnRunner.run(content, turn_opts) do
      {:ok, %{text: response_text, provider_session_id: new_session_id}} ->
        # Add assistant message
        assistant_message = %{
          role: "assistant",
          content: response_text,
          inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }

        state = add_message(state, assistant_message)
        state = %{state | claude_session_id: new_session_id || state.claude_session_id}

        # Extract and store learnings from the conversation
        state = extract_and_store_learnings(state, content, response_text)

        # Update session in DB with new claude_session_id and last_activity
        update_session_activity(state)

        # Maybe flush to DB
        state = maybe_flush_to_db(state)

        # Log conversation to daily memory (async, non-blocking)
        log_to_daily_memory(content, response_text)

        {:reply, {:ok, response_text}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:send_to_claude, content, opts}, _from, state) do
    ai_client = Keyword.get(opts, :ai_client)

    turn_opts =
      opts
      |> Keyword.delete(:ai_client)
      |> Keyword.put(:user_id, state.user_id)
      |> Keyword.put(:channel_type, state.channel_type)
      |> Keyword.put(:channel_id, state.channel_id)
      |> Keyword.put(:hal_session_id, state.session_id)
      |> Keyword.put(:session_id, state.claude_session_id)
      |> Keyword.put(:enable_routing, false)
      |> Keyword.put(:default_provider, :claude_code)
      |> maybe_put_ai_client(ai_client)

    case TurnRunner.run(content, turn_opts) do
      {:ok, %{raw: response, provider_session_id: new_session_id}} ->
        state = %{state | claude_session_id: new_session_id || state.claude_session_id}
        {:reply, {:ok, response, new_session_id}, state}

      {:ok, %{text: response, provider_session_id: new_session_id}} ->
        state = %{state | claude_session_id: new_session_id || state.claude_session_id}
        {:reply, {:ok, response, new_session_id}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    result = %{
      session_id: state.session_id,
      channel_type: state.channel_type,
      channel_id: state.channel_id,
      user_id: state.user_id,
      claude_session_id: state.claude_session_id,
      last_activity: state.last_activity,
      state: state.state,
      messages: state.messages,
      loaded_memories: state.loaded_memories,
      settings: state.settings,
      metadata: state.metadata
    }

    {:reply, result, state}
  end

  @impl true
  def handle_call(:is_idle?, _from, state) do
    {:reply, state.state == :idle, state}
  end

  @impl true
  def handle_call(:flush_to_db, _from, state) do
    state = do_flush_to_db(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast(:go_idle, state) do
    if state.state == :active do
      new_state = transition_to_idle(state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:periodic_flush, state) do
    state = do_flush_to_db(state)
    schedule_flush()
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_inactivity, state) do
    now = DateTime.utc_now()
    inactivity_ms = DateTime.diff(now, state.last_activity, :millisecond)

    cond do
      # Already idle and past archive timeout → terminate
      state.state == :idle and inactivity_ms >= @archive_timeout_ms ->
        Logger.info(
          "Session #{state.session_id} (#{state.channel_type}:#{state.channel_id}) " <>
            "idle for #{div(inactivity_ms, 60_000)} minutes, archiving"
        )

        {:stop, :normal, state}

      # Active and past idle timeout → transition to idle
      state.state == :active and inactivity_ms >= @idle_timeout_ms ->
        Logger.info(
          "Session #{state.session_id} (#{state.channel_type}:#{state.channel_id}) " <>
            "inactive for #{div(inactivity_ms, 60_000)} minutes, transitioning to idle"
        )

        new_state = transition_to_idle(state)
        schedule_inactivity_check()
        {:noreply, new_state}

      # Not yet time to transition, reschedule check
      true ->
        schedule_inactivity_check()
        {:noreply, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug(
      "SessionServer terminating for session #{state.session_id}, reason: #{inspect(reason)}"
    )

    # Flush pending messages before terminating
    do_flush_to_db(state)

    # Update session status in DB
    # If terminated due to inactivity, mark as inactive
    # Otherwise preserve the current status
    if reason == :normal do
      # Update last_activity timestamp one final time
      update_session_activity(state)
    end

    :ok
  end

  # Private Functions

  defp load_messages_from_db(session_id) do
    query =
      from m in MessageSchema,
        where: m.session_id == ^session_id,
        order_by: [desc: m.inserted_at],
        limit: @max_messages_in_memory

    messages =
      Repo.all(query)
      |> Enum.reverse()
      |> Enum.map(fn msg ->
        %{
          id: msg.id,
          role: msg.role,
          content: msg.content,
          attachments: msg.attachments,
          metadata: msg.metadata,
          inserted_at: msg.inserted_at
        }
      end)

    Logger.debug("Loaded #{length(messages)} messages from database")
    messages
  end

  defp add_message(state, message) do
    messages = state.messages ++ [message]

    # Trim to max messages
    messages =
      if length(messages) > @max_messages_in_memory do
        Enum.drop(messages, length(messages) - @max_messages_in_memory)
      else
        messages
      end

    pending = state.pending_messages ++ [message]

    %{state | messages: messages, pending_messages: pending}
  end

  # Get recent messages for conversation context (excluding the latest user message we just added)
  # Limit to last 20 messages to avoid huge prompts
  @context_message_limit 20
  defp get_recent_messages_for_context(messages) do
    messages
    # +1 because we'll drop the last one
    |> Enum.take(-(@context_message_limit + 1))
    # Drop the message we just added (it's sent separately)
    |> Enum.drop(-1)
    |> Enum.map(fn msg ->
      %{role: msg.role, content: msg.content}
    end)
  end

  defp maybe_flush_to_db(state) do
    if length(state.pending_messages) >= @flush_threshold do
      do_flush_to_db(state)
    else
      state
    end
  end

  defp do_flush_to_db(%{pending_messages: []} = state), do: state

  defp do_flush_to_db(state) do
    Logger.debug("Flushing #{length(state.pending_messages)} messages to database")

    for message <- state.pending_messages do
      # Skip if already has an ID (already in DB)
      unless Map.has_key?(message, :id) do
        %MessageSchema{}
        |> MessageSchema.changeset(%{
          session_id: state.session_id,
          role: message.role,
          content: message.content,
          attachments: Map.get(message, :attachments, []),
          metadata: Map.get(message, :metadata, %{})
        })
        |> Repo.insert()
      end
    end

    %{state | pending_messages: []}
  end

  defp update_session_activity(state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    SessionSchema
    |> Repo.get(state.session_id)
    |> case do
      nil ->
        Logger.warning("Session #{state.session_id} not found in database")

      session ->
        session
        |> SessionSchema.activity_changeset(%{
          last_activity: now,
          claude_session_id: state.claude_session_id
        })
        |> Repo.update()
    end
  end

  defp schedule_flush do
    Process.send_after(self(), :periodic_flush, @flush_interval_ms)
  end

  defp schedule_inactivity_check do
    # Check every 5 minutes to see if we've hit the idle timeout
    check_interval = min(@idle_timeout_ms, 5 * 60 * 1000)
    Process.send_after(self(), :check_inactivity, check_interval)
  end

  # Session state transitions for LRU caching

  defp transition_to_idle(state) do
    # Flush pending messages before going idle
    state = do_flush_to_db(state)

    # Clear heavy data but keep essential metadata for fast reactivation
    %{state | state: :idle, messages: [], pending_messages: [], loaded_memories: []}
  end

  defp reactivate_from_idle(state) do
    # Reload messages from database
    messages = load_messages_from_db(state.session_id)
    memories = []

    Logger.debug("Reactivated session #{state.session_id} from idle state")

    %{
      state
      | state: :active,
        messages: messages,
        loaded_memories: memories,
        last_activity: DateTime.utc_now()
    }
  end

  defp maybe_put_ai_client(opts, fun) when is_function(fun, 3),
    do: Keyword.put(opts, :ai_client, fun)

  defp maybe_put_ai_client(opts, _), do: opts

  defp extract_and_store_learnings(state, user_message, assistant_response) do
    # Asynchronously extract and store learnings to avoid blocking the response
    Task.start(fn ->
      extract_learnings_async(state.user_id, user_message, assistant_response, %{
        session_id: state.session_id,
        channel_type: state.channel_type,
        channel_id: state.channel_id
      })
    end)

    state
  end

  defp extract_learnings_async(_user_id, user_message, assistant_response, metadata) do
    # Use simple pattern matching to extract learnings
    # This is a basic implementation - could be enhanced with AI-based extraction

    learnings = []

    # Pattern 1: "I prefer/like X"
    learnings =
      learnings ++
        extract_preferences(user_message) ++
        extract_preferences(assistant_response)

    # Pattern 2: "My name is X" or "I am X"
    learnings = learnings ++ extract_facts(user_message)

    # Pattern 3: "We decided to X" or "Let's use X"
    learnings = learnings ++ extract_decisions(user_message)

    # Store each learning as a memory using the new API
    Enum.each(learnings, fn {content, type} ->
      try do
        # Map the type atom to a valid source string
        source = type_to_source(type)
        memory_metadata = Map.merge(metadata, %{learning_type: type})

        case Memory.store(content, source, metadata: memory_metadata) do
          {:ok, _memory} ->
            Logger.debug("Stored learning: #{content}")

          {:error, reason} ->
            Logger.warning("Failed to store learning: #{inspect(reason)}")
        end
      rescue
        e ->
          Logger.warning("Error storing learning: #{Exception.message(e)}")
      end
    end)
  end

  # Map learning types to valid memory sources
  defp type_to_source(:preference), do: "user_input"
  defp type_to_source(:fact), do: "user_input"
  defp type_to_source(:decision), do: "conversation"
  defp type_to_source(:knowledge), do: "document"
  defp type_to_source(_), do: "observation"

  defp extract_preferences(text) do
    text_lower = String.downcase(text)

    cond do
      String.match?(text_lower, ~r/\b(i prefer|i like|i love|i enjoy)\b/) ->
        [{text, :preference}]

      true ->
        []
    end
  end

  defp extract_facts(text) do
    text_lower = String.downcase(text)

    cond do
      String.match?(text_lower, ~r/\b(my name is|i am|i work at|i live in)\b/) ->
        [{text, :fact}]

      true ->
        []
    end
  end

  defp extract_decisions(text) do
    text_lower = String.downcase(text)

    cond do
      String.match?(
        text_lower,
        ~r/\b(we decided|let's use|we'll use|we chose|we're using)\b/
      ) ->
        [{text, :decision}]

      true ->
        []
    end
  end

  # Log conversations to daily memory file
  defp log_to_daily_memory(user_message, assistant_response) do
    # Run async to avoid blocking response
    Task.start(fn ->
      try do
        # Truncate long messages for the log
        user_summary = truncate_for_log(user_message, 200)
        assistant_summary = truncate_for_log(assistant_response, 300)

        entry = """
        **Chat:**
        User: #{user_summary}
        HAL: #{assistant_summary}
        """

        HAL.Autonomy.SelfModification.append_to_daily_log(entry)
      rescue
        e ->
          Logger.warning("Failed to log chat to daily memory: #{inspect(e)}")
      end
    end)
  end

  defp truncate_for_log(text, max_length) do
    text = String.replace(text, ~r/\n+/, " ")

    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end
end
