defmodule Hal.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    # Documents table - tracks uploaded files
    create table(:documents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false

      # Document metadata
      add :title, :string, null: false
      add :filename, :string
      # application/pdf, text/plain, text/markdown
      add :content_type, :string
      add :file_size, :integer

      # Processing status
      # pending, processing, completed, failed
      add :status, :string, default: "pending"
      add :error_message, :text

      # Statistics
      add :chunk_count, :integer, default: 0
      add :total_tokens, :integer, default: 0

      # Optional: store raw content for small files
      add :raw_content, :text

      # Tags and categories for organization
      add :tags, {:array, :string}, default: []
      add :category, :string

      timestamps(type: :utc_datetime)
    end

    create index(:documents, [:user_id])
    create index(:documents, [:status])
    create index(:documents, [:user_id, :status])
    create index(:documents, [:tags], using: :gin)

    # Document chunks - individual pieces stored in memory system
    # Links chunks back to their source document
    create table(:document_chunks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :document_id, references(:documents, on_delete: :delete_all, type: :binary_id),
        null: false

      add :memory_id, references(:memories, on_delete: :delete_all, type: :binary_id), null: false

      # Chunk metadata
      # Position in document
      add :chunk_index, :integer, null: false
      # For PDFs
      add :page_number, :integer
      # If extractable
      add :section_title, :string

      # For citation purposes
      add :start_char, :integer
      add :end_char, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:document_chunks, [:document_id])
    create index(:document_chunks, [:memory_id])
    create unique_index(:document_chunks, [:document_id, :chunk_index])
  end
end
