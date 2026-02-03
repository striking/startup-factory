defmodule Hal.Repo.Migrations.AddPairingRequestsAndUserPairedAt do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :paired_at, :utc_datetime
    end

    create table(:pairing_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :code, :string, null: false
      add :status, :string, null: false, default: "pending"

      add :approved_at, :utc_datetime
      add :denied_at, :utc_datetime
      add :deny_reason, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:pairing_requests, [:code])
    create index(:pairing_requests, [:user_id])
    create index(:pairing_requests, [:status])
  end
end
