defmodule Hal.Gateway.SessionCleanerTest do
  @moduledoc """
  Tests for the SessionCleaner GenServer that handles archived session cleanup.

  The SessionCleaner is responsible for:
  - Running periodic cleanup every hour
  - Finding sessions with status = "archived" AND updated_at > 7 days
  - Stopping associated SessionServer GenServers gracefully
  - Deleting archived sessions from the database
  """
  use Hal.DataCase, async: false

  alias Hal.Accounts.User
  alias Hal.Gateway.Session, as: SessionSchema
  alias Hal.Gateway.SessionCleaner
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

  # Helper to create a test session in DB
  defp create_session_record(user, attrs) do
    default_attrs = %{
      channel_type: "telegram",
      channel_id: "chat_#{System.unique_integer([:positive])}",
      user_id: user.id,
      last_activity: DateTime.utc_now() |> DateTime.truncate(:second),
      status: "active"
    }

    merged_attrs = Map.merge(default_attrs, attrs)

    changeset = SessionSchema.changeset(%SessionSchema{}, merged_attrs)

    # If inserted_at or updated_at are provided, force them (truncate to second precision)
    changeset =
      if Map.has_key?(attrs, :inserted_at) do
        truncated = DateTime.truncate(attrs.inserted_at, :second)
        Ecto.Changeset.force_change(changeset, :inserted_at, truncated)
      else
        changeset
      end

    changeset =
      if Map.has_key?(attrs, :updated_at) do
        truncated = DateTime.truncate(attrs.updated_at, :second)
        Ecto.Changeset.force_change(changeset, :updated_at, truncated)
      else
        changeset
      end

    {:ok, session} = Repo.insert(changeset)

    session
  end

  # Helper to start a session server with registry
  defp start_session_server(session, registry_name) do
    SessionServer.start_link(
      session_id: session.id,
      channel_type: session.channel_type,
      channel_id: session.channel_id,
      user_id: session.user_id,
      registry_name: registry_name
    )
  end

  # Helper to create a unique registry for each test
  defp start_test_registry do
    registry_name = :"TestRegistry#{System.unique_integer([:positive])}"
    {:ok, _} = Registry.start_link(keys: :unique, name: registry_name)
    registry_name
  end

  describe "start_link/1" do
    test "starts the SessionCleaner GenServer" do
      registry_name = start_test_registry()

      {:ok, pid} =
        SessionCleaner.start_link(
          name: :"cleaner_#{System.unique_integer([:positive])}",
          registry_name: registry_name
        )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "accepts configurable grace period" do
      registry_name = start_test_registry()

      # 3 day grace period
      {:ok, pid} =
        SessionCleaner.start_link(
          name: :"cleaner_#{System.unique_integer([:positive])}",
          registry_name: registry_name,
          grace_period_days: 3
        )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "cleanup_archived_sessions/0" do
    test "deletes archived sessions older than grace period (7 days)" do
      registry_name = start_test_registry()
      user = create_user()

      # Create an archived session that is 8 days old (should be deleted)
      old_time = DateTime.add(DateTime.utc_now(), -8, :day)

      old_session =
        create_session_record(user, %{
          last_activity: old_time,
          status: "archived",
          inserted_at: old_time,
          updated_at: old_time
        })

      {:ok, pid} =
        SessionCleaner.start_link(
          name: :"cleaner_#{System.unique_integer([:positive])}",
          registry_name: registry_name
        )

      # Trigger cleanup manually
      result = SessionCleaner.cleanup_now(pid)

      assert {:ok, stats} = result
      assert stats.deleted_count >= 1

      # Verify session was deleted from database
      deleted_session = Repo.get(SessionSchema, old_session.id)
      assert is_nil(deleted_session)

      GenServer.stop(pid)
    end

    test "does not delete archived sessions within grace period" do
      registry_name = start_test_registry()
      user = create_user()

      # Create an archived session that is only 3 days old (should NOT be deleted)
      recent_time = DateTime.add(DateTime.utc_now(), -3, :day)

      recent_session =
        create_session_record(user, %{
          last_activity: recent_time,
          status: "archived",
          inserted_at: recent_time,
          updated_at: recent_time
        })

      {:ok, pid} =
        SessionCleaner.start_link(
          name: :"cleaner_#{System.unique_integer([:positive])}",
          registry_name: registry_name
        )

      # Trigger cleanup manually
      {:ok, stats} = SessionCleaner.cleanup_now(pid)

      # Should not have deleted this session
      assert stats.deleted_count == 0

      # Verify session still exists
      existing_session = Repo.get(SessionSchema, recent_session.id)
      assert existing_session.status == "archived"

      GenServer.stop(pid)
    end

    test "stops SessionServer GenServers for deleted sessions" do
      registry_name = start_test_registry()
      user = create_user()

      # Create an archived session that is 8 days old
      old_time = DateTime.add(DateTime.utc_now(), -8, :day)

      old_session =
        create_session_record(user, %{
          last_activity: old_time,
          status: "archived",
          inserted_at: old_time,
          updated_at: old_time
        })

      # Start a SessionServer for this session
      {:ok, session_pid} = start_session_server(old_session, registry_name)
      assert Process.alive?(session_pid)

      {:ok, cleaner_pid} =
        SessionCleaner.start_link(
          name: :"cleaner_#{System.unique_integer([:positive])}",
          registry_name: registry_name
        )

      # Trigger cleanup
      {:ok, stats} = SessionCleaner.cleanup_now(cleaner_pid)

      assert stats.servers_stopped >= 1

      # Give the GenServer time to stop
      Process.sleep(100)

      # Verify the session server was stopped
      refute Process.alive?(session_pid)

      GenServer.stop(cleaner_pid)
    end

    test "handles missing SessionServer gracefully" do
      registry_name = start_test_registry()
      user = create_user()

      # Create an archived session that is 8 days old, but no GenServer running
      old_time = DateTime.add(DateTime.utc_now(), -8, :day)

      old_session =
        create_session_record(user, %{
          last_activity: old_time,
          status: "archived",
          inserted_at: old_time,
          updated_at: old_time
        })

      {:ok, pid} =
        SessionCleaner.start_link(
          name: :"cleaner_#{System.unique_integer([:positive])}",
          registry_name: registry_name
        )

      # Should not crash when there's no GenServer to stop
      {:ok, stats} = SessionCleaner.cleanup_now(pid)

      assert stats.deleted_count >= 1
      assert stats.servers_stopped == 0

      # Verify session was still deleted
      deleted_session = Repo.get(SessionSchema, old_session.id)
      assert is_nil(deleted_session)

      GenServer.stop(pid)
    end

    test "respects configurable grace period" do
      registry_name = start_test_registry()
      user = create_user()

      # Create an archived session that is 4 days old
      four_days_ago = DateTime.add(DateTime.utc_now(), -4, :day)

      session =
        create_session_record(user, %{
          last_activity: four_days_ago,
          status: "archived",
          inserted_at: four_days_ago,
          updated_at: four_days_ago
        })

      # Start cleaner with 3 day grace period
      {:ok, pid} =
        SessionCleaner.start_link(
          name: :"cleaner_#{System.unique_integer([:positive])}",
          registry_name: registry_name,
          grace_period_days: 3
        )

      # Trigger cleanup
      {:ok, _stats} = SessionCleaner.cleanup_now(pid)

      # Session should be deleted (it's 4 days old, grace period is 3 days)
      deleted_session = Repo.get(SessionSchema, session.id)
      assert is_nil(deleted_session)

      GenServer.stop(pid)
    end

    test "only deletes sessions with archived status" do
      registry_name = start_test_registry()
      user = create_user()

      # Create an active session that is 8 days old
      old_time = DateTime.add(DateTime.utc_now(), -8, :day)

      active_session =
        create_session_record(user, %{
          last_activity: old_time,
          status: "active",
          inserted_at: old_time,
          updated_at: old_time
        })

      {:ok, pid} =
        SessionCleaner.start_link(
          name: :"cleaner_#{System.unique_integer([:positive])}",
          registry_name: registry_name
        )

      {:ok, stats} = SessionCleaner.cleanup_now(pid)

      # Should not have deleted this session (it's not "archived")
      assert stats.deleted_count == 0

      # Session should still exist
      existing_session = Repo.get(SessionSchema, active_session.id)
      assert existing_session.status == "active"

      GenServer.stop(pid)
    end
  end

  describe "periodic cleanup via handle_info" do
    test "schedules periodic cleanup" do
      registry_name = start_test_registry()

      # Use a very short interval for testing (100ms)
      {:ok, pid} =
        SessionCleaner.start_link(
          name: :"cleaner_#{System.unique_integer([:positive])}",
          registry_name: registry_name,
          cleanup_interval_ms: 100
        )

      # Create an archived session older than grace period
      user = create_user()
      old_time = DateTime.add(DateTime.utc_now(), -8, :day)

      old_session =
        create_session_record(user, %{
          last_activity: old_time,
          status: "archived",
          inserted_at: old_time,
          updated_at: old_time
        })

      # Wait for periodic cleanup to run
      Process.sleep(200)

      # Verify session was deleted by the periodic cleanup
      deleted_session = Repo.get(SessionSchema, old_session.id)
      assert is_nil(deleted_session)

      GenServer.stop(pid)
    end
  end

  describe "get_stats/1" do
    test "returns cleanup statistics" do
      registry_name = start_test_registry()

      {:ok, pid} =
        SessionCleaner.start_link(
          name: :"cleaner_#{System.unique_integer([:positive])}",
          registry_name: registry_name
        )

      stats = SessionCleaner.get_stats(pid)

      assert is_map(stats)
      assert Map.has_key?(stats, :last_cleanup_at)
      assert Map.has_key?(stats, :total_deleted)
      assert Map.has_key?(stats, :total_servers_stopped)
      assert Map.has_key?(stats, :cleanup_count)

      GenServer.stop(pid)
    end
  end
end
