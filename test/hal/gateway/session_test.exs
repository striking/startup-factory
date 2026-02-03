defmodule Hal.Gateway.SessionTest do
  use Hal.DataCase, async: true

  alias Hal.Accounts.User
  alias Hal.Gateway.Session

  # Helper to create a test user
  defp create_user(attrs \\ %{}) do
    default_attrs = %{
      external_id: "test_user_#{System.unique_integer([:positive])}",
      platform: "telegram"
    }

    {:ok, user} =
      %User{}
      |> User.changeset(Map.merge(default_attrs, attrs))
      |> Repo.insert()

    user
  end

  describe "changeset/2" do
    test "valid changeset with required fields" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        channel_type: "telegram",
        channel_id: "chat_123",
        user_id: user.id,
        last_activity: now
      }

      changeset = Session.changeset(%Session{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :channel_type) == "telegram"
      assert get_change(changeset, :channel_id) == "chat_123"
      # default applied at DB level
      assert get_change(changeset, :status) == nil
    end

    test "valid changeset with all fields" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        channel_type: "slack",
        channel_id: "C12345",
        user_id: user.id,
        claude_session_id: "claude_sess_abc123",
        settings: %{"model" => "claude-3-opus", "max_tokens" => 4096},
        metadata: %{"thread_ts" => "1234567890.123456"},
        last_activity: now,
        status: "active"
      }

      changeset = Session.changeset(%Session{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :claude_session_id) == "claude_sess_abc123"

      assert get_change(changeset, :settings) == %{
               "model" => "claude-3-opus",
               "max_tokens" => 4096
             }
    end

    test "invalid changeset without channel_type" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        channel_id: "chat_123",
        user_id: user.id,
        last_activity: now
      }

      changeset = Session.changeset(%Session{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).channel_type
    end

    test "invalid changeset without channel_id" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        channel_type: "telegram",
        user_id: user.id,
        last_activity: now
      }

      changeset = Session.changeset(%Session{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).channel_id
    end

    test "invalid changeset without user_id" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        channel_type: "telegram",
        channel_id: "chat_123",
        last_activity: now
      }

      changeset = Session.changeset(%Session{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).user_id
    end

    test "invalid changeset without last_activity" do
      user = create_user()

      attrs = %{
        channel_type: "telegram",
        channel_id: "chat_123",
        user_id: user.id
      }

      changeset = Session.changeset(%Session{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).last_activity
    end

    test "invalid changeset with invalid channel_type" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        channel_type: "whatsapp",
        channel_id: "chat_123",
        user_id: user.id,
        last_activity: now
      }

      changeset = Session.changeset(%Session{}, attrs)

      refute changeset.valid?

      assert "must be one of: telegram, slack, discord, terminal" in errors_on(changeset).channel_type
    end

    test "invalid changeset with invalid status" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        channel_type: "telegram",
        channel_id: "chat_123",
        user_id: user.id,
        last_activity: now,
        status: "deleted"
      }

      changeset = Session.changeset(%Session{}, attrs)

      refute changeset.valid?
      assert "must be one of: active, paused, archived, expired" in errors_on(changeset).status
    end

    test "accepts all valid channel types" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for channel_type <- Session.valid_channel_types() do
        attrs = %{
          channel_type: channel_type,
          channel_id: "test_123",
          user_id: user.id,
          last_activity: now
        }

        changeset = Session.changeset(%Session{}, attrs)
        assert changeset.valid?, "Expected #{channel_type} to be valid"
      end
    end

    test "accepts all valid statuses" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for status <- Session.valid_statuses() do
        attrs = %{
          channel_type: "telegram",
          channel_id: "test_#{status}",
          user_id: user.id,
          last_activity: now,
          status: status
        }

        changeset = Session.changeset(%Session{}, attrs)
        assert changeset.valid?, "Expected status #{status} to be valid"
      end
    end
  end

  describe "activity_changeset/2" do
    test "updates last_activity" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      later = DateTime.add(now, 3600, :second)

      {:ok, session} =
        %Session{}
        |> Session.changeset(%{
          channel_type: "telegram",
          channel_id: "chat_123",
          user_id: user.id,
          last_activity: now
        })
        |> Repo.insert()

      changeset = Session.activity_changeset(session, %{last_activity: later})

      assert changeset.valid?
      assert get_change(changeset, :last_activity) == later
    end

    test "can update claude_session_id" do
      session = %Session{last_activity: DateTime.utc_now()}

      changeset =
        Session.activity_changeset(session, %{
          last_activity: DateTime.utc_now(),
          claude_session_id: "new_session_id"
        })

      assert changeset.valid?
      assert get_change(changeset, :claude_session_id) == "new_session_id"
    end
  end

  describe "status_changeset/2" do
    test "updates status to paused" do
      session = %Session{status: "active"}

      changeset = Session.status_changeset(session, %{status: "paused"})

      assert changeset.valid?
      assert get_change(changeset, :status) == "paused"
    end

    test "rejects invalid status" do
      session = %Session{status: "active"}

      changeset = Session.status_changeset(session, %{status: "invalid"})

      refute changeset.valid?
      assert "must be one of: active, paused, archived, expired" in errors_on(changeset).status
    end
  end

  describe "database operations" do
    test "can insert a session" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        channel_type: "telegram",
        channel_id: "chat_123",
        user_id: user.id,
        last_activity: now
      }

      {:ok, session} = %Session{} |> Session.changeset(attrs) |> Repo.insert()

      assert session.id
      assert session.channel_type == "telegram"
      assert session.channel_id == "chat_123"
      assert session.user_id == user.id
      assert session.status == "active"
      assert session.settings == %{}
      assert session.metadata == %{}
    end

    test "enforces foreign key constraint on user_id" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      fake_user_id = Ecto.UUID.generate()

      attrs = %{
        channel_type: "telegram",
        channel_id: "chat_123",
        user_id: fake_user_id,
        last_activity: now
      }

      {:error, changeset} = %Session{} |> Session.changeset(attrs) |> Repo.insert()

      assert "does not exist" in errors_on(changeset).user_id
    end

    test "cascades delete when user is deleted" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, session} =
        %Session{}
        |> Session.changeset(%{
          channel_type: "telegram",
          channel_id: "chat_123",
          user_id: user.id,
          last_activity: now
        })
        |> Repo.insert()

      # Delete the user
      Repo.delete!(user)

      # Session should be deleted too
      assert Repo.get(Session, session.id) == nil
    end

    test "can preload user association" do
      user = create_user(%{username: "testuser"})
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, session} =
        %Session{}
        |> Session.changeset(%{
          channel_type: "telegram",
          channel_id: "chat_123",
          user_id: user.id,
          last_activity: now
        })
        |> Repo.insert()

      session_with_user = Session |> Repo.get!(session.id) |> Repo.preload(:user)

      assert session_with_user.user.id == user.id
      assert session_with_user.user.username == "testuser"
    end

    test "can query sessions by channel" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} =
        %Session{}
        |> Session.changeset(%{
          channel_type: "telegram",
          channel_id: "chat_1",
          user_id: user.id,
          last_activity: now
        })
        |> Repo.insert()

      {:ok, _} =
        %Session{}
        |> Session.changeset(%{
          channel_type: "telegram",
          channel_id: "chat_2",
          user_id: user.id,
          last_activity: now
        })
        |> Repo.insert()

      {:ok, _} =
        %Session{}
        |> Session.changeset(%{
          channel_type: "slack",
          channel_id: "channel_1",
          user_id: user.id,
          last_activity: now
        })
        |> Repo.insert()

      telegram_sessions = Session |> where(channel_type: "telegram") |> Repo.all()
      slack_sessions = Session |> where(channel_type: "slack") |> Repo.all()

      assert length(telegram_sessions) == 2
      assert length(slack_sessions) == 1
    end
  end

  describe "valid_channel_types/0" do
    test "returns expected channel types" do
      types = Session.valid_channel_types()

      assert "telegram" in types
      assert "slack" in types
      assert "discord" in types
      assert "terminal" in types
      assert length(types) == 4
    end
  end

  describe "valid_statuses/0" do
    test "returns expected statuses" do
      statuses = Session.valid_statuses()

      assert "active" in statuses
      assert "paused" in statuses
      assert "archived" in statuses
      assert "expired" in statuses
      assert length(statuses) == 4
    end
  end
end
