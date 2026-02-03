defmodule HalWeb.SessionDetailLiveTest do
  use HalWeb.LiveViewCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Hal.Accounts.User
  alias Hal.Gateway.{Session, Message}
  alias Hal.Repo

  describe "SessionDetailLive" do
    test "renders session details", %{conn: conn} do
      {:ok, user} = create_user(username: "detail_test_user")
      {:ok, session} = create_session(user)

      {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}")

      assert html =~ "detail_test_user"
      assert html =~ "Telegram"
      assert html =~ session.channel_id
      assert html =~ "Conversation"
    end

    test "displays session statistics", %{conn: conn} do
      {:ok, user} = create_user()
      {:ok, session} = create_session(user)

      # Create some messages
      create_message(session, role: "user", content: "Hello")
      create_message(session, role: "assistant", content: "Hi there!")
      create_message(session, role: "user", content: "How are you?")

      {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}")

      # Should show message count
      assert html =~ "3"
      assert html =~ "Messages"
    end

    test "displays messages in chat format", %{conn: conn} do
      {:ok, user} = create_user()
      {:ok, session} = create_session(user)

      create_message(session, role: "user", content: "What is 2 + 2?")
      create_message(session, role: "assistant", content: "2 + 2 equals 4.")

      {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}")

      assert html =~ "What is 2 + 2?"
      assert html =~ "2 + 2 equals 4."
      assert html =~ "You"
      assert html =~ "HAL"
    end

    test "displays empty state when no messages", %{conn: conn} do
      {:ok, user} = create_user()
      {:ok, session} = create_session(user)

      {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}")

      assert html =~ "No messages yet"
      assert html =~ "Messages will appear here"
    end

    test "redirects to sessions list when session not found", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      {:error, {:live_redirect, %{to: path, flash: flash}}} = live(conn, ~p"/sessions/#{fake_id}")

      assert path == "/sessions"
      assert flash["error"] == "Session not found"
    end

    test "displays back link to sessions list", %{conn: conn} do
      {:ok, user} = create_user()
      {:ok, session} = create_session(user)

      {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}")

      assert html =~ "Back to sessions"
      assert html =~ "/sessions"
    end

    test "shows session status badge", %{conn: conn} do
      {:ok, user} = create_user()
      {:ok, session} = create_session(user, status: "active")

      {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}")

      assert html =~ "Active"
    end

    test "displays system messages with different styling", %{conn: conn} do
      {:ok, user} = create_user()
      {:ok, session} = create_session(user)

      create_message(session, role: "system", content: "Session started")
      create_message(session, role: "user", content: "Hello")

      {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}")

      assert html =~ "Session started"
      assert html =~ "System"
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
      status: attrs[:status] || "active"
    }

    %Session{}
    |> Session.changeset(Map.merge(default_attrs, Map.new(attrs)))
    |> Repo.insert()
  end

  defp create_message(session, attrs \\ []) do
    default_attrs = %{
      session_id: session.id,
      role: attrs[:role] || "user",
      content: attrs[:content] || "Test message"
    }

    %Message{}
    |> Message.changeset(Map.merge(default_attrs, Map.new(attrs)))
    |> Repo.insert()
  end
end
