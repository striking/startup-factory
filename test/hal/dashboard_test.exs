defmodule Hal.DashboardTest do
  use Hal.DataCase, async: true

  alias Hal.Dashboard
  alias Hal.Accounts.User
  alias Hal.Gateway.{Session, Message}

  describe "list_active_sessions/1" do
    test "returns empty list when no sessions" do
      assert Dashboard.list_active_sessions() == []
    end

    test "returns active sessions ordered by last_activity desc" do
      {:ok, user} = create_user()

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      hour_ago = DateTime.add(now, -3600, :second)

      {:ok, old_session} = create_session(user, last_activity: hour_ago)
      {:ok, new_session} = create_session(user, last_activity: now)

      sessions = Dashboard.list_active_sessions()

      assert length(sessions) == 2
      assert hd(sessions).id == new_session.id
    end

    test "filters by channel_type" do
      {:ok, user} = create_user()
      {:ok, telegram} = create_session(user, channel_type: "telegram")
      {:ok, slack} = create_session(user, channel_type: "slack")

      sessions = Dashboard.list_active_sessions(channel_type: "telegram")

      assert length(sessions) == 1
      assert hd(sessions).channel_type == "telegram"
    end

    test "excludes non-active sessions" do
      {:ok, user} = create_user()
      {:ok, active} = create_session(user, status: "active")
      {:ok, archived} = create_session(user, status: "archived")

      sessions = Dashboard.list_active_sessions()

      assert length(sessions) == 1
      assert hd(sessions).status == "active"
    end

    test "respects limit option" do
      {:ok, user} = create_user()

      for _ <- 1..5 do
        create_session(user)
      end

      sessions = Dashboard.list_active_sessions(limit: 3)

      assert length(sessions) == 3
    end

    test "preloads user association" do
      {:ok, user} = create_user(username: "preload_test")
      {:ok, session} = create_session(user)

      [loaded_session] = Dashboard.list_active_sessions()

      assert loaded_session.user.username == "preload_test"
    end
  end

  describe "count_active_sessions/1" do
    test "returns 0 when no sessions" do
      assert Dashboard.count_active_sessions() == 0
    end

    test "counts active sessions" do
      {:ok, user} = create_user()
      create_session(user, status: "active")
      create_session(user, status: "active")
      create_session(user, status: "archived")

      assert Dashboard.count_active_sessions() == 2
    end

    test "filters by channel_type" do
      {:ok, user} = create_user()
      create_session(user, channel_type: "telegram")
      create_session(user, channel_type: "telegram")
      create_session(user, channel_type: "slack")

      assert Dashboard.count_active_sessions(channel_type: "telegram") == 2
    end
  end

  describe "count_sessions_by_channel/0" do
    test "returns empty map when no sessions" do
      assert Dashboard.count_sessions_by_channel() == %{}
    end

    test "returns counts grouped by channel" do
      {:ok, user} = create_user()
      create_session(user, channel_type: "telegram")
      create_session(user, channel_type: "telegram")
      create_session(user, channel_type: "slack")
      create_session(user, channel_type: "discord")

      counts = Dashboard.count_sessions_by_channel()

      assert counts["telegram"] == 2
      assert counts["slack"] == 1
      assert counts["discord"] == 1
    end
  end

  describe "get_session/1" do
    test "returns session with associations" do
      {:ok, user} = create_user()
      {:ok, session} = create_session(user)
      {:ok, message} = create_message(session)

      loaded = Dashboard.get_session(session.id)

      assert loaded.id == session.id
      assert loaded.user.id == user.id
      assert length(loaded.messages) == 1
    end

    test "returns nil for non-existent session" do
      assert Dashboard.get_session(Ecto.UUID.generate()) == nil
    end
  end

  describe "list_messages_for_session/2" do
    test "returns messages ordered by created_at asc" do
      {:ok, user} = create_user()
      {:ok, session} = create_session(user)

      {:ok, msg1} = create_message(session, content: "First")
      :timer.sleep(10)
      {:ok, msg2} = create_message(session, content: "Second")

      messages = Dashboard.list_messages_for_session(session.id)

      assert length(messages) == 2
      assert hd(messages).content == "First"
    end

    test "respects limit option" do
      {:ok, user} = create_user()
      {:ok, session} = create_session(user)

      for i <- 1..10 do
        create_message(session, content: "Message #{i}")
      end

      messages = Dashboard.list_messages_for_session(session.id, limit: 5)

      assert length(messages) == 5
    end
  end

  describe "count_messages_today/0" do
    test "returns 0 when no messages" do
      assert Dashboard.count_messages_today() == 0
    end

    test "counts messages from today" do
      {:ok, user} = create_user()
      {:ok, session} = create_session(user)

      create_message(session, content: "Today 1")
      create_message(session, content: "Today 2")

      assert Dashboard.count_messages_today() == 2
    end
  end

  describe "count_messages_for_session/1" do
    test "returns 0 for session with no messages" do
      {:ok, user} = create_user()
      {:ok, session} = create_session(user)

      assert Dashboard.count_messages_for_session(session.id) == 0
    end

    test "counts messages for specific session" do
      {:ok, user} = create_user()
      {:ok, session1} = create_session(user)
      {:ok, session2} = create_session(user)

      create_message(session1, content: "S1 M1")
      create_message(session1, content: "S1 M2")
      create_message(session2, content: "S2 M1")

      assert Dashboard.count_messages_for_session(session1.id) == 2
      assert Dashboard.count_messages_for_session(session2.id) == 1
    end
  end

  describe "get_stats/0" do
    test "returns stats map" do
      stats = Dashboard.get_stats()

      assert Map.has_key?(stats, :active_sessions)
      assert Map.has_key?(stats, :messages_today)
      assert Map.has_key?(stats, :channels_connected)
      assert Map.has_key?(stats, :total_messages)
      assert Map.has_key?(stats, :uptime)
    end

    test "returns correct counts" do
      {:ok, user} = create_user()
      {:ok, session} = create_session(user, channel_type: "telegram")
      create_message(session)

      stats = Dashboard.get_stats()

      assert stats.active_sessions == 1
      assert stats.messages_today == 1
      assert stats.channels_connected["telegram"] == 1
    end
  end

  describe "get_uptime/0" do
    test "returns formatted uptime string" do
      uptime = Dashboard.get_uptime()

      assert is_binary(uptime)
      # Should contain time indicators like s, m, h, d
      assert Regex.match?(~r/\d+[smhd]/, uptime)
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
      last_activity: attrs[:last_activity] || now,
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
