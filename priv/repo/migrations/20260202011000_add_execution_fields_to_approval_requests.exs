defmodule Hal.Repo.Migrations.AddExecutionFieldsToApprovalRequests do
  use Ecto.Migration

  def change do
    alter table(:approval_requests) do
      add :execution_status, :string
      add :executed_at, :utc_datetime
      add :execution_result, :map
      add :execution_error, :text
    end

    create index(:approval_requests, [:execution_status])
    create index(:approval_requests, [:executed_at])
  end
end
