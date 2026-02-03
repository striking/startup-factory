defmodule Hal.Accounts.User do
  @moduledoc """
  Schema representing a user across messaging platforms.

  Users are identified by their external platform ID (Telegram user_id, Slack user_id, etc.)
  combined with their platform type. This allows the same person to have separate user
  records per platform if needed.

  ## Fields

    * `external_id` - The unique identifier from the messaging platform
    * `platform` - The messaging platform (telegram, slack, discord)
    * `username` - Optional username/display name
    * `settings` - User-specific preferences stored as JSONB
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Hal.Gateway.Session

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_platforms ~w(telegram slack discord email terminal)
  @valid_roles ~w(owner user)

  schema "users" do
    field :external_id, :string
    field :platform, :string
    field :username, :string
    field :settings, :map, default: %{}
    field :paired_at, :utc_datetime
    field :role, :string, default: "user"

    has_many :sessions, Session

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new user.

  ## Required Fields
    * `external_id` - Platform-specific user identifier
    * `platform` - One of: telegram, slack, discord

  ## Optional Fields
    * `username` - Display name
    * `settings` - User preferences map
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:external_id, :platform, :username, :settings, :paired_at, :role])
    |> validate_required([:external_id, :platform, :role])
    |> validate_inclusion(:platform, @valid_platforms,
      message: "must be one of: #{Enum.join(@valid_platforms, ", ")}"
    )
    |> validate_inclusion(:role, @valid_roles,
      message: "must be one of: #{Enum.join(@valid_roles, ", ")}"
    )
    |> validate_length(:external_id, max: 255)
    |> validate_length(:username, max: 255)
    |> unique_constraint([:platform, :external_id],
      message: "user already exists for this platform"
    )
  end

  @doc """
  Returns the list of valid platforms.
  """
  def valid_platforms, do: @valid_platforms
end
