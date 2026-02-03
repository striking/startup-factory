defmodule Hal.Repo.Migrations.CreateOauthTokens do
  use Ecto.Migration

  def change do
    create table(:oauth_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      add :provider, :string, null: false
      # Tokens stored encrypted (using application-level encryption)
      add :access_token_encrypted, :binary, null: false
      add :refresh_token_encrypted, :binary
      add :token_type, :string, default: "Bearer"
      add :expires_at, :utc_datetime
      add :scopes, {:array, :string}, default: []
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    # One token per user per provider
    create unique_index(:oauth_tokens, [:user_id, :provider])
    create index(:oauth_tokens, [:provider])
    create index(:oauth_tokens, [:expires_at])
  end
end
