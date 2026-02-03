defmodule Hal.Knowledge.Document do
  @moduledoc """
  Schema for uploaded documents in the knowledge base.

  Tracks document metadata, processing status, and links to chunks.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Hal.Accounts.User
  alias Hal.Knowledge.DocumentChunk
  alias Hal.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending processing completed failed)
  @content_types ~w(application/pdf text/plain text/markdown text/html)

  schema "documents" do
    belongs_to :user, User
    has_many :chunks, DocumentChunk

    field :title, :string
    field :filename, :string
    field :content_type, :string
    field :file_size, :integer

    field :status, :string, default: "pending"
    field :error_message, :string

    field :chunk_count, :integer, default: 0
    field :total_tokens, :integer, default: 0

    field :raw_content, :string
    field :tags, {:array, :string}, default: []
    field :category, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a document.
  """
  def changeset(document, attrs) do
    document
    |> cast(attrs, [
      :user_id,
      :title,
      :filename,
      :content_type,
      :file_size,
      :status,
      :error_message,
      :chunk_count,
      :total_tokens,
      :raw_content,
      :tags,
      :category
    ])
    |> validate_required([:user_id, :title])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:content_type, @content_types ++ [nil])
  end

  @doc """
  Creates a new document record.
  """
  @spec create(binary(), map()) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def create(user_id, attrs) do
    %__MODULE__{}
    |> changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert()
  end

  @doc """
  Gets a document by ID.
  """
  @spec get(binary()) :: %__MODULE__{} | nil
  def get(id), do: Repo.get(__MODULE__, id)

  @doc """
  Gets a document with chunks preloaded.
  """
  @spec get_with_chunks(binary()) :: %__MODULE__{} | nil
  def get_with_chunks(id) do
    __MODULE__
    |> Repo.get(id)
    |> Repo.preload(:chunks)
  end

  @doc """
  Lists documents for a user.
  """
  @spec list_for_user(binary(), keyword()) :: [%__MODULE__{}]
  def list_for_user(user_id, opts \\ []) do
    status = Keyword.get(opts, :status)
    category = Keyword.get(opts, :category)
    tag = Keyword.get(opts, :tag)
    limit = Keyword.get(opts, :limit, 50)

    query =
      from(d in __MODULE__,
        where: d.user_id == ^user_id,
        order_by: [desc: d.inserted_at],
        limit: ^limit
      )

    query = if status, do: where(query, [d], d.status == ^status), else: query
    query = if category, do: where(query, [d], d.category == ^category), else: query
    query = if tag, do: where(query, [d], ^tag in d.tags), else: query

    Repo.all(query)
  end

  @doc """
  Updates document status.
  """
  @spec update_status(binary(), String.t(), keyword()) :: {:ok, %__MODULE__{}} | {:error, term()}
  def update_status(id, status, opts \\ []) do
    case get(id) do
      nil ->
        {:error, :not_found}

      doc ->
        attrs = %{status: status}

        attrs =
          if error = Keyword.get(opts, :error),
            do: Map.put(attrs, :error_message, error),
            else: attrs

        attrs =
          if count = Keyword.get(opts, :chunk_count),
            do: Map.put(attrs, :chunk_count, count),
            else: attrs

        attrs =
          if tokens = Keyword.get(opts, :total_tokens),
            do: Map.put(attrs, :total_tokens, tokens),
            else: attrs

        doc
        |> changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Deletes a document and all its chunks.
  """
  @spec delete(binary()) :: {:ok, %__MODULE__{}} | {:error, term()}
  def delete(id) do
    case get(id) do
      nil -> {:error, :not_found}
      doc -> Repo.delete(doc)
    end
  end

  @doc """
  Searches documents by title or tags.
  """
  @spec search(binary(), String.t()) :: [%__MODULE__{}]
  def search(user_id, query) do
    search_term = "%#{query}%"

    from(d in __MODULE__,
      where: d.user_id == ^user_id,
      where: ilike(d.title, ^search_term) or ^query in d.tags,
      order_by: [desc: d.inserted_at],
      limit: 20
    )
    |> Repo.all()
  end
end
