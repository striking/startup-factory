defmodule Hal.Repo.Migrations.CreateMemories do
  use Ecto.Migration

  def up do
    # Enable the pgvector extension
    execute "CREATE EXTENSION IF NOT EXISTS vector"

    # Create the memories table
    create table(:memories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :content, :text, null: false
      # 3072 dimensions for gemini-embedding-001
      # Note: pgvector HNSW/IVFFlat indexes are limited to 2000 dimensions
      # For high-dimensional vectors, we rely on exact search initially
      # Consider using text-embedding-3-small (1536d) for indexed search
      add :embedding, :vector, size: 3072
      add :metadata, :map, default: %{}
      # Source type: "conversation", "document", "observation", etc.
      add :source, :string

      timestamps(type: :utc_datetime)
    end

    # Create standard indexes for filtering
    create index(:memories, [:source])
    create index(:memories, [:inserted_at])

    # Note on vector index:
    # pgvector HNSW and IVFFlat indexes are limited to 2000 dimensions.
    # Since gemini-embedding-001 produces 3072-dimensional vectors, we cannot
    # create an ANN index. Options for future optimization:
    # 1. Switch to text-embedding-3-small (1536d) or text-embedding-004 (768d)
    # 2. Use dimensionality reduction (PCA) on embeddings
    # 3. Wait for pgvector to support higher dimensions
    # For now, exact search (<->) will be used, which is fine for <100k memories
  end

  def down do
    drop table(:memories)

    # Note: We don't drop the vector extension as other tables may use it
  end
end
