defmodule Hal.Memory.Store do
  @moduledoc """
  Ecto-based memory store with vector embeddings for semantic search.

  This module provides persistent storage for memories with vector embeddings,
  enabling semantic similarity search via pgvector. It complements the markdown-based
  `Hal.Memory` module with more structured, queryable storage.

  ## Usage

      # Create a memory with an embedding
      embedding = Hal.Memory.Embedding.generate("I prefer dark mode")
      {:ok, memory} = Hal.Memory.Store.create_memory(
        "I prefer dark mode",
        embedding,
        source: "conversation",
        metadata: %{user_id: "abc123", importance: "high"}
      )

      # Retrieve a memory by ID
      memory = Hal.Memory.Store.get_memory(memory.id)

      # List memories with filters
      memories = Hal.Memory.Store.list_memories(
        source: "conversation",
        limit: 10
      )

      # Update metadata
      {:ok, updated} = Hal.Memory.Store.update_metadata(
        memory.id,
        %{reviewed: true}
      )

      # Delete a memory
      {:ok, _} = Hal.Memory.Store.delete_memory(memory.id)

  ## Schema

  The `memories` table stores:
    - `id` - UUID primary key
    - `content` - The text content of the memory
    - `embedding` - 3072-dimensional vector (for gemini-embedding-001)
    - `metadata` - JSONB map for flexible metadata storage
    - `source` - Memory source type (conversation, document, observation, etc.)
    - `inserted_at`, `updated_at` - Timestamps

  ## Notes

  Vector indexes in pgvector are limited to 2000 dimensions, so the 3072-dimensional
  embeddings from gemini-embedding-001 use exact (non-indexed) search. This is fine
  for up to ~100k memories. Consider using a smaller embedding model if you need
  indexed approximate nearest neighbor (ANN) search.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Hal.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_sources ~w(conversation document observation system user_input agent_output)

  schema "memories" do
    field :content, :string
    field :embedding, Pgvector.Ecto.Vector
    field :metadata, :map, default: %{}
    field :source, :string

    timestamps(type: :utc_datetime)
  end

  # Type definitions

  @type t :: %__MODULE__{
          id: binary() | nil,
          content: String.t(),
          embedding: Pgvector.Ecto.Vector.t() | nil,
          metadata: map(),
          source: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @type create_opts :: [
          source: String.t(),
          metadata: map()
        ]

  @type list_opts :: [
          source: String.t(),
          limit: pos_integer(),
          offset: non_neg_integer()
        ]

  # Changesets

  @doc """
  Creates a changeset for a new memory.

  ## Parameters

    - `memory` - The memory struct (usually `%__MODULE__{}`)
    - `attrs` - Map of attributes to apply

  ## Validations

    - `content` is required and must not be blank
    - `source` if provided must be one of: #{Enum.join(@valid_sources, ", ")}
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [:content, :embedding, :metadata, :source])
    |> validate_required([:content])
    |> validate_content_not_blank()
    |> validate_inclusion(:source, @valid_sources,
      message: "must be one of: #{Enum.join(@valid_sources, ", ")}"
    )
  end

  defp validate_content_not_blank(changeset) do
    validate_change(changeset, :content, fn :content, content ->
      if String.trim(content) == "" do
        [content: "cannot be blank"]
      else
        []
      end
    end)
  end

  # Public API

  @doc """
  Creates a new memory with the given content and embedding.

  ## Parameters

    - `content` - The text content of the memory (required)
    - `embedding` - The vector embedding for the content (can be nil)
    - `opts` - Optional keyword list:
      - `:source` - Memory source type (e.g., "conversation", "document")
      - `:metadata` - Map of additional metadata

  ## Returns

    - `{:ok, memory}` on success
    - `{:error, changeset}` on validation failure

  ## Examples

      # Create with just content
      {:ok, memory} = Hal.Memory.Store.create_memory("Remember this", nil)

      # Create with embedding and options
      {:ok, memory} = Hal.Memory.Store.create_memory(
        "I prefer dark mode",
        embedding_vector,
        source: "conversation",
        metadata: %{user_id: "abc", importance: "high"}
      )
  """
  @spec create_memory(String.t(), Pgvector.Ecto.Vector.t() | list() | nil, create_opts()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create_memory(content, embedding, opts \\ []) do
    attrs = %{
      content: content,
      embedding: embedding,
      source: Keyword.get(opts, :source),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Retrieves a memory by its ID.

  ## Parameters

    - `id` - The UUID of the memory

  ## Returns

    - The memory struct if found
    - `nil` if not found

  ## Examples

      memory = Hal.Memory.Store.get_memory("550e8400-e29b-41d4-a716-446655440000")
  """
  @spec get_memory(binary()) :: t() | nil
  def get_memory(id) when is_binary(id) do
    Repo.get(__MODULE__, id)
  end

  @doc """
  Lists memories with optional filtering and pagination.

  ## Parameters

    - `opts` - Optional keyword list:
      - `:source` - Filter by source type
      - `:limit` - Maximum number of results (default: 50)
      - `:offset` - Number of results to skip (default: 0)

  ## Returns

    List of memory structs, ordered by `inserted_at` descending (newest first).

  ## Examples

      # Get all memories (up to default limit)
      memories = Hal.Memory.Store.list_memories()

      # Filter by source with pagination
      memories = Hal.Memory.Store.list_memories(
        source: "conversation",
        limit: 10,
        offset: 20
      )
  """
  @spec list_memories(list_opts()) :: [t()]
  def list_memories(opts \\ []) do
    source = Keyword.get(opts, :source)
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    __MODULE__
    |> maybe_filter_by_source(source)
    |> order_by([m], desc: m.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  defp maybe_filter_by_source(query, nil), do: query
  defp maybe_filter_by_source(query, source), do: where(query, [m], m.source == ^source)

  @doc """
  Deletes a memory by its ID.

  ## Parameters

    - `id` - The UUID of the memory to delete

  ## Returns

    - `{:ok, memory}` if the memory was deleted successfully
    - `{:error, :not_found}` if no memory exists with that ID
    - `{:error, changeset}` if deletion failed

  ## Examples

      {:ok, deleted_memory} = Hal.Memory.Store.delete_memory(memory.id)
  """
  @spec delete_memory(binary()) :: {:ok, t()} | {:error, :not_found | Ecto.Changeset.t()}
  def delete_memory(id) when is_binary(id) do
    case get_memory(id) do
      nil -> {:error, :not_found}
      memory -> Repo.delete(memory)
    end
  end

  @doc """
  Updates the metadata of an existing memory.

  Merges the provided metadata updates into the existing metadata map.
  Existing keys are overwritten, new keys are added.

  ## Parameters

    - `id` - The UUID of the memory to update
    - `metadata_updates` - Map of metadata to merge

  ## Returns

    - `{:ok, memory}` on success
    - `{:error, :not_found}` if no memory exists with that ID
    - `{:error, changeset}` on validation failure

  ## Examples

      # Add new metadata
      {:ok, memory} = Hal.Memory.Store.update_metadata(
        memory.id,
        %{reviewed: true, reviewer: "user123"}
      )

      # Update existing metadata (merges with existing)
      {:ok, memory} = Hal.Memory.Store.update_metadata(
        memory.id,
        %{importance: "critical"}
      )
  """
  @spec update_metadata(binary(), map()) :: {:ok, t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_metadata(id, metadata_updates) when is_binary(id) and is_map(metadata_updates) do
    case get_memory(id) do
      nil ->
        {:error, :not_found}

      memory ->
        merged_metadata = Map.merge(memory.metadata || %{}, metadata_updates)

        memory
        |> changeset(%{metadata: merged_metadata})
        |> Repo.update()
    end
  end

  @doc """
  Returns the list of valid source types.

  ## Examples

      Hal.Memory.Store.valid_sources()
      #=> ["conversation", "document", "observation", "system", "user_input", "agent_output"]
  """
  @spec valid_sources() :: [String.t()]
  def valid_sources, do: @valid_sources
end
