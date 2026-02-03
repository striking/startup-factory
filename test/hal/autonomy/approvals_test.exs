defmodule HAL.Autonomy.ApprovalsTest do
  use Hal.DataCase, async: true

  alias HAL.Autonomy.{ApprovalRequest, Approvals}
  alias Hal.Repo

  defp create_user!(attrs \\ %{}) do
    defaults = %{
      external_id: "approvals-test-user",
      platform: "terminal",
      username: "Approvals Test User",
      role: "owner"
    }

    %Hal.Accounts.User{}
    |> Hal.Accounts.User.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  test "request/4 creates a pending approval request" do
    user = create_user!()

    assert {:ok, req} =
             Approvals.request(user.id, "hal_delegate_to_codex", %{"task" => "Do the thing"}, %{
               "hal_session_id" => "session-123"
             })

    assert req.status == "pending"
    assert is_binary(req.token) and req.token != ""
    assert req.tool_name == "hal_delegate_to_codex"

    assert %ApprovalRequest{status: "pending"} = Approvals.get(req.token)
  end

  test "approve/1 marks a request approved" do
    user = create_user!()
    {:ok, req} = Approvals.request(user.id, "hal_delegate_to_codex", %{"task" => "Do the thing"})

    assert {:ok, approved} = Approvals.approve(req.token)
    assert approved.status == "approved"
    assert approved.approved_at != nil

    assert :approved = Approvals.validate_tool_token(req.token, "hal_delegate_to_codex")
  end

  test "deny/2 marks a request denied" do
    user = create_user!()
    {:ok, req} = Approvals.request(user.id, "hal_delegate_to_codex", %{"task" => "Do the thing"})
    token = req.token

    assert {:ok, denied} = Approvals.deny(token, "Nope")
    assert denied.status == "denied"
    assert denied.denied_at != nil
    assert denied.deny_reason == "Nope"

    assert {:denied, %ApprovalRequest{token: ^token}} =
             Approvals.validate_tool_token(token, "hal_delegate_to_codex")
  end

  test "tool execution requires approval for Codex delegation" do
    user = create_user!()

    assert {:error, %{type: :needs_approval, approval_token: token}} =
             Hal.Tools.Executor.execute("hal_delegate_to_codex", %{"task" => "Refactor X"},
               user_id: user.id
             )

    assert %ApprovalRequest{status: "pending", tool_name: "hal_delegate_to_codex"} =
             Approvals.get(token)

    assert {:ok, %ApprovalRequest{status: "approved"}} = Approvals.approve(token)

    assert :approved = Approvals.validate_tool_token(token, "hal_delegate_to_codex")

    assert 1 = Repo.aggregate(ApprovalRequest, :count, :id)
  end

  test "wait_for_resolution/2 returns approved even if PubSub delivery is missed" do
    user = create_user!()
    {:ok, req} = Approvals.request(user.id, "hal_delegate_to_codex", %{"task" => "Do the thing"})
    token = req.token

    Task.start(fn ->
      Process.sleep(50)

      req = Repo.get_by!(ApprovalRequest, token: token)

      req
      |> ApprovalRequest.changeset(%{status: "approved", approved_at: DateTime.utc_now()})
      |> Repo.update!()
    end)

    assert :approved = Approvals.wait_for_resolution(token, 200)
  end
end
