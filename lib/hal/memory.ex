defmodule HAL.Memory do
  @moduledoc """
  Main facade for HAL's semantic memory system.

  This module provides a high-level API for storing, recalling, and managing
  memories with vector embeddings. It integrates:

  - `HAL.Memory.Embedding` - Google Vertex AI embeddings
  - `Hal.Memory.Store` - Ecto-backed storage with pgvector
  - `HAL.Memory.Search` - Semantic similarity search
  - `HAL.Memory.Truncation` - Smart content truncation

  ## Configuration

  Configure in `config/runtime.exs`:

      config :hal, HAL.Memory,
        enabled: true,
        auto_store_conversations: true,
        max_context_chars: 8000,
        relevance_threshold: 0.7

  ## Usage

      # Store a new memory with automatic embedding
      {:ok, memory} = HAL.Memory.store("User prefers dark mode", "user_input")

      # Recall relevant memories
      {:ok, results} = HAL.Memory.recall("What are the user's preferences?")

      # Get formatted context for prompt injection
      context = HAL.Memory.get_context("user preferences", max_chars: 4000)

      # Delete a memory
      {:ok, _} = HAL.Memory.forget(memory_id)

  ## Sources

  Valid memory sources (from `Hal.Memory.Store`):
  - `"user_input"` - Messages from the user
  - `"agent_output"` - HAL's responses
  - `"conversation"` - Full conversation exchanges
  - `"document"` - Imported documents
  - `"observation"` - Agent observations and learnings
  - `"system"` - System-generated memories

  ## Markdown-based Memory (Legacy)

  For simple markdown-based memory without vector search, the legacy
  `Hal.Memory` API is still available but deprecated. The new vector-based
  system in this module is recommended for semantic search capabilities.
  """

  require Logger

  alias Hal.Memory.Store
  alias HAL.Memory.Embedding
  alias HAL.Memory.Search
  alias HAL.Memory.Truncation

  # Type definitions

  @type memory_id :: String.t()
  @type source :: String.t()

  @type store_opts :: [
          metadata: map(),
          skip_embedding: boolean()
        ]

  @type recall_opts :: [
          limit: pos_integer(),
          threshold: float(),
          source: String.t() | nil,
          metadata: map() | nil
        ]

  @type context_opts :: [
          max_chars: pos_integer() | nil,
          format: :text | :structured,
          limit: pos_integer(),
          threshold: float(),
          source: String.t() | nil
        ]

  # Default configuration values
  @default_enabled true
  @default_auto_store false
  @default_max_context_chars 8000
  @default_relevance_threshold 0.7
  @default_recall_limit 5

  # Public API

  @doc """
  Store a new memory with automatic embedding generation.

  Creates a memory in the database with a vector embedding for semantic search.
  The embedding is generated using Google's Vertex AI embeddings API.

  ## Parameters

    - `content` - The text content to store
    - `source` - Memory source type (see module docs for valid values)
    - `opts` - Optional keyword list:
      - `:metadata` - Map of additional metadata to store
      - `:skip_embedding` - If true, store without embedding (default: false)

  ## Returns

    - `{:ok, memory}` on success
    - `{:error, reason}` on failure

  ## Examples

      # Basic storage
      {:ok, memory} = HAL.Memory.store("User prefers dark mode", "user_input")

      # With metadata
      {:ok, memory} = HAL.Memory.store(
        "Discussed project timeline",
        "conversation",
        metadata: %{session_id: "abc123", importance: "high"}
      )

      # Store without embedding (faster, but no semantic search)
      {:ok, memory} = HAL.Memory.store(
        "Quick note",
        "observation",
        skip_embedding: true
      )
  """
  @spec store(String.t(), source(), store_opts()) :: {:ok, Store.t()} | {:error, term()}
  def store(content, source, opts \\ []) when is_binary(content) and is_binary(source) do
    with :ok <- check_enabled(),
         {:ok, embedding} <- maybe_generate_embedding(content, opts) do
      metadata = Keyword.get(opts, :metadata, %{})
      Store.create_memory(content, embedding, source: source, metadata: metadata)
    end
  end

  @doc """
  Search for relevant memories using semantic similarity.

  ## Parameters

    - `query` - The search query text
    - `opts` - Optional keyword list:
      - `:limit` - Maximum results (default: #{@default_recall_limit})
      - `:threshold` - Minimum similarity 0.0-1.0 (default: from config)
      - `:source` - Filter by memory source
      - `:metadata` - Filter by metadata fields

  ## Returns

    - `{:ok, results}` - List of `%{memory: memory, similarity: float}`
    - `{:error, reason}` on failure

  ## Examples

      {:ok, results} = HAL.Memory.recall("user preferences")

      {:ok, results} = HAL.Memory.recall("dark mode",
        limit: 3,
        threshold: 0.6,
        source: "user_input"
      )
  """
  @spec recall(String.t(), recall_opts()) :: {:ok, [Search.search_result()]} | {:error, term()}
  def recall(query, opts \\ []) when is_binary(query) do
    if not enabled?() do
      {:ok, []}
    else
      opts =
        opts
        |> Keyword.put_new(:limit, @default_recall_limit)
        |> Keyword.put_new(
          :threshold,
          get_config(:relevance_threshold, @default_relevance_threshold)
        )

      Search.search(query, opts)
    end
  end

  @doc """
  Get formatted context from relevant memories for prompt injection.

  This is the main function for integrating memories into AI prompts.
  It searches for relevant memories and formats them appropriately,
  with optional truncation to fit token budgets.

  ## Parameters

    - `query` - The search query (usually the current message/prompt)
    - `opts` - Optional keyword list:
      - `:max_chars` - Maximum characters in output (default: from config)
      - `:format` - Output format, `:text` or `:structured` (default: :text)
      - `:limit` - Maximum memories to include (default: #{@default_recall_limit})
      - `:threshold` - Minimum similarity (default: from config)
      - `:source` - Filter by source type

  ## Returns

    - Formatted string with relevant memories (or empty string if none found)

  ## Formats

  ### :text (default)
      Relevant context from memory:
      - [0.95] User prefers dark mode
      - [0.87] User works late at night

  ### :structured
      <relevant_memories>
        <memory similarity="0.95" source="user_input">
          User prefers dark mode
        </memory>
      </relevant_memories>

  ## Examples

      # Basic context retrieval
      context = HAL.Memory.get_context("user preferences")

      # With truncation for smaller context windows
      context = HAL.Memory.get_context("settings",
        max_chars: 2000,
        format: :text
      )
  """
  @spec get_context(String.t(), context_opts()) :: String.t()
  def get_context(query, opts \\ []) when is_binary(query) do
    if not enabled?() do
      ""
    else
      # Apply config defaults
      opts =
        opts
        |> Keyword.put_new(:max_chars, get_config(:max_context_chars, @default_max_context_chars))
        |> Keyword.put_new(
          :threshold,
          get_config(:relevance_threshold, @default_relevance_threshold)
        )
        |> Keyword.put_new(:limit, @default_recall_limit)

      Search.get_relevant_context(query, opts)
    end
  end

  @doc """
  Delete a memory by its ID.

  ## Parameters

    - `memory_id` - The UUID of the memory to delete

  ## Returns

    - `{:ok, memory}` - The deleted memory
    - `{:error, :not_found}` - Memory doesn't exist
    - `{:error, reason}` - Other failure

  ## Examples

      {:ok, _deleted} = HAL.Memory.forget("550e8400-e29b-41d4-a716-446655440000")
  """
  @spec forget(memory_id()) :: {:ok, Store.t()} | {:error, :not_found | term()}
  def forget(memory_id) when is_binary(memory_id) do
    Store.delete_memory(memory_id)
  end

  @doc """
  Store a conversation exchange (user message + AI response).

  Convenience function for storing both sides of a conversation.
  Only stores if `auto_store_conversations` is enabled in config.

  ## Parameters

    - `user_message` - The user's input message
    - `ai_response` - HAL's response
    - `opts` - Optional keyword list:
      - `:session_id` - Session identifier for metadata
      - `:force` - Store even if auto_store disabled (default: false)
      - `:metadata` - Additional metadata

  ## Returns

    - `{:ok, %{user: memory, ai: memory}}` on success
    - `{:ok, :skipped}` if auto_store disabled and not forced
    - `{:error, reason}` on failure
  """
  @spec store_exchange(String.t(), String.t(), keyword()) ::
          {:ok, %{user: Store.t(), ai: Store.t()} | :skipped} | {:error, term()}
  def store_exchange(user_message, ai_response, opts \\ []) do
    force = Keyword.get(opts, :force, false)
    auto_store = get_config(:auto_store_conversations, @default_auto_store)

    if not auto_store and not force do
      {:ok, :skipped}
    else
      session_id = Keyword.get(opts, :session_id)
      extra_metadata = Keyword.get(opts, :metadata, %{})

      base_metadata =
        if session_id do
          Map.put(extra_metadata, :session_id, session_id)
        else
          extra_metadata
        end

      # Store user message
      user_metadata = Map.put(base_metadata, :role, "user")
      user_result = store(user_message, "user_input", metadata: user_metadata)

      # Store AI response
      ai_metadata = Map.put(base_metadata, :role, "assistant")
      ai_result = store(ai_response, "agent_output", metadata: ai_metadata)

      case {user_result, ai_result} do
        {{:ok, user_mem}, {:ok, ai_mem}} ->
          {:ok, %{user: user_mem, ai: ai_mem}}

        {{:error, reason}, _} ->
          Logger.warning("Failed to store user message: #{inspect(reason)}")
          {:error, {:user_store_failed, reason}}

        {_, {:error, reason}} ->
          Logger.warning("Failed to store AI response: #{inspect(reason)}")
          {:error, {:ai_store_failed, reason}}
      end
    end
  end

  @doc """
  Check if the memory system is enabled.

  ## Returns

    - `true` if enabled
    - `false` if disabled via config
  """
  @spec enabled?() :: boolean()
  def enabled? do
    get_config(:enabled, @default_enabled)
  end

  @doc """
  Check if auto-store of conversations is enabled.
  """
  @spec auto_store_enabled?() :: boolean()
  def auto_store_enabled? do
    enabled?() and get_config(:auto_store_conversations, @default_auto_store)
  end

  @doc """
  Get the configured maximum context characters.
  """
  @spec max_context_chars() :: pos_integer()
  def max_context_chars do
    get_config(:max_context_chars, @default_max_context_chars)
  end

  @doc """
  Get the configured relevance threshold.
  """
  @spec relevance_threshold() :: float()
  def relevance_threshold do
    get_config(:relevance_threshold, @default_relevance_threshold)
  end

  @doc """
  Truncate content using the smart head/tail preservation strategy.

  Delegates to `HAL.Memory.Truncation.truncate/2`.

  ## Parameters

    - `content` - Text to truncate
    - `opts` - Truncation options (see `HAL.Memory.Truncation`)

  ## Examples

      truncated = HAL.Memory.truncate(long_content, max_chars: 4000)
  """
  @spec truncate(String.t(), keyword()) :: String.t()
  def truncate(content, opts \\ []) do
    Truncation.truncate(content, opts)
  end

  @doc """
  Check configuration status of the memory system.

  Returns a map with configuration status for debugging.
  """
  @spec status() :: map()
  def status do
    embedding_status =
      case Embedding.check_config() do
        :ok -> :configured
        {:error, reason} -> {:error, reason}
      end

    %{
      enabled: enabled?(),
      auto_store_conversations: auto_store_enabled?(),
      max_context_chars: max_context_chars(),
      relevance_threshold: relevance_threshold(),
      embedding_service: embedding_status,
      embedding_dimension: Embedding.get_embedding_dimension()
    }
  end

  # Private functions

  defp generate_embedding(content) do
    # Truncate very long content before embedding
    # Google embeddings have a token limit (~2048 tokens)
    truncated = Truncation.truncate(content, max_chars: 8000)
    embedding_client().embed(truncated, task_type: :retrieval_document)
  end

  defp embedding_client do
    Application.get_env(:hal, :embedding_client, Embedding)
  end

  defp get_config(key, default) do
    case Application.get_env(:hal, __MODULE__, []) do
      config when is_list(config) -> Keyword.get(config, key, default)
      _ -> default
    end
  end

  defp check_enabled do
    if enabled?() do
      :ok
    else
      Logger.debug("Memory system disabled, skipping store")
      {:error, :memory_disabled}
    end
  end

  defp maybe_generate_embedding(content, opts) do
    if Keyword.get(opts, :skip_embedding, false) do
      {:ok, nil}
    else
      case generate_embedding(content) do
        {:ok, embedding} ->
          {:ok, embedding}

        {:error, reason} ->
          Logger.warning(
            "Failed to generate embedding: #{inspect(reason)}. Storing without embedding."
          )

          # Graceful degradation - store without embedding
          {:ok, nil}
      end
    end
  end
end
