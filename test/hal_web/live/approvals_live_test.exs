defmodule HalWeb.ApprovalsLiveTest do
  use HalWeb.LiveViewCase, async: true

  alias HAL.Autonomy.Approvals
  alias Hal.Repo

  defp create_user!(attrs \\ %{}) do
    defaults = %{
      external_id: "approvals-live-test-user",
      platform: "terminal",
      username: "Approvals Live Test User",
      role: "owner"
    }

    %Hal.Accounts.User{}
    |> Hal.Accounts.User.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  test "lists pending approvals and allows approving in the UI", %{conn: conn} do
    user = create_user!()

    {:ok, req} =
      Approvals.request(user.id, "hal_delegate_to_codex", %{"task" => "Create foo.txt"})

    {:ok, view, html} = live(conn, ~p"/approvals")
    assert html =~ req.token
    assert html =~ "Pending"

    view
    |> element("button[phx-click=\"approve\"][phx-value-token=\"#{req.token}\"]")
    |> render_click()

    assert render(view) =~ "Approved #{req.token}"
    assert render(view) =~ "No pending approvals"
  end
end
