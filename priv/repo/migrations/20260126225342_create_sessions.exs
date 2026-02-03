defmodule Hal.Repo.Migrations.CreateSessions do
  use Ecto.Migration

  def change do
    create table(:sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :channel_type, :string, null: false
      add :channel_id, :string, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :claude_session_id, :string
      add :settings, :map, default: %{}
      add :metadata, :map, default: %{}
      add :last_activity, :utc_datetime, null: false
      add :status, :string, default: "active", null: false

      timestamps(type: :utc_datetime)
    end

    # Composite index for fast session lookups by channel
    create index(:sessions, [:channel_type, :channel_id, :user_id])

    # Index for activity-based queries (e.g., finding stale sessions)
    create index(:sessions, [:last_activity])

    # Index on user_id for fast user session lookups
    create index(:sessions, [:user_id])
  end
end
