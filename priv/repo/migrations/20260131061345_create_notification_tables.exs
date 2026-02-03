defmodule Hal.Repo.Migrations.CreateNotificationTables do
  use Ecto.Migration

  def change do
    # Notification preferences per user
    create table(:notification_preferences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false

      # Proactive notification toggles
      add :calendar_reminders, :boolean, default: true
      add :email_alerts, :boolean, default: true
      add :task_reminders, :boolean, default: true
      add :daily_summary, :boolean, default: false

      # Calendar reminder timing (minutes before)
      add :calendar_reminder_minutes, {:array, :integer}, default: [15, 60]

      # Quiet hours (stored as minutes from midnight, UTC offset handled in code)
      add :quiet_hours_enabled, :boolean, default: false
      # 10 PM (22:00)
      add :quiet_hours_start, :integer, default: 1320
      # 8 AM (08:00)
      add :quiet_hours_end, :integer, default: 480
      add :timezone, :string, default: "UTC"

      # Daily summary time (minutes from midnight in user's timezone)
      # 9 AM
      add :daily_summary_time, :integer, default: 540

      # Email alert keywords (triggers urgent notification)
      add :urgent_email_keywords, {:array, :string},
        default: ["urgent", "ASAP", "immediately", "critical"]

      add :urgent_email_senders, {:array, :string}, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:notification_preferences, [:user_id])

    # Notification history for tracking and avoiding duplicates
    create table(:notification_history, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false

      # What triggered this notification
      # calendar, email, task, daily_summary
      add :trigger_type, :string, null: false
      # External ID (calendar event ID, email ID, etc.)
      add :trigger_id, :string

      # Notification content
      add :title, :string, null: false
      add :body, :text
      # normal, urgent
      add :priority, :string, default: "normal"

      # Delivery status
      # pending, delivered, failed, suppressed
      add :status, :string, default: "pending"
      # telegram, slack, discord, email
      add :channel, :string
      # ID from the channel (for tracking)
      add :channel_message_id, :string
      # If failed
      add :error_reason, :string

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:notification_history, [:user_id])
    create index(:notification_history, [:trigger_type, :trigger_id])
    create index(:notification_history, [:user_id, :trigger_type, :trigger_id])
    create index(:notification_history, [:status])
    create index(:notification_history, [:inserted_at])
  end
end
