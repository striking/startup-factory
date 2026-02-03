defmodule Hal.Gateway.SessionManagerTest do
  @moduledoc """
  Tests for the SessionManager GenServer.
  """
  use Hal.DataCase, async: false

  alias Hal.Accounts.User
  alias Hal.Gateway.Session, as: SessionSchema
  alias Hal.Gateway.SessionManager

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

  # Helper to create test infrastructure
  defp start_test_infrastructure do
    test_id = System.unique_integer([:positive])

    registry_name = :"TestRegistry#{test_id}"
    supervisor_name = :"TestDynamicSupervisor#{test_id}"
    session_manager_name = :"TestSessionManager#{test_id}"

    # Start Registry
    {:ok, _} = Registry.start_link(keys: :unique, name: registry_name)

    # Start DynamicSupervisor
    {:ok, _} = DynamicSupervisor.start_link(strategy: :one_for_one, name: supervisor_name)

    # Start SessionManager
    {:ok, session_manager_pid} =
      SessionManager.start_link(
        name: session_manager_name,
        registry_name: registry_name,
        dynamic_supervisor_name: supervisor_name
      )

    %{
      session_manager: session_manager_pid,
      session_manager_name: session_manager_name,
      registry_name: registry_name,
      supervisor_name: supervisor_name
    }
  end

  describe "start_link/1" do
    test "starts the session manager" do
      infra = start_test_infrastructure()
      assert Process.alive?(infra.session_manager)
    end
  end

  describe "get_or_create_session/4" do
    test "creates a new session when none exists" do
      infra = start_test_infrastructure()
      user = create_user()

      {:ok, session_pid} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "chat_123",
          user.id
        )

      assert is_pid(session_pid)
      assert Process.alive?(session_pid)
    end

    test "returns existing session when one exists" do
      infra = start_test_infrastructure()
      user = create_user()

      {:ok, session_pid1} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "chat_123",
          user.id
        )

      {:ok, session_pid2} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "chat_123",
          user.id
        )

      assert session_pid1 == session_pid2
    end

    test "creates different sessions for different channels" do
      infra = start_test_infrastructure()
      user = create_user()

      {:ok, session_pid1} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "chat_123",
          user.id
        )

      {:ok, session_pid2} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "chat_456",
          user.id
        )

      assert session_pid1 != session_pid2
    end

    test "creates different sessions for different platforms" do
      infra = start_test_infrastructure()
      user = create_user()

      {:ok, session_pid1} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "chat_123",
          user.id
        )

      {:ok, session_pid2} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "slack",
          "chat_123",
          user.id
        )

      assert session_pid1 != session_pid2
    end

    test "persists session to database" do
      infra = start_test_infrastructure()
      user = create_user()

      {:ok, _session_pid} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "chat_789",
          user.id
        )

      # Check database
      session =
        SessionSchema
        |> where(channel_type: "telegram", channel_id: "chat_789", user_id: ^user.id)
        |> Repo.one()

      assert session != nil
      assert session.status == "active"
    end
  end

  describe "list_sessions/1" do
    test "returns empty list when no sessions" do
      infra = start_test_infrastructure()

      sessions = SessionManager.list_sessions(infra.session_manager_name)
      assert sessions == []
    end

    test "returns list of active session PIDs" do
      infra = start_test_infrastructure()
      user = create_user()

      {:ok, session_pid1} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "chat_1",
          user.id
        )

      {:ok, session_pid2} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "chat_2",
          user.id
        )

      sessions = SessionManager.list_sessions(infra.session_manager_name)

      assert length(sessions) == 2
      assert session_pid1 in sessions
      assert session_pid2 in sessions
    end
  end

  describe "get_session/4" do
    test "returns nil when session doesn't exist" do
      infra = start_test_infrastructure()
      user = create_user()

      result =
        SessionManager.get_session(
          infra.session_manager_name,
          "telegram",
          "nonexistent",
          user.id
        )

      assert result == nil
    end

    test "returns session PID when it exists" do
      infra = start_test_infrastructure()
      user = create_user()

      {:ok, session_pid} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "chat_123",
          user.id
        )

      result =
        SessionManager.get_session(
          infra.session_manager_name,
          "telegram",
          "chat_123",
          user.id
        )

      assert result == session_pid
    end
  end

  describe "session recovery after crash" do
    test "recreates session from database after crash" do
      infra = start_test_infrastructure()
      user = create_user()

      # Create session
      {:ok, session_pid1} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "crash_test",
          user.id
        )

      # Kill the session
      Process.exit(session_pid1, :kill)
      Process.sleep(50)

      # Request session again - should recreate from DB
      {:ok, session_pid2} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "crash_test",
          user.id
        )

      assert session_pid2 != session_pid1
      assert Process.alive?(session_pid2)
    end
  end
end
