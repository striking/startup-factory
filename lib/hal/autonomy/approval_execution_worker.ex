defmodule HAL.Autonomy.ApprovalExecutionWorker do
  @moduledoc """
  Executes approved, high-impact tool requests durably via Oban.

  This turns the human approval step into a durable queue:
  - Tool call creates an `approval_requests` row (pending)
  - Human approves (status=approved)
  - We enqueue this worker to execute the tool call

  Execution is idempotent via `HAL.Autonomy.Approvals.claim_execution/1`.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  require Logger

  alias HAL.Autonomy.{ApprovalRequest, Approvals}
  alias Hal.Repo
  alias Hal.Tools.Executor, as: ToolExecutor

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"token" => token}}) when is_binary(token) do
    case Repo.get_by(ApprovalRequest, token: token) do
      nil ->
        Logger.warning("ApprovalExecutionWorker: token not found: #{token}")
        :discard

      %ApprovalRequest{status: "denied"} ->
        :discard

      %ApprovalRequest{status: "pending"} ->
        # Shouldn't happen (we enqueue on approve) but be robust.
        {:snooze, 5}

      %ApprovalRequest{status: "approved", tool_name: tool_name} = req ->
        case Approvals.claim_execution(token) do
          :claimed ->
            args =
              req.args
              |> ensure_map()
              |> Map.put("approval_token", token)

            opts =
              [user_id: req.user_id]
              |> maybe_put(:session_id, get_ctx(req.context, "session_id"))
              |> maybe_put(:channel_type, get_ctx(req.context, "channel_type"))
              |> maybe_put(:channel_id, get_ctx(req.context, "channel_id"))
              |> Keyword.put(:approval_already_claimed, true)

            case ToolExecutor.execute(tool_name, args, opts) do
              {:ok, _} -> :ok
              {:error, _} -> {:error, :tool_failed}
            end

          :already_claimed ->
            :ok

          :not_found ->
            :discard
        end
    end
  end

  def perform(_job), do: :discard

  defp ensure_map(nil), do: %{}
  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_), do: %{}

  defp get_ctx(context, key) when is_map(context) do
    Map.get(context, key) || Map.get(context, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(context, key)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
