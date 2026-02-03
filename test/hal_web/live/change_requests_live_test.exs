defmodule HalWeb.ChangeRequestsLiveTest do
  use HalWeb.LiveViewCase, async: true

  alias HAL.SelfImprovement.ChangeRequests
  alias Hal.Repo

  defp create_owner!(attrs \\ %{}) do
    defaults = %{
      external_id: "changes-live-test-user",
      platform: "terminal",
      username: "Changes Live Test User",
      role: "owner"
    }

    %Hal.Accounts.User{}
    |> Hal.Accounts.User.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  test "renders recent change requests", %{conn: conn} do
    user = create_owner!()

    {:ok, req} =
      ChangeRequests.create(user.id, %{
        title: "Add Changes UI",
        request: "Create a changes UI page",
        status: "pending"
      })

    {:ok, _view, html} = live(conn, ~p"/changes")
    assert html =~ "Changes"
    assert html =~ req.title
    assert html =~ req.id
  end
end
