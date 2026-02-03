defmodule Hal.Repo.Migrations.CreateCostRecords do
  use Ecto.Migration

  def change do
    create table(:cost_records, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)

      # Provider identification
      # claude, gemini, codex, jules
      add :provider, :string, null: false

      # Model details
      # claude-opus-4-5-20251101, gemini-1.5-flash, etc.
      add :model, :string

      # Token usage
      add :input_tokens, :integer, null: false, default: 0
      add :output_tokens, :integer, null: false, default: 0
      add :cache_read_tokens, :integer, default: 0
      add :cache_write_tokens, :integer, default: 0

      # Cost in cents (avoid float precision issues)
      add :cost_cents, :integer, null: false, default: 0

      # Context
      # heartbeat, chat, goal_work, delegation, etc.
      add :task_type, :string
      add :session_id, :binary_id
      add :goal_id, :binary_id

      # Metadata for additional details
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    # Indices for efficient aggregation queries
    create index(:cost_records, [:user_id, :inserted_at])
    create index(:cost_records, [:provider, :inserted_at])
    create index(:cost_records, [:task_type, :inserted_at])
    create index(:cost_records, [:session_id])

    # Daily budgets table
    create table(:cost_budgets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Budget limits (cents)
      # $10/day default
      add :daily_limit_cents, :integer, default: 1000
      # $100/month default
      add :monthly_limit_cents, :integer, default: 10000

      # Alert thresholds (0.0 - 1.0)
      # Alert at 80% of budget
      add :alert_threshold, :float, default: 0.8

      # Current period tracking
      add :current_day_cents, :integer, default: 0
      add :current_month_cents, :integer, default: 0
      add :last_reset_date, :date

      # Alert status
      add :alerts_enabled, :boolean, default: true
      add :last_alert_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:cost_budgets, [:user_id])
  end
end
