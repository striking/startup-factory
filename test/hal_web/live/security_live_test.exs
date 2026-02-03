defmodule HalWeb.SecurityLiveTest do
  use HalWeb.LiveViewCase, async: true

  alias Hal.Repo
  alias Hal.Security.PairingRequest

  defp create_user!(attrs \\ %{}) do
    defaults = %{
      external_id: "security-live-test-user",
      platform: "telegram",
      username: "Security Live Test User"
    }

    %Hal.Accounts.User{}
    |> Hal.Accounts.User.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp create_pairing_request!(user, attrs \\ %{}) do
    defaults = %{
      user_id: user.id,
      code: "TEST-PAIR",
      status: "pending"
    }

    %PairingRequest{}
    |> PairingRequest.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  test "lists pending pairings and allows approving in the UI", %{conn: conn} do
    user = create_user!()
    req = create_pairing_request!(user, %{code: "ABCD-EFGH"})

    {:ok, view, html} = live(conn, ~p"/security")
    assert html =~ req.code
    assert html =~ "Pending Pairings"

    view
    |> element("button[phx-click=\"approve_pairing\"][phx-value-code=\"#{req.code}\"]")
    |> render_click()

    assert render(view) =~ "Approved pairing #{req.code}"
    assert render(view) =~ "No pending pairing requests"
  end
end
