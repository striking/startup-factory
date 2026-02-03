defmodule Hal.Repo.Migrations.AddRoleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string, null: false, default: "user"
    end

    create index(:users, [:role])

    execute(
      "UPDATE users SET role = 'owner' WHERE platform = 'terminal' AND external_id = 'web-chat-user'",
      "UPDATE users SET role = 'user' WHERE platform = 'terminal' AND external_id = 'web-chat-user'"
    )
  end
end
