defmodule Hal.Repo.Migrations.CreateChangeRequests do
  use Ecto.Migration

  def change do
    create table(:change_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false

      add :title, :string, null: false
      add :request, :text, null: false
      add :status, :string, null: false, default: "pending"

      add :base_sha, :string
      add :worktree_path, :text

      add :diff, :text
      add :changed_files, {:array, :string}, default: []

      add :test_command, :string, default: "mix test"
      add :test_exit_code, :integer
      add :test_output, :text

      add :codex_session_id, :string
      add :approval_token, :string

      add :generated_at, :utc_datetime
      add :applied_at, :utc_datetime
      add :error_message, :text

      timestamps(type: :utc_datetime)
    end

    create index(:change_requests, [:user_id])
    create index(:change_requests, [:status])
    create index(:change_requests, [:inserted_at])
    create index(:change_requests, [:applied_at])
  end
end
