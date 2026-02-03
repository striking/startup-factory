defmodule Hal.Repo.Migrations.CreateUserMemories do
  use Ecto.Migration

  def up do
    # Ensure pgvector is available for vector columns/indexes.
    execute "CREATE EXTENSION IF NOT EXISTS vector"

    create table(:user_memories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)

      add :content, :text, null: false
      add :embedding, :vector, size: 1536
      add :type, :string
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:user_memories, [:user_id])
    create index(:user_memories, [:type])
    create index(:user_memories, [:inserted_at])

    execute """
    CREATE INDEX user_memories_embedding_idx
    ON user_memories
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100)
    """
  end

  def down do
    drop table(:user_memories)
  end
end
