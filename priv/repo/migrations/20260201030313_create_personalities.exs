defmodule Hal.Repo.Migrations.CreatePersonalities do
  use Ecto.Migration

  def change do
    create table(:personalities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Core personality traits (0.0 - 1.0 scale)
      # These influence HAL's communication style and behavior
      # How directly HAL communicates
      add :assertiveness, :float, default: 0.7
      # Emotional tone (0=formal, 1=friendly)
      add :warmth, :float, default: 0.5
      # Response length preference
      add :verbosity, :float, default: 0.4
      # Initiative level
      add :proactivity, :float, default: 0.8
      # Willingness to take uncertain actions
      add :risk_tolerance, :float, default: 0.6

      # Additional traits that can be added over time
      # Use of humor in responses
      add :humor, :float, default: 0.3
      # Formal vs casual communication
      add :formality, :float, default: 0.5

      # Flexible preferences learned over time
      # e.g., %{"prefers_bullet_points" => true, "timezone" => "Australia/Sydney"}
      add :learned_preferences, :map, default: %{}

      # Audit trail of personality changes
      # Each entry: %{timestamp, trait, old_value, new_value, reason}
      add :evolution_log, {:array, :map}, default: []

      # Track modification limits (3/day max per plan)
      add :modifications_today, :integer, default: 0
      add :last_modification_date, :date

      timestamps(type: :utc_datetime)
    end

    create unique_index(:personalities, [:user_id])

    # Index for querying by modification date (for rate limiting)
    create index(:personalities, [:last_modification_date])
  end
end
