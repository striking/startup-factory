defmodule Hal.Notifications.Preference do
  @moduledoc """
  Schema for user notification preferences.

  Controls what proactive notifications a user receives and when.
  Supports quiet hours to suppress notifications during sleep/focus time.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Hal.Accounts.User
  alias Hal.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notification_preferences" do
    belongs_to :user, User

    # Proactive notification toggles
    field :calendar_reminders, :boolean, default: true
    field :email_alerts, :boolean, default: true
    field :task_reminders, :boolean, default: true
    field :daily_summary, :boolean, default: false

    # Calendar reminder timing (minutes before event)
    field :calendar_reminder_minutes, {:array, :integer}, default: [15, 60]

    # Quiet hours configuration
    field :quiet_hours_enabled, :boolean, default: false
    # 10 PM
    field :quiet_hours_start, :integer, default: 1320
    # 8 AM
    field :quiet_hours_end, :integer, default: 480
    field :timezone, :string, default: "UTC"

    # Daily summary timing
    # 9 AM
    field :daily_summary_time, :integer, default: 540

    # Email alert configuration
    field :urgent_email_keywords, {:array, :string},
      default: ["urgent", "ASAP", "immediately", "critical"]

    field :urgent_email_senders, {:array, :string}, default: []

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for notification preferences.
  """
  def changeset(preference, attrs) do
    preference
    |> cast(attrs, [
      :user_id,
      :calendar_reminders,
      :email_alerts,
      :task_reminders,
      :daily_summary,
      :calendar_reminder_minutes,
      :quiet_hours_enabled,
      :quiet_hours_start,
      :quiet_hours_end,
      :timezone,
      :daily_summary_time,
      :urgent_email_keywords,
      :urgent_email_senders
    ])
    |> validate_required([:user_id])
    |> validate_time_range(:quiet_hours_start)
    |> validate_time_range(:quiet_hours_end)
    |> validate_time_range(:daily_summary_time)
    |> unique_constraint(:user_id)
  end

  defp validate_time_range(changeset, field) do
    validate_number(changeset, field, greater_than_or_equal_to: 0, less_than: 1440)
  end

  @doc """
  Gets preferences for a user, creating defaults if none exist.
  """
  @spec get_or_create(binary()) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def get_or_create(user_id) do
    case Repo.get_by(__MODULE__, user_id: user_id) do
      nil ->
        %__MODULE__{}
        |> changeset(%{user_id: user_id})
        |> Repo.insert()

      preference ->
        {:ok, preference}
    end
  end

  @doc """
  Gets preferences for a user (returns nil if none exist).
  """
  @spec get(binary()) :: %__MODULE__{} | nil
  def get(user_id) do
    Repo.get_by(__MODULE__, user_id: user_id)
  end

  @doc """
  Updates preferences for a user.
  """
  @spec update(binary(), map()) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def update(user_id, attrs) do
    case get_or_create(user_id) do
      {:ok, preference} ->
        preference
        |> changeset(attrs)
        |> Repo.update()

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Checks if the current time is within quiet hours for a user.

  Returns true if notifications should be suppressed.
  """
  @spec in_quiet_hours?(binary()) :: boolean()
  def in_quiet_hours?(user_id) do
    case get(user_id) do
      nil -> false
      %{quiet_hours_enabled: false} -> false
      preference -> check_quiet_hours(preference)
    end
  end

  defp check_quiet_hours(%{
         quiet_hours_start: start_mins,
         quiet_hours_end: end_mins,
         timezone: tz
       }) do
    now = get_current_time_in_timezone(tz)
    current_mins = now.hour * 60 + now.minute

    if start_mins > end_mins do
      # Quiet hours span midnight (e.g., 10 PM to 8 AM)
      current_mins >= start_mins or current_mins < end_mins
    else
      # Quiet hours within same day (e.g., 1 PM to 5 PM)
      current_mins >= start_mins and current_mins < end_mins
    end
  end

  defp get_current_time_in_timezone(tz) do
    case DateTime.now(tz) do
      {:ok, dt} -> dt
      {:error, _} -> DateTime.utc_now()
    end
  end

  @doc """
  Gets all users who have a specific notification type enabled.
  """
  @spec users_with_enabled(atom()) :: [%__MODULE__{}]
  def users_with_enabled(notification_type) do
    field_name = notification_type_to_field(notification_type)

    from(p in __MODULE__,
      where: field(p, ^field_name) == true,
      preload: [:user]
    )
    |> Repo.all()
  end

  defp notification_type_to_field(:calendar), do: :calendar_reminders
  defp notification_type_to_field(:email), do: :email_alerts
  defp notification_type_to_field(:task), do: :task_reminders
  defp notification_type_to_field(:daily_summary), do: :daily_summary
end
