defmodule Hal.Repo.Migrations.CreateHabits do
  use Ecto.Migration

  def change do
    create table(:habits, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :name, :string, null: false
      add :description, :text
      # daily, weekly, custom
      add :frequency, :string, null: false
      # times per frequency
      add :target_count, :integer, default: 1
      # [1,2,3,4,5] for weekdays
      add :target_days, {:array, :integer}, default: []

      # preferred reminder time
      add :reminder_time, :time
      add :reminder_enabled, :boolean, default: true

      add :current_streak, :integer, default: 0
      add :longest_streak, :integer, default: 0
      add :total_completions, :integer, default: 0

      # active, paused, archived
      add :status, :string, default: "active"
      # health, productivity, learning, etc.
      add :category, :string
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:habits, [:user_id])
    create index(:habits, [:user_id, :status])
    create index(:habits, [:status, :reminder_enabled])

    create table(:habit_completions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :habit_id, references(:habits, type: :binary_id, on_delete: :delete_all), null: false

      add :completed_at, :utc_datetime, null: false
      # for easy daily grouping
      add :date, :date, null: false
      add :notes, :text
      # 1-5 rating of how well they did
      add :quality, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:habit_completions, [:habit_id])
    create index(:habit_completions, [:habit_id, :date])

    create unique_index(:habit_completions, [:habit_id, :date],
             name: :habit_completions_habit_date_unique
           )
  end
end
