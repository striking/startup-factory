defmodule HAL.Autonomy.ApprovalRequest do
  @moduledoc """
  Persistent human-approval gate for high-impact actions.

  Approval requests are created when HAL wants to perform an action that
  should require explicit human confirmation (e.g., codops impacting actions).

  This is stored in Postgres so approvals survive restarts and can be reviewed
  in the LiveView UI.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending approved denied)
  @execution_statuses ~w(queued running completed failed)

  schema "approval_requests" do
    belongs_to :user, Hal.Accounts.User

    field :token, :string
    field :status, :string, default: "pending"

    field :tool_name, :string
    field :args, :map, default: %{}
    field :context, :map, default: %{}

    field :approved_at, :utc_datetime
    field :denied_at, :utc_datetime
    field :deny_reason, :string

    field :execution_status, :string
    field :executed_at, :utc_datetime
    field :execution_result, :map
    field :execution_error, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(request, attrs) do
    request
    |> cast(attrs, [
      :user_id,
      :token,
      :status,
      :tool_name,
      :args,
      :context,
      :approved_at,
      :denied_at,
      :deny_reason,
      :execution_status,
      :executed_at,
      :execution_result,
      :execution_error
    ])
    |> validate_required([:user_id, :token, :status, :tool_name])
    |> validate_inclusion(:status, @statuses)
    |> validate_change(:execution_status, fn
      :execution_status, nil -> []
      :execution_status, status when status in @execution_statuses -> []
      :execution_status, _ -> [execution_status: "is invalid"]
    end)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:token)
  end
end
