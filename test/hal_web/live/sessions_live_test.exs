defmodule HalWeb.SessionsLiveTest do
  use HalWeb.LiveViewCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Hal.Accounts.User
  alias Hal.Gateway.Session
  alias Hal.Repo

  describe "SessionsLive" do
    test "renders sessions list with empty state", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/sessions")

      assert html =~ "Sessions"
      assert html =~ "View and manage all conversation sessions"
      assert html =~ "No sessions found"
    end

    test "displays sessions in a grid", %{conn: conn} do
      # Create multiple sessions
      {:ok, user} = create_user()
      {:ok, _session1} = create_session(user, channel_type: "telegram")
      {:ok, _session2} = create_session(user, channel_type: "slack")
      {:ok, _session3} = create_session(user, channel_type: "discord")

      {:ok, _view, html} = live(conn, ~p"/sessions")

      assert html =~ "Telegram"
      assert html =~ "Slack"
      assert html =~ "Discord"
      assert html =~ "Showing 3 of 3 sessions"
    end

    test "filters by channel type via URL params", %{conn: conn} do
      {:ok, user} = create_user()
      {:ok, _telegram} = create_session(user, channel_type: "telegram")
      {:ok, _slack} = create_session(user, channel_type: "slack")

      {:ok, _view, html} = live(conn, ~p"/sessions?channel=telegram")

      assert html =~ "Telegram"
      assert html =~ "Showing 1 of 1 sessions"
    end

    test "filters by channel type via select", %{conn: conn} do
      {:ok, user} = create_user()
      {:ok, _telegram} = create_session(user, channel_type: "telegram")
      {:ok, _slack} = create_session(user, channel_type: "slack")

      {:ok, view, _html} = live(conn, ~p"/sessions")

      html =
        view
        |> element("select[name='channel']")
        |> render_change(%{channel: "slack"})

      # Check that URL was patched (order of params may vary)
      path = assert_patch(view)
      assert path =~ "/sessions?"
      assert path =~ "channel=slack"
      assert path =~ "page=1"
    end

    test "searches sessions by query", %{conn: conn} do
      {:ok, user1} = create_user(username: "search_alice")
      {:ok, user2} = create_user(username: "search_bob")
      {:ok, _session1} = create_session(user1)
      {:ok, _session2} = create_session(user2)

      {:ok, view, _html} = live(conn, ~p"/sessions")

      html =
        view
        |> element("form")
        |> render_change(%{query: "alice"})

      # Check that URL was patched with search (order of params may vary)
      path = assert_patch(view)
      assert path =~ "/sessions?"
      assert path =~ "search=alice"
    end

    test "paginates sessions", %{conn: conn} do
      {:ok, user} = create_user()

      # Create more than 20 sessions (default page size)
      for i <- 1..25 do
        create_session(user, channel_id: "chat_#{i}")
      end

      {:ok, _view, html} = live(conn, ~p"/sessions")

      assert html =~ "Showing 20 of 25 sessions"
      # Page numbers are wrapped in span tags, so check individually
      assert html =~ "Page"
      assert html =~ ">1<"
      assert html =~ "of"
      assert html =~ ">2<"
      assert html =~ "Next"
    end

    test "navigates to next page", %{conn: conn} do
      {:ok, user} = create_user()

      for i <- 1..25 do
        create_session(user, channel_id: "chat_#{i}")
      end

      {:ok, view, _html} = live(conn, ~p"/sessions")

      # Click next page
      view
      |> element("a", "Next")
      |> render_click()

      # Check that URL was patched (order of params may vary)
      path = assert_patch(view)
      assert path =~ "/sessions?"
      assert path =~ "page=2"
    end

    test "navigates to session detail on card click", %{conn: conn} do
      {:ok, user} = create_user()
      {:ok, session} = create_session(user)

      {:ok, view, _html} = live(conn, ~p"/sessions")

      # Click the session card - use role="button" selector since phx-click is JSON encoded
      view
      |> element("[role='button'][aria-label*='View session']")
      |> render_click()

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
      channel_id: attrs[:channel_id] || "chat_#{:rand.uniform(100_000)}",
      user_id: user.id,
      last_activity: now,
      status: "active"
    }

    %Session{}
    |> Session.changeset(Map.merge(default_attrs, Map.new(attrs)))
    |> Repo.insert()
  end
end
