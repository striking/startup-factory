defmodule HAL.Integration.MessageFlowTest do
  @moduledoc """
  Integration tests for the complete message flow through HAL.

  Tests the full journey: Channel -> Gateway -> AI Provider -> Response

  These tests require external services (Claude Code CLI, Telegram API, etc.)
  and should only be run manually in a configured environment.

  Run with: mix test test/integration/message_flow_test.exs --include integration
  """

  use Hal.DataCase, async: false

  alias Hal.Accounts.User
  alias Hal.Gateway.{Router, Session, SessionManager, SessionServer}
  alias Hal.AI.ClaudeCode

  @moduletag :integration
  @moduletag timeout: 180_000

  setup do
    # Create a test user
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        external_id: "integration_test_user_#{System.unique_integer([:positive])}",
        platform: "telegram",
        username: "integration_test"
      })
      |> Repo.insert()

    # Create a test session record
    {:ok, session} =
      %Session{}
      |> Session.changeset(%{
        channel_type: "telegram",
        channel_id: "integration_chat_#{System.unique_integer([:positive])}",
        user_id: user.id,
        last_activity: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    %{user: user, session: session}
  end

  describe "end-to-end message flow" do
    @tag :slow
    test "message flows from channel through gateway to AI and back", %{session: session} do
      # Start a session server
      {:ok, session_pid} =
        SessionServer.start_link(
          session_id: session.id,
          channel_type: session.channel_type,
          channel_id: session.channel_id,
          user_id: session.user_id
        )

      # Send a simple message and verify AI response
      {:ok, response} =
        SessionServer.handle_message(session_pid, "What is 2 + 2? Reply with just the number.")

      # Verify we got a response
      assert is_binary(response)
      assert String.contains?(response, "4")

      # Verify messages were persisted
      state = SessionServer.get_state(session_pid)
      assert length(state.messages) >= 2

      # Verify session has claude_session_id set
      assert state.claude_session_id != nil
    end

    @tag :slow
    test "session maintains context across multiple messages", %{session: session} do
      {:ok, session_pid} =
        SessionServer.start_link(
          session_id: session.id,
          channel_type: session.channel_type,
          channel_id: session.channel_id,
          user_id: session.user_id
        )

      # First message - establish context
      {:ok, _response1} =
        SessionServer.handle_message(
          session_pid,
          "Remember the word 'elephant'. Just say OK."
        )

      # Second message - test context retention
      {:ok, response2} =
        SessionServer.handle_message(
          session_pid,
          "What word did I ask you to remember? Just say the word."
        )

      assert String.downcase(response2) =~ "elephant"
    end

    @tag :slow
    test "router correctly routes to Claude Code for coding tasks", %{session: session} do
      # Use mock to track which provider is called
      provider_called = :counters.new(1, [:atomics])

      mock_provider = fn provider, _session_id, _message, _opts ->
        case provider do
          :claude_code ->
            :counters.add(provider_called, 1, 1)
            {:ok, "Code written", "session-123"}

          _ ->
            {:ok, "Other response", nil}
        end
      end

      {:ok, _response, _session_id, provider} =
        Router.route("Write a function that adds two numbers",
          provider_caller: mock_provider,
          session_id: nil
        )

      assert provider == :claude_code
      assert :counters.get(provider_called, 1) == 1
    end
  end

  describe "message persistence" do
    test "messages are persisted to database after session flush", %{session: session} do
      {:ok, session_pid} =
        SessionServer.start_link(
          session_id: session.id,
          channel_type: session.channel_type,
          channel_id: session.channel_id,
          user_id: session.user_id
        )

      # Add message with mock AI
      mock_ai = fn _session_id, _content, _opts ->
        {:ok, %{result: "Test response"}, "mock_session_123"}
      end

      {:ok, _response} =
        SessionServer.handle_message(session_pid, "Test message", ai_client: mock_ai)

      # Force flush
      :ok = SessionServer.flush_to_db(session_pid)

      # Verify in database
      import Ecto.Query
      messages = Hal.Gateway.Message |> where(session_id: ^session.id) |> Repo.all()

      assert length(messages) == 2
      assert Enum.any?(messages, &(&1.role == "user" and &1.content == "Test message"))
      assert Enum.any?(messages, &(&1.role == "assistant" and &1.content == "Test response"))
    end
  end

  describe "error handling" do
    test "handles AI provider errors gracefully", %{session: session} do
      {:ok, session_pid} =
        SessionServer.start_link(
          session_id: session.id,
          channel_type: session.channel_type,
          channel_id: session.channel_id,
          user_id: session.user_id
        )

      # Mock AI that returns an error
      mock_ai = fn _session_id, _content, _opts ->
        {:error, "Simulated API failure"}
      end

      {:error, reason} =
        SessionServer.handle_message(session_pid, "Test message", ai_client: mock_ai)

      assert reason == "Simulated API failure"

      # Session should still be running
      assert Process.alive?(session_pid)
    end
  end
end
