defmodule Hal.Repo.Migrations.AddStatusUpdatedAtIndexToSessions do
  use Ecto.Migration

  def change do
    # Composite index for efficient archived session cleanup queries
    # Supports: WHERE status = 'archived' AND updated_at < cutoff
    create index(:sessions, [:status, :updated_at])
  end
end
