defmodule Hal.Repo.Migrations.CreateGoals do
  use Ecto.Migration

  def change do
    create table(:goals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Hierarchical goals (parent-child relationship)
      add :parent_id, references(:goals, type: :binary_id, on_delete: :nilify_all)

      # Core goal fields
      add :title, :string, null: false
      add :description, :text

      # Goal type determines time horizon
      add :type, :string, null: false, default: "short_term"
      # Values: long_term (months), medium_term (weeks), short_term (days/hours)

      # Status tracking
      add :status, :string, null: false, default: "active"
      # Values: active, paused, completed, abandoned

      # Progress (0.0 - 1.0)
      add :progress, :float, default: 0.0

      # Success criteria (array of strings, all must be met)
      add :success_criteria, {:array, :string}, default: []

      # Optional target date
      add :target_date, :utc_datetime

      # Priority within the same type (higher = more important)
      add :priority, :integer, default: 50

      # Metadata for additional context
      add :metadata, :map, default: %{}

      # Tracking when goal was worked on
      add :last_worked_at, :utc_datetime
      add :work_sessions_count, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    # Index for efficient queries
    create index(:goals, [:user_id, :status])
    create index(:goals, [:user_id, :type, :status])
    create index(:goals, [:parent_id])
    create index(:goals, [:status, :priority])

    # Goal progress tracking table
    create table(:goal_progress_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :goal_id, references(:goals, type: :binary_id, on_delete: :delete_all), null: false

      # Progress change
      add :previous_progress, :float, null: false
      add :new_progress, :float, null: false

      # What was accomplished
      add :summary, :text, null: false

      # Optional: link to session that made progress
      add :session_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    create index(:goal_progress_entries, [:goal_id])
    create index(:goal_progress_entries, [:inserted_at])
  end
end
