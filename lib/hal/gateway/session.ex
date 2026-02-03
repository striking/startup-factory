defmodule Hal.Gateway.Session do
  @moduledoc """
  Schema representing a conversation session.

  Each session represents a unique conversation context, identified by the combination
  of channel_type (telegram, slack, discord, terminal), channel_id (chat_id, channel_id, etc.),
  and user_id. Sessions maintain continuity with Claude Code via the claude_session_id.

  ## Fields

    * `channel_type` - The messaging platform (telegram, slack, discord, terminal)
    * `channel_id` - Platform-specific conversation identifier (chat_id, thread_ts, etc.)
    * `user_id` - Reference to the User who owns this session
    * `claude_session_id` - Claude Code session ID for continuity (--resume flag)
    * `settings` - Session-specific settings (model preferences, allowed tools, etc.)
    * `metadata` - Additional session metadata (context, tags, etc.)
    * `last_activity` - Timestamp of last message activity
    * `status` - Session status: active, paused, archived, expired
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Hal.Accounts.User
  alias Hal.Gateway.Message

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_channel_types ~w(telegram slack discord terminal)
  @valid_statuses ~w(active paused archived expired)

  schema "sessions" do
    field :channel_type, :string
    field :channel_id, :string
    field :claude_session_id, :string
    field :settings, :map, default: %{}
    field :metadata, :map, default: %{}
    field :last_activity, :utc_datetime
    field :status, :string, default: "active"

    belongs_to :user, User
    has_many :messages, Message

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new session.

  ## Required Fields
    * `channel_type` - One of: telegram, slack, discord, terminal
    * `channel_id` - Platform-specific conversation identifier
    * `user_id` - Reference to the owning user
    * `last_activity` - Initial activity timestamp

  ## Optional Fields
    * `claude_session_id` - Claude Code session ID
    * `settings` - Session preferences
    * `metadata` - Additional metadata
    * `status` - Session status (defaults to "active")
  """
  @cast_fields [
    :channel_type,
    :channel_id,
    :user_id,
    :claude_session_id,
    :settings,
    :metadata,
    :last_activity,
    :status
  ]

  def changeset(session, attrs) do
    session
    |> cast(attrs, @cast_fields)
    |> validate_required([:channel_type, :channel_id, :user_id, :last_activity])
    |> validate_inclusion(:channel_type, @valid_channel_types,
      message: "must be one of: #{Enum.join(@valid_channel_types, ", ")}"
    )
    |> validate_inclusion(:status, @valid_statuses,
      message: "must be one of: #{Enum.join(@valid_statuses, ", ")}"
    )
    |> validate_length(:channel_id, max: 255)
    |> validate_length(:claude_session_id, max: 255)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for updating session activity.
  Used when a new message is received to update last_activity timestamp.
  """
  def activity_changeset(session, attrs) do
    session
    |> cast(attrs, [:last_activity, :claude_session_id, :metadata])
    |> validate_required([:last_activity])
  end

  @doc """
  Changeset for updating session status.
  """
  def status_changeset(session, attrs) do
    session
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @valid_statuses,
      message: "must be one of: #{Enum.join(@valid_statuses, ", ")}"
    )
  end

  @doc """
  Returns the list of valid channel types.
  """
  def valid_channel_types, do: @valid_channel_types

  @doc """
  Returns the list of valid statuses.
  """
  def valid_statuses, do: @valid_statuses
end
