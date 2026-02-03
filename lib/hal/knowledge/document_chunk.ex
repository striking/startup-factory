defmodule Hal.Knowledge.DocumentChunk do
  @moduledoc """
  Schema for document chunks that link documents to memories.

  Each chunk is a piece of a document that has been embedded and stored
  in the memory system for semantic search.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Hal.Knowledge.Document
  alias Hal.Memory.Store, as: Memory
  alias Hal.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "document_chunks" do
    belongs_to :document, Document
    belongs_to :memory, Memory

    field :chunk_index, :integer
    field :page_number, :integer
    field :section_title, :string
    field :start_char, :integer
    field :end_char, :integer

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a document chunk.
  """
  def changeset(chunk, attrs) do
    chunk
    |> cast(attrs, [
      :document_id,
      :memory_id,
      :chunk_index,
      :page_number,
      :section_title,
      :start_char,
      :end_char
    ])
    |> validate_required([:document_id, :memory_id, :chunk_index])
    |> unique_constraint([:document_id, :chunk_index])
  end

  @doc """
  Creates a new chunk record.
  """
  @spec create(map()) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists chunks for a document.
  """
  @spec list_for_document(binary()) :: [%__MODULE__{}]
  def list_for_document(document_id) do
    from(c in __MODULE__,
      where: c.document_id == ^document_id,
      order_by: [asc: c.chunk_index],
      preload: [:memory]
    )
    |> Repo.all()
  end

  @doc """
  Gets a chunk by its memory ID.
  """
  @spec get_by_memory(binary()) :: %__MODULE__{} | nil
  def get_by_memory(memory_id) do
    from(c in __MODULE__,
      where: c.memory_id == ^memory_id,
      preload: [:document]
    )
    |> Repo.one()
  end

  @doc """
  Deletes all chunks for a document.
  """
  @spec delete_for_document(binary()) :: {integer(), nil}
  def delete_for_document(document_id) do
    from(c in __MODULE__, where: c.document_id == ^document_id)
    |> Repo.delete_all()
  end
end
