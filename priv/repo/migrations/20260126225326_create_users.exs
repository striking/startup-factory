defmodule Hal.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :external_id, :string, null: false
      add :platform, :string, null: false
      add :username, :string
      add :settings, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    # Unique index on platform + external_id for fast lookups
    create unique_index(:users, [:platform, :external_id])
  end
end
