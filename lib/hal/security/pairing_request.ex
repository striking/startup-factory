defmodule Hal.Security.PairingRequest do
  @moduledoc """
  Persistent pairing request for inbound DM trust-gating.

  When DM policy is `:pairing`, new users are prompted with a pairing code.
  The operator approves/denies the request in the HAL UI.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending approved denied)

  schema "pairing_requests" do
    belongs_to :user, Hal.Accounts.User

    field :code, :string
    field :status, :string, default: "pending"

    field :approved_at, :utc_datetime
    field :denied_at, :utc_datetime
    field :deny_reason, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(request, attrs) do
    request
    |> cast(attrs, [:user_id, :code, :status, :approved_at, :denied_at, :deny_reason])
    |> validate_required([:user_id, :code, :status])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:code)
  end
end
