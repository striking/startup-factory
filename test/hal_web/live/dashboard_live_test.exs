defmodule HalWeb.DashboardLiveTest do
  use HalWeb.LiveViewCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Hal.Accounts.User
  alias Hal.Gateway.Session
  alias Hal.Repo

  describe "DashboardLive" do
    test "renders dashboard with empty state", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Dashboard"
      assert html =~ "Monitor your HAL assistant"
      assert html =~ "No active sessions"
    end

    test "displays stats panel", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Active Sessions"
      assert html =~ "Messages Today"
      assert html =~ "Channels Connected"
      assert html =~ "System Uptime"
    end

    test "displays active sessions when present", %{conn: conn} do
      # Create a user and session
      {:ok, user} = create_user()
      {:ok, _session} = create_session(user)

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ user.username
      assert html =~ "Telegram"
    end

    test "filters sessions by channel type", %{conn: conn} do
      {:ok, user} = create_user()
      {:ok, _telegram_session} = create_session(user, channel_type: "telegram")
      {:ok, slack_session} = create_session(user, channel_type: "slack")

      {:ok, view, _html} = live(conn, ~p"/")

      # Filter by telegram
      html =
        view
        |> element("select[name='channel']")
        |> render_change(%{channel: "telegram"})

      assert html =~ "Telegram"
      # Should not show slack when filtered
      refute html =~ slack_session.channel_id
    end

    test "searches sessions", %{conn: conn} do
      {:ok, user1} = create_user(username: "alice_test")
      {:ok, user2} = create_user(username: "bob_test")
      {:ok, _session1} = create_session(user1)
      {:ok, _session2} = create_session(user2)

      {:ok, view, _html} = live(conn, ~p"/")

      # Search for alice
      html =
        view
        |> element("form")
        |> render_change(%{query: "alice"})

      assert html =~ "alice_test"
      refute html =~ "bob_test"
    end

    test "navigates to session detail on click", %{conn: conn} do
      {:ok, user} = create_user()
      {:ok, session} = create_session(user)

      {:ok, view, _html} = live(conn, ~p"/")

      # Click the session card - use role="button" selector since phx-click is JSON encoded
      view
      |> element("[role='button'][aria-label*='View session']")
      |> render_click()

      # Should redirect to session detail
      assert_redirect(view, "/sessions/#{session.id}")
    end
  end

  # Helper functions

  defp create_user(attrs \\ []) do
    default_attrs = %{
      external_id: "ext_#{:rand.uniform(100_000)}",
      platform: attrs[:platform] || "telegram",
      username: attrs[:username] || "testuser_#{:rand.uniform(1000)}"
    }

    %User{}
    |> User.changeset(Map.merge(default_attrs, Map.new(attrs)))
    |> Repo.insert()
  end

  defp create_session(user, attrs \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    default_attrs = %{
      channel_type: attrs[:channel_type] || "telegram",
      channel_id: "chat_#{:rand.uniform(100_000)}",
      user_id: user.id,
      last_activity: now,
      status: "active"
    }

    %Session{}
    |> Session.changeset(Map.merge(default_attrs, Map.new(attrs)))
    |> Repo.insert()
  end
end
