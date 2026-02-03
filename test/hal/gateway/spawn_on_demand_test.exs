defmodule Hal.Gateway.SpawnOnDemandTest do
  @moduledoc """
  Integration tests for spawn-on-demand session management.

  These tests verify that:
  1. Sessions spawn on-demand when first message arrives
  2. Sessions reuse existing process if already spawned
  3. Session state persists to database
  4. Sessions can be re-spawned after termination with state intact
  """
  use Hal.DataCase, async: false

  alias Hal.Accounts.User
  alias Hal.Gateway.Session, as: SessionSchema
  alias Hal.Gateway.SessionManager
  alias Hal.Gateway.SessionServer

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

  describe "spawn-on-demand behavior" do
    test "session spawns on first message and reuses on second" do
      infra = start_test_infrastructure()
      user = create_user()

      # Initially, no session exists
      assert SessionManager.get_session(
               infra.session_manager_name,
               "telegram",
               "spawn_test_1",
               user.id
             ) == nil

      # First message spawns the session
      {:ok, session_pid1} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "spawn_test_1",
          user.id
        )

      assert Process.alive?(session_pid1)

      # Second message reuses the same session
      {:ok, session_pid2} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "spawn_test_1",
          user.id
        )

      assert session_pid1 == session_pid2
    end

    test "session state persists to database and can be recovered" do
      infra = start_test_infrastructure()
      user = create_user()

      # Mock AI client
      mock_ai = fn _session_id, _content, _opts ->
        {:ok, %{result: "Hello! How can I help?"}, "claude_session_123"}
      end

      # Spawn session and send a message
      {:ok, session_pid} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "persist_test",
          user.id
        )

      {:ok, _response} =
        SessionServer.handle_message(session_pid, "Hello Claude!", ai_client: mock_ai)

      # Force flush to database
      SessionServer.flush_to_db(session_pid)

      # Get session ID for verification
      state = SessionServer.get_state(session_pid)
      session_id = state.session_id

      # Verify session and messages are in database
      session_record = Repo.get(SessionSchema, session_id)
      assert session_record != nil
      assert session_record.claude_session_id == "claude_session_123"

      # Kill the session process
      Process.exit(session_pid, :kill)
      Process.sleep(50)

      # Re-spawn the session
      {:ok, new_session_pid} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "persist_test",
          user.id
        )

      assert new_session_pid != session_pid
      assert Process.alive?(new_session_pid)

      # Verify the new session loaded the message history
      new_state = SessionServer.get_state(new_session_pid)
      assert new_state.session_id == session_id
      assert length(new_state.messages) == 2
    end

    test "no sessions pre-spawned on startup" do
      infra = start_test_infrastructure()
      user = create_user()

      # Create some sessions in the database
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      %SessionSchema{}
      |> SessionSchema.changeset(%{
        channel_type: "telegram",
        channel_id: "pre_spawn_test_1",
        user_id: user.id,
        last_activity: now,
        status: "active"
      })
      |> Repo.insert!()

      %SessionSchema{}
      |> SessionSchema.changeset(%{
        channel_type: "telegram",
        channel_id: "pre_spawn_test_2",
        user_id: user.id,
        last_activity: now,
        status: "active"
      })
      |> Repo.insert!()

      # Verify no sessions are spawned automatically
      sessions = SessionManager.list_sessions(infra.session_manager_name)
      assert sessions == []

      # But we can still get_or_create them on demand
      {:ok, pid1} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "pre_spawn_test_1",
          user.id
        )

      {:ok, pid2} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "pre_spawn_test_2",
          user.id
        )

      assert Process.alive?(pid1)
      assert Process.alive?(pid2)

      # Now we have 2 active sessions
      sessions = SessionManager.list_sessions(infra.session_manager_name)
      assert length(sessions) == 2
    end
  end

  describe "memory scaling" do
    test "active session count reflects actual spawned processes" do
      infra = start_test_infrastructure()
      user = create_user()

      # Start with no sessions
      assert SessionManager.list_sessions(infra.session_manager_name) == []

      # Spawn 3 sessions
      {:ok, _pid1} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "chat_1",
          user.id
        )

      {:ok, _pid2} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "chat_2",
          user.id
        )

      {:ok, _pid3} =
        SessionManager.get_or_create_session(
          infra.session_manager_name,
          "telegram",
          "chat_3",
          user.id
        )

      # Should have exactly 3 active sessions
      sessions = SessionManager.list_sessions(infra.session_manager_name)
      assert length(sessions) == 3
    end
  end
end
