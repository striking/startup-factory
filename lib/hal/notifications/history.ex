defmodule Hal.Notifications.History do
  @moduledoc """
  Schema for tracking sent notifications.

  Records all proactive notifications for:
  - Avoiding duplicate notifications (e.g., same calendar event)
  - Debugging delivery issues
  - User notification history view
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Hal.Accounts.User
  alias Hal.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @trigger_types ~w(calendar email task daily_summary habit_reminder general)
  @statuses ~w(pending delivered failed suppressed)
  @priorities ~w(normal urgent)
  @channels ~w(telegram slack discord email)

  schema "notification_history" do
    belongs_to :user, User

    # Trigger information
    field :trigger_type, :string
    field :trigger_id, :string

    # Content
    field :title, :string
    field :body, :string
    field :priority, :string, default: "normal"

    # Delivery status
    field :status, :string, default: "pending"
    field :channel, :string
    field :channel_message_id, :string
    field :error_reason, :string

    # Additional data
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for notification history.
  """
  def changeset(history, attrs) do
    history
    |> cast(attrs, [
      :user_id,
      :trigger_type,
      :trigger_id,
      :title,
      :body,
      :priority,
      :status,
      :channel,
      :channel_message_id,
      :error_reason,
      :metadata
    ])
    |> validate_required([:user_id, :trigger_type, :title])
    |> validate_inclusion(:trigger_type, @trigger_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:priority, @priorities)
    |> validate_inclusion(:channel, @channels ++ [nil])
  end

  @doc """
  Records a new notification.
  """
  @spec record(map()) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def record(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Marks a notification as delivered.
  """
  @spec mark_delivered(binary(), String.t(), String.t() | nil) ::
          {:ok, %__MODULE__{}} | {:error, term()}
  def mark_delivered(notification_id, channel, message_id \\ nil) do
    case Repo.get(__MODULE__, notification_id) do
      nil ->
        {:error, :not_found}

      notification ->
        notification
        |> changeset(%{
          status: "delivered",
          channel: channel,
          channel_message_id: message_id
        })
        |> Repo.update()
    end
  end

  @doc """
  Marks a notification as failed.
  """
  @spec mark_failed(binary(), String.t()) :: {:ok, %__MODULE__{}} | {:error, term()}
  def mark_failed(notification_id, reason) do
    case Repo.get(__MODULE__, notification_id) do
      nil ->
        {:error, :not_found}

      notification ->
        notification
        |> changeset(%{status: "failed", error_reason: reason})
        |> Repo.update()
    end
  end

  @doc """
  Marks a notification as suppressed (e.g., quiet hours).
  """
  @spec mark_suppressed(binary(), String.t()) :: {:ok, %__MODULE__{}} | {:error, term()}
  def mark_suppressed(notification_id, reason) do
    case Repo.get(__MODULE__, notification_id) do
      nil ->
        {:error, :not_found}

      notification ->
        notification
        |> changeset(%{status: "suppressed", error_reason: reason})
        |> Repo.update()
    end
  end

  @doc """
  Checks if a notification has already been sent for a specific trigger.

  Used to avoid duplicate notifications (e.g., same calendar event reminder).
  """
  @spec already_sent?(binary(), String.t(), String.t()) :: boolean()
  def already_sent?(user_id, trigger_type, trigger_id) do
    from(h in __MODULE__,
      where: h.user_id == ^user_id,
      where: h.trigger_type == ^trigger_type,
      where: h.trigger_id == ^trigger_id,
      where: h.status in ["delivered", "pending"]
    )
    |> Repo.exists?()
  end

  @doc """
  Gets recent notification history for a user.
  """
  @spec recent(binary(), keyword()) :: [%__MODULE__{}]
  def recent(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(h in __MODULE__,
      where: h.user_id == ^user_id,
      order_by: [desc: h.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Gets notifications for a user within a time range.
  """
  @spec for_period(binary(), DateTime.t(), DateTime.t()) :: [%__MODULE__{}]
  def for_period(user_id, start_time, end_time) do
    from(h in __MODULE__,
      where: h.user_id == ^user_id,
      where: h.inserted_at >= ^start_time,
      where: h.inserted_at <= ^end_time,
      order_by: [desc: h.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Cleans up old notification history (older than specified days).
  """
  @spec cleanup(integer()) :: {integer(), nil}
  def cleanup(days_to_keep \\ 30) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days_to_keep, :day)

    from(h in __MODULE__, where: h.inserted_at < ^cutoff)
    |> Repo.delete_all()
  end
end
