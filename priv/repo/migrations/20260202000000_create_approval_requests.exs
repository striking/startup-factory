defmodule Hal.Repo.Migrations.CreateApprovalRequests do
  use Ecto.Migration

  def change do
    create table(:approval_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :token, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false

      add :status, :string, null: false, default: "pending"
      add :tool_name, :string, null: false
      add :args, :map, default: %{}
      add :context, :map, default: %{}

      add :approved_at, :utc_datetime
      add :denied_at, :utc_datetime
      add :deny_reason, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:approval_requests, [:token])
    create index(:approval_requests, [:user_id])
    create index(:approval_requests, [:status])
    create index(:approval_requests, [:inserted_at])
  end
end
