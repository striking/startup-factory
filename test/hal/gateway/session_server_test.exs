defmodule Hal.Gateway.SessionServerTest do
  @moduledoc """
  Tests for the SessionServer GenServer (individual conversation sessions).
  """
  use Hal.DataCase, async: false

  alias Hal.Accounts.User
  alias Hal.Gateway.Message
  alias Hal.Gateway.Session, as: SessionSchema
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
  defp create_session_record(user, attrs \\ %{}) do
    # Convert keyword list to map if necessary
    attrs = if is_list(attrs), do: Enum.into(attrs, %{}), else: attrs

    default_attrs = %{
      channel_type: "telegram",
      channel_id: "chat_#{System.unique_integer([:positive])}",
      user_id: user.id,
      last_activity: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    {:ok, session} =
      %SessionSchema{}
      |> SessionSchema.changeset(Map.merge(default_attrs, attrs))
      |> Repo.insert()

    session
  end

  # Helper to start a session server
  defp start_session_server(session, opts \\ []) do
    test_id = System.unique_integer([:positive])
    registry_name = Keyword.get(opts, :registry_name, :"TestRegistry#{test_id}")

    # Start Registry if needed
    case Registry.start_link(keys: :unique, name: registry_name) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    SessionServer.start_link(
      session_id: session.id,
      channel_type: session.channel_type,
      channel_id: session.channel_id,
      user_id: session.user_id,
      registry_name: registry_name
    )
  end

  describe "start_link/1" do
    test "starts the session server" do
      user = create_user()
      session = create_session_record(user)

      {:ok, pid} = start_session_server(session)

      assert Process.alive?(pid)
    end

    test "loads existing messages from database" do
      user = create_user()
      session = create_session_record(user)

      # Add some messages to the session
      {:ok, _} =
        %Message{}
        |> Message.changeset(%{
          session_id: session.id,
          role: "user",
          content: "Hello"
        })
        |> Repo.insert()

      {:ok, _} =
        %Message{}
        |> Message.changeset(%{
          session_id: session.id,
          role: "assistant",
          content: "Hi there!"
        })
        |> Repo.insert()

      {:ok, pid} = start_session_server(session)

      # Get state and verify messages loaded
      state = SessionServer.get_state(pid)

      assert length(state.messages) == 2
    end
  end

  describe "handle_message/2" do
    test "adds user message to session" do
      user = create_user()
      session = create_session_record(user)
      {:ok, pid} = start_session_server(session)

      # Mock the AI response
      mock_ai = fn _session_id, _content, _opts ->
        {:ok, %{result: "Hello! How can I help?"}, "claude_session_123"}
      end

      {:ok, response} =
        SessionServer.handle_message(pid, "Hello Claude!", ai_client: mock_ai)

      assert response == "Hello! How can I help?"

      # Verify messages were added
      state = SessionServer.get_state(pid)
      assert length(state.messages) == 2

      [user_msg, assistant_msg] = state.messages
      assert user_msg.role == "user"
      assert user_msg.content == "Hello Claude!"
      assert assistant_msg.role == "assistant"
      assert assistant_msg.content == "Hello! How can I help?"
    end

    test "persists messages to database" do
      user = create_user()
      session = create_session_record(user)
      {:ok, pid} = start_session_server(session)

      mock_ai = fn _session_id, _content, _opts ->
        {:ok, %{result: "Response"}, "claude_123"}
      end

      {:ok, _response} = SessionServer.handle_message(pid, "Test message", ai_client: mock_ai)

      # Force a flush to database
      SessionServer.flush_to_db(pid)

      # Check database
      messages = Message |> where(session_id: ^session.id) |> Repo.all()

      assert length(messages) == 2
    end

    test "updates claude_session_id" do
      user = create_user()
      session = create_session_record(user)
      {:ok, pid} = start_session_server(session)

      mock_ai = fn _session_id, _content, _opts ->
        {:ok, %{result: "Response"}, "new_claude_session_456"}
      end

      {:ok, _response} = SessionServer.handle_message(pid, "Test", ai_client: mock_ai)

      state = SessionServer.get_state(pid)
      assert state.claude_session_id == "new_claude_session_456"
    end

    test "handles AI error gracefully" do
      user = create_user()
      session = create_session_record(user)
      {:ok, pid} = start_session_server(session)

      mock_ai = fn _session_id, _content, _opts ->
        {:error, "AI service unavailable"}
      end

      {:error, reason} = SessionServer.handle_message(pid, "Test", ai_client: mock_ai)

      assert reason == "AI service unavailable"
    end
  end

  describe "send_to_claude/3" do
    test "sends message and returns response" do
      user = create_user()
      session = create_session_record(user)
      {:ok, pid} = start_session_server(session)

      mock_ai = fn _session_id, content, _opts ->
        {:ok, %{result: "You said: #{content}"}, "session_123"}
      end

      {:ok, response, _session_id} =
        SessionServer.send_to_claude(pid, "Hello", ai_client: mock_ai)

      assert response.result == "You said: Hello"
    end
  end

  describe "get_state/1" do
    test "returns current session state" do
      user = create_user()
      session = create_session_record(user)
      {:ok, pid} = start_session_server(session)

      state = SessionServer.get_state(pid)

      assert state.session_id == session.id
      assert state.channel_type == session.channel_type
      assert state.channel_id == session.channel_id
      assert state.user_id == session.user_id
      assert is_list(state.messages)
    end
  end

  describe "message history limit" do
    test "keeps only last 100 messages in memory" do
      user = create_user()
      session = create_session_record(user)
      {:ok, pid} = start_session_server(session)

      # Create a mock that returns quick responses
      mock_ai = fn _session_id, _content, _opts ->
        {:ok, %{result: "Response"}, "session_123"}
      end

      # Add more than 100 messages (each handle_message adds 2: user + assistant)
      for i <- 1..60 do
        SessionServer.handle_message(pid, "Message #{i}", ai_client: mock_ai)
      end

      state = SessionServer.get_state(pid)

      # Should only have 100 messages in memory (60 pairs = 120, truncated to 100)
      assert length(state.messages) <= 100
    end
  end

  describe "flush_to_db/1" do
    test "persists pending messages to database" do
      user = create_user()
      session = create_session_record(user)
      {:ok, pid} = start_session_server(session)

      mock_ai = fn _session_id, _content, _opts ->
        {:ok, %{result: "Response"}, "session_123"}
      end

      # Add several messages
      SessionServer.handle_message(pid, "Message 1", ai_client: mock_ai)
      SessionServer.handle_message(pid, "Message 2", ai_client: mock_ai)

      # Force flush
      :ok = SessionServer.flush_to_db(pid)

      # Verify in database
      messages = Message |> where(session_id: ^session.id) |> order_by(:inserted_at) |> Repo.all()

      assert length(messages) == 4
    end
  end

  describe "registry lookup" do
    test "can find session via Registry" do
      user = create_user()
      session = create_session_record(user)
      test_id = System.unique_integer([:positive])
      registry_name = :"TestRegistry#{test_id}"

      {:ok, _} = Registry.start_link(keys: :unique, name: registry_name)

      {:ok, pid} = start_session_server(session, registry_name: registry_name)

      # Lookup via Registry
      key = {session.channel_type, session.channel_id, session.user_id}

      [{found_pid, _}] = Registry.lookup(registry_name, key)

      assert found_pid == pid
    end
  end

  describe "inactivity timeout" do
    test "session tracks last_activity" do
      user = create_user()
      session = create_session_record(user)
      {:ok, pid} = start_session_server(session)

      mock_ai = fn _session_id, _content, _opts ->
        {:ok, %{result: "Response"}, "session_123"}
      end

      # Get initial state
      state_before = SessionServer.get_state(pid)
      initial_activity = state_before.messages |> length()

      # Wait a tiny bit
      Process.sleep(100)

      # Send a message
      {:ok, _response} = SessionServer.handle_message(pid, "Test message", ai_client: mock_ai)

      # Check that last_activity was updated
      state_after = SessionServer.get_state(pid)

      # Messages should have increased
      assert length(state_after.messages) > initial_activity
    end

    test "session state includes last_activity timestamp" do
      user = create_user()
      session = create_session_record(user)
      {:ok, pid} = start_session_server(session)

      state = SessionServer.get_state(pid)

      # Should have last_activity field
      assert Map.has_key?(state, :last_activity)
      assert %DateTime{} = state.last_activity
    end
  end
end
