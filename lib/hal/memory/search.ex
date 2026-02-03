defmodule HAL.Memory.Search do
  @moduledoc """
  Semantic search module for HAL memories using pgvector.

  This module provides vector similarity search functionality for the memory store,
  enabling retrieval of semantically relevant memories based on natural language queries.

  ## Usage

      # Search for memories similar to a query
      {:ok, results} = HAL.Memory.Search.search("What are the user's preferences?")

      # Search with options
      {:ok, results} = HAL.Memory.Search.search("dark mode settings",
        limit: 10,
        threshold: 0.7,
        source: "conversation"
      )

      # Find memories similar to an existing memory
      {:ok, results} = HAL.Memory.Search.search_similar(memory_id)

      # Get formatted context for prompt injection
      context = HAL.Memory.Search.get_relevant_context("user preferences",
        max_chars: 2000,
        format: :text
      )

  ## How Similarity Works

  Similarity is calculated using cosine distance via pgvector's `<=>` operator.
  The result is converted to similarity score: `similarity = 1 - distance`.

  - Similarity of 1.0 = identical vectors
  - Similarity of 0.0 = orthogonal vectors
  - Similarity < 0 = opposite vectors (rare with embedding models)

  ## Configuration

  The embedding client can be configured for testing:

      # config/test.exs
      config :hal, :embedding_client, HAL.Memory.EmbeddingMock

  By default, uses `HAL.Memory.Embedding` for production.
  """

  import Ecto.Query

  alias Hal.Memory.Store
  alias Hal.Repo

  require Logger

  # Type definitions

  @type search_result :: %{
          memory: Store.t(),
          similarity: float()
        }

  @type search_opts :: [
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

  # Default values
  @default_limit 5
  @default_threshold 0.8

  # Public API

  @doc """
  Search for memories semantically similar to the given query.

  Generates an embedding for the query text and searches pgvector for similar memories
  using cosine distance.

  ## Parameters

    - `query` - The search query text
    - `opts` - Optional keyword list:
      - `:limit` - Maximum number of results (default: #{@default_limit})
      - `:threshold` - Minimum similarity score 0.0-1.0 (default: #{@default_threshold})
      - `:source` - Filter by memory source type
      - `:metadata` - Filter by metadata fields (partial match)

  ## Returns

    - `{:ok, [%{memory: memory, similarity: float}]}` on success
    - `{:error, term()}` on embedding or query failure

  ## Examples

      # Basic search
      {:ok, results} = HAL.Memory.Search.search("What does the user prefer?")
      Enum.each(results, fn %{memory: m, similarity: s} ->
        IO.puts("[\#{Float.round(s, 2)}] \#{m.content}")
      end)

      # Search with filters
      {:ok, results} = HAL.Memory.Search.search("dark mode",
        limit: 3,
        threshold: 0.6,
        source: "conversation"
      )

      # Search with metadata filter
      {:ok, results} = HAL.Memory.Search.search("user settings",
        metadata: %{"importance" => "high"}
      )
  """
  @spec search(String.t(), search_opts()) :: {:ok, [search_result()]} | {:error, term()}
  def search(query, opts \\ []) when is_binary(query) do
    with {:ok, query_embedding} <- generate_query_embedding(query) do
      execute_similarity_search(query_embedding, opts)
    end
  end

  @doc """
  Find memories similar to an existing memory by ID.

  Uses the existing memory's embedding vector, avoiding the need to regenerate an embedding.
  Useful for finding related memories or building memory clusters.

  ## Parameters

    - `memory_id` - UUID of the source memory
    - `opts` - Same options as `search/2`

  ## Returns

    - `{:ok, [%{memory: memory, similarity: float}]}` on success
    - `{:error, :not_found}` if memory doesn't exist
    - `{:error, :no_embedding}` if memory has no embedding
    - `{:error, term()}` on query failure

  ## Examples

      {:ok, similar} = HAL.Memory.Search.search_similar(memory_id, limit: 10)

      # Exclude the source memory from results (it would have similarity 1.0)
      similar_others = Enum.reject(similar, fn %{memory: m} -> m.id == memory_id end)
  """
  @spec search_similar(binary(), search_opts()) :: {:ok, [search_result()]} | {:error, term()}
  def search_similar(memory_id, opts \\ []) when is_binary(memory_id) do
    case Store.get_memory(memory_id) do
      nil ->
        {:error, :not_found}

      %{embedding: nil} ->
        {:error, :no_embedding}

      %{embedding: embedding} ->
        # Convert Pgvector type to list if needed
        embedding_list = to_embedding_list(embedding)
        execute_similarity_search(embedding_list, opts)
    end
  end

  @doc """
  Get relevant context for prompt injection.

  High-level function that searches for relevant memories and formats them
  for inclusion in LLM prompts. Handles truncation and formatting automatically.

  ## Parameters

    - `query` - The search query text
    - `opts` - Optional keyword list:
      - `:max_chars` - Maximum characters in output (default: nil, no limit)
      - `:format` - Output format, `:text` or `:structured` (default: :text)
      - `:limit` - Maximum memories to include (default: #{@default_limit})
      - `:threshold` - Minimum similarity (default: #{@default_threshold})
      - `:source` - Filter by source type

  ## Returns

    - Formatted string with relevant memories
    - Empty string if no relevant memories found or on error

  ## Formats

  ### :text (default)
  Plain text format suitable for most prompts:

      Relevant context from memory:
      - [0.95] I prefer dark mode for all interfaces
      - [0.87] The user mentioned they work late at night

  ### :structured
  Structured format with metadata:

      <relevant_memories>
        <memory similarity="0.95" source="conversation">
          I prefer dark mode for all interfaces
        </memory>
        <memory similarity="0.87" source="observation">
          The user mentioned they work late at night
        </memory>
      </relevant_memories>

  ## Examples

      # Basic usage
      context = HAL.Memory.Search.get_relevant_context("user preferences")

      # With truncation
      context = HAL.Memory.Search.get_relevant_context("settings",
        max_chars: 1000,
        format: :text
      )

      # Structured for XML-based prompts
      context = HAL.Memory.Search.get_relevant_context("history",
        format: :structured,
        limit: 3
      )
  """
  @spec get_relevant_context(String.t(), context_opts()) :: String.t()
  def get_relevant_context(query, opts \\ []) when is_binary(query) do
    search_opts = [
      limit: Keyword.get(opts, :limit, @default_limit),
      threshold: Keyword.get(opts, :threshold, @default_threshold),
      source: Keyword.get(opts, :source)
    ]

    max_chars = Keyword.get(opts, :max_chars)
    format = Keyword.get(opts, :format, :text)

    case search(query, search_opts) do
      {:ok, []} ->
        ""

      {:ok, results} ->
        format_context(results, format, max_chars)

      {:error, reason} ->
        Logger.warning("Failed to get relevant context: #{inspect(reason)}")
        ""
    end
  end

  # Private functions

  defp generate_query_embedding(query) do
    embedding_client().embed(query, task_type: :retrieval_query)
  end

  defp embedding_client do
    Application.get_env(:hal, :embedding_client, HAL.Memory.Embedding)
  end

  defp execute_similarity_search(query_embedding, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    threshold = Keyword.get(opts, :threshold, @default_threshold)
    source = Keyword.get(opts, :source)
    metadata = Keyword.get(opts, :metadata)

    # Convert threshold to distance (cosine distance = 1 - similarity)
    # If threshold is 0.8 similarity, max distance is 0.2
    max_distance = 1.0 - threshold

    # Convert embedding list to Pgvector format for the query
    query_vector = Pgvector.new(query_embedding)

    query =
      from(m in Store,
        where: fragment("? <=> ?", m.embedding, ^query_vector) <= ^max_distance,
        order_by: fragment("? <=> ?", m.embedding, ^query_vector),
        limit: ^limit,
        select: %{
          memory: m,
          distance: fragment("? <=> ?", m.embedding, ^query_vector)
        }
      )

    # Apply optional filters
    query = maybe_filter_by_source(query, source)
    query = maybe_filter_by_metadata(query, metadata)

    results =
      query
      |> Repo.all()
      |> Enum.map(fn %{memory: memory, distance: distance} ->
        %{
          memory: memory,
          similarity: 1.0 - distance
        }
      end)

    {:ok, results}
  rescue
    error ->
      Logger.error("Similarity search failed: #{inspect(error)}")
      {:error, {:query_failed, error}}
  end

  defp maybe_filter_by_source(query, nil), do: query

  defp maybe_filter_by_source(query, source) do
    where(query, [m], m.source == ^source)
  end

  defp maybe_filter_by_metadata(query, nil), do: query
  defp maybe_filter_by_metadata(query, metadata) when metadata == %{}, do: query

  defp maybe_filter_by_metadata(query, metadata) when is_map(metadata) do
    # Filter by each metadata key-value pair using @> containment operator
    where(query, [m], fragment("? @> ?", m.metadata, ^metadata))
  end

  defp to_embedding_list(%Pgvector{} = vector), do: Pgvector.to_list(vector)
  defp to_embedding_list(list) when is_list(list), do: list

  defp format_context(results, :text, max_chars) do
    header = "Relevant context from memory:\n"

    items =
      results
      |> Enum.map(fn %{memory: memory, similarity: similarity} ->
        "- [#{Float.round(similarity, 2)}] #{memory.content}"
      end)
      |> Enum.join("\n")

    full_text = header <> items

    if max_chars && String.length(full_text) > max_chars do
      truncate_text(full_text, max_chars)
    else
      full_text
    end
  end

  defp format_context(results, :structured, max_chars) do
    items =
      results
      |> Enum.map(fn %{memory: memory, similarity: similarity} ->
        source_attr = if memory.source, do: ~s( source="#{memory.source}"), else: ""

        ~s(  <memory similarity="#{Float.round(similarity, 2)}"#{source_attr}>\n    #{escape_xml(memory.content)}\n  </memory>)
      end)
      |> Enum.join("\n")

    full_text = "<relevant_memories>\n#{items}\n</relevant_memories>"

    if max_chars && String.length(full_text) > max_chars do
      truncate_text(full_text, max_chars)
    else
      full_text
    end
  end

  defp truncate_text(text, max_chars) do
    if String.length(text) <= max_chars do
      text
    else
      String.slice(text, 0, max_chars - 3) <> "..."
    end
  end

  defp escape_xml(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
