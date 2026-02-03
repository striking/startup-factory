defmodule HAL.Autonomy.Approvals do
  @moduledoc """
  Human approval workflow for high-impact actions.

  This module is used by the tool execution layer to gate codops-impacting
  actions behind an explicit approval step, and by the LiveView UI to list,
  approve, or deny pending requests.
  """

  import Ecto.Query, only: [from: 2]

  alias HAL.Autonomy.ApprovalRequest
  alias HAL.Autonomy.ApprovalExecutionWorker
  alias HAL.EventLog
  alias Hal.Repo

  @type token :: String.t()

  @pubsub Hal.PubSub
  @topic_prefix "approvals:"

  defp topic(token) when is_binary(token), do: @topic_prefix <> token

  @doc """
  Wait for an approval token to be resolved.

  Returns:
  - `:approved`
  - `{:denied, req}`
  - `:timeout`
  - `:not_found`
  """
  @spec wait_for_resolution(token(), pos_integer()) ::
          :approved | {:denied, ApprovalRequest.t()} | :timeout | :not_found
  def wait_for_resolution(token, timeout_ms \\ 120_000)
      when is_binary(token) and is_integer(timeout_ms) and timeout_ms > 0 do
    case get(token) do
      nil ->
        :not_found

      %ApprovalRequest{status: "approved"} ->
        :approved

      %ApprovalRequest{status: "denied"} = req ->
        {:denied, req}

      %ApprovalRequest{status: "pending"} ->
        Phoenix.PubSub.subscribe(@pubsub, topic(token))

        # Avoid a race where approval is resolved between our initial `get/1`
        # and the PubSub subscription.
        case get(token) do
          nil ->
            :not_found

          %ApprovalRequest{status: "approved"} ->
            :approved

          %ApprovalRequest{status: "denied"} = req ->
            {:denied, req}

          %ApprovalRequest{status: "pending"} ->
            receive do
              {:approval_resolved, ^token, "approved"} ->
                :approved

              {:approval_resolved, ^token, "denied"} ->
                case get(token) do
                  %ApprovalRequest{} = req -> {:denied, req}
                  nil -> :not_found
                end
            after
              timeout_ms ->
                # If PubSub delivery was missed, fall back to persisted state.
                case get(token) do
                  nil -> :not_found
                  %ApprovalRequest{status: "approved"} -> :approved
                  %ApprovalRequest{status: "denied"} = req -> {:denied, req}
                  _ -> :timeout
                end
            end
        end
    end
  end

  @doc """
  Create a pending approval request.
  """
  @spec request(Ecto.UUID.t(), String.t(), map(), map()) ::
          {:ok, ApprovalRequest.t()} | {:error, Ecto.Changeset.t()}
  def request(user_id, tool_name, args, context \\ %{}) when is_map(args) and is_map(context) do
    token = generate_token()

    %ApprovalRequest{}
    |> ApprovalRequest.changeset(%{
      user_id: user_id,
      token: token,
      status: "pending",
      tool_name: tool_name,
      args: args,
      context: context
    })
    |> Repo.insert()
    |> case do
      {:ok, req} = ok ->
        EventLog.log(:approval_requested, %{
          token: req.token,
          tool_name: tool_name,
          user_id: user_id
        })

        ok

      other ->
        other
    end
  end

  @doc """
  Fetch an approval request by token.
  """
  @spec get(token()) :: ApprovalRequest.t() | nil
  def get(token) when is_binary(token) do
    Repo.get_by(ApprovalRequest, token: token)
  end

  @doc """
  Approve a pending request.
  """
  @spec approve(token()) :: {:ok, ApprovalRequest.t()} | {:error, :not_found | :not_pending}
  def approve(token) when is_binary(token) do
    case get(token) do
      nil ->
        {:error, :not_found}

      %ApprovalRequest{status: "approved"} = req ->
        maybe_enqueue_execution(req)
        {:ok, req}

      %ApprovalRequest{status: "denied"} ->
        {:error, :not_pending}

      %ApprovalRequest{status: "pending"} = req ->
        execution_status = if auto_execute_enabled?(), do: "queued", else: nil

        req
        |> ApprovalRequest.changeset(%{
          status: "approved",
          approved_at: DateTime.utc_now(),
          execution_status: execution_status,
          execution_error: nil
        })
        |> Repo.update()
        |> case do
          {:ok, updated} = ok ->
            EventLog.log(:approval_approved, %{
              token: updated.token,
              tool_name: updated.tool_name,
              user_id: updated.user_id
            })

            Phoenix.PubSub.broadcast(
              @pubsub,
              topic(updated.token),
              {:approval_resolved, updated.token, updated.status}
            )

            maybe_enqueue_execution(updated)

            ok

          other ->
            other
        end
    end
  end

  @doc """
  Deny a pending request.
  """
  @spec deny(token(), String.t()) ::
          {:ok, ApprovalRequest.t()} | {:error, :not_found | :not_pending}
  def deny(token, reason \\ "Denied by user") when is_binary(token) do
    case get(token) do
      nil ->
        {:error, :not_found}

      %ApprovalRequest{status: "approved"} ->
        {:error, :not_pending}

      %ApprovalRequest{status: "denied"} = req ->
        {:ok, req}

      %ApprovalRequest{status: "pending"} = req ->
        req
        |> ApprovalRequest.changeset(%{
          status: "denied",
          denied_at: DateTime.utc_now(),
          deny_reason: reason
        })
        |> Repo.update()
        |> case do
          {:ok, updated} = ok ->
            EventLog.log(:approval_denied, %{
              token: updated.token,
              tool_name: updated.tool_name,
              user_id: updated.user_id,
              reason: updated.deny_reason
            })

            Phoenix.PubSub.broadcast(
              @pubsub,
              topic(updated.token),
              {:approval_resolved, updated.token, updated.status}
            )

            ok

          other ->
            other
        end
    end
  end

  @doc """
  List pending approvals (newest first).
  """
  @spec list_pending(keyword()) :: [ApprovalRequest.t()]
  def list_pending(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(r in ApprovalRequest,
      where: r.status == "pending",
      order_by: [desc: r.inserted_at],
      limit: ^limit,
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  List recently approved approvals that are queued/running/failed (newest first).
  """
  @spec list_queue(keyword()) :: [ApprovalRequest.t()]
  def list_queue(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(r in ApprovalRequest,
      where: r.status == "approved" and r.execution_status in ["queued", "running", "failed"],
      order_by: [desc: r.approved_at],
      limit: ^limit,
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  List recently executed approvals (completed/failed), newest first.

  Useful for UI visibility so successful executions don't "disappear" instantly.
  """
  @spec list_recent_executions(keyword()) :: [ApprovalRequest.t()]
  def list_recent_executions(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(r in ApprovalRequest,
      where: r.status == "approved" and not is_nil(r.executed_at),
      order_by: [desc: r.executed_at],
      limit: ^limit,
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  Claim an approved approval request for execution.

  This prevents double execution when both:
  - an interactive tool call is waiting on approval, and
  - the durable Oban job is enqueued on approval.
  """
  @spec claim_execution(token()) :: :claimed | :already_claimed | :not_found
  def claim_execution(token) when is_binary(token) do
    {updated, _} =
      from(r in ApprovalRequest,
        where:
          r.token == ^token and r.status == "approved" and
            (is_nil(r.execution_status) or r.execution_status in ["queued"])
      )
      |> Repo.update_all(set: [execution_status: "running", execution_error: nil])

    cond do
      updated == 1 ->
        case get(token) do
          %ApprovalRequest{} = req ->
            EventLog.log(:approval_execution_started, %{
              token: token,
              tool_name: req.tool_name,
              user_id: req.user_id
            })

          _ ->
            :ok
        end

        :claimed

      is_nil(get(token)) ->
        :not_found

      true ->
        :already_claimed
    end
  end

  @doc """
  Mark an approval execution completed (stores result for inspection).
  """
  @spec mark_execution_completed(token(), map()) :: :ok
  def mark_execution_completed(token, result) when is_binary(token) and is_map(result) do
    req = get(token)

    from(r in ApprovalRequest, where: r.token == ^token)
    |> Repo.update_all(
      set: [
        execution_status: "completed",
        executed_at: DateTime.utc_now(),
        execution_result: result,
        execution_error: nil
      ]
    )

    if %ApprovalRequest{} = req do
      EventLog.log(:approval_execution_completed, %{
        token: token,
        tool_name: req.tool_name,
        user_id: req.user_id
      })
    end

    :ok
  end

  @doc """
  Mark an approval execution failed (stores error for inspection).
  """
  @spec mark_execution_failed(token(), map()) :: :ok
  def mark_execution_failed(token, error) when is_binary(token) and is_map(error) do
    req = get(token)

    from(r in ApprovalRequest, where: r.token == ^token)
    |> Repo.update_all(
      set: [
        execution_status: "failed",
        executed_at: DateTime.utc_now(),
        execution_error: Map.get(error, :error) || Map.get(error, "error") || inspect(error),
        execution_result: error
      ]
    )

    if %ApprovalRequest{} = req do
      EventLog.log(:approval_execution_failed, %{
        token: token,
        tool_name: req.tool_name,
        user_id: req.user_id
      })
    end

    :ok
  end

  @doc """
  Validate a token for a tool call.

  Returns:
  - `:approved` if the token exists and is approved
  - `{:needs_approval, req}` if pending
  - `{:denied, req}` if denied
  - `:not_found` if token is invalid
  - `{:mismatch, req}` if token exists but tool doesn't match
  """
  @spec validate_tool_token(token(), String.t()) ::
          :approved
          | {:needs_approval, ApprovalRequest.t()}
          | {:denied, ApprovalRequest.t()}
          | :not_found
          | {:mismatch, ApprovalRequest.t()}
  def validate_tool_token(token, tool_name) when is_binary(token) and is_binary(tool_name) do
    case get(token) do
      nil ->
        :not_found

      %ApprovalRequest{tool_name: ^tool_name, status: "approved"} ->
        :approved

      %ApprovalRequest{tool_name: ^tool_name, status: "pending"} = req ->
        {:needs_approval, req}

      %ApprovalRequest{tool_name: ^tool_name, status: "denied"} = req ->
        {:denied, req}

      %ApprovalRequest{} = req ->
        {:mismatch, req}
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp auto_execute_enabled? do
    Application.get_env(:hal, __MODULE__, [])
    |> Keyword.get(:auto_execute, true)
  end

  defp maybe_enqueue_execution(%ApprovalRequest{token: token} = req) do
    if auto_execute_enabled?() do
      job =
        ApprovalExecutionWorker.new(%{"token" => token},
          unique: [fields: [:args, :queue, :worker], keys: [:token], period: 60 * 60 * 24 * 30]
        )

      case Oban.insert(job) do
        {:ok, _job} ->
          EventLog.log(:approval_execution_enqueued, %{
            token: req.token,
            tool_name: req.tool_name,
            user_id: req.user_id
          })

        {:error, reason} ->
          from(r in ApprovalRequest, where: r.token == ^token)
          |> Repo.update_all(
            set: [
              execution_status: "failed",
              execution_error: "Failed to enqueue Oban job: #{inspect(reason)}"
            ]
          )

          EventLog.log(:approval_execution_enqueue_failed, %{
            token: req.token,
            tool_name: req.tool_name,
            user_id: req.user_id,
            reason: inspect(reason)
          })
      end
    end

    :ok
  end
end
