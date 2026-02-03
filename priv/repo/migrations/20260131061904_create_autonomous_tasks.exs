defmodule Hal.Repo.Migrations.CreateAutonomousTasks do
  use Ecto.Migration

  def change do
    # Multi-step autonomous tasks
    create table(:autonomous_tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false

      # Task definition
      add :title, :string, null: false
      add :description, :text
      # The user's original request
      add :original_request, :text, null: false

      # Steps (array of maps: %{name, prompt, status, result, started_at, completed_at})
      add :steps, {:array, :map}, default: []
      add :current_step, :integer, default: 0

      # Status tracking
      # pending, running, paused, completed, failed
      add :status, :string, default: "pending"
      # low, normal, high, urgent
      add :priority, :string, default: "normal"

      # Results
      add :final_result, :text
      add :error_message, :text

      # Timing
      # When to start (nil = immediately)
      add :scheduled_at, :utc_datetime
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :retry_count, :integer, default: 0
      add :max_retries, :integer, default: 3

      # Context for Claude
      # Additional context passed to each step
      add :context, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:autonomous_tasks, [:user_id])
    create index(:autonomous_tasks, [:status])
    create index(:autonomous_tasks, [:user_id, :status])
    create index(:autonomous_tasks, [:scheduled_at])
  end
end
