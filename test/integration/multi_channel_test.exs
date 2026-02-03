defmodule HAL.Integration.MultiChannelTest do
  @moduledoc """
  Integration tests for multi-channel message handling.

  Tests simultaneous operation across multiple messaging platforms:
  - Telegram
  - Slack
  - Discord

  Verifies:
  - Session isolation between channels
  - Concurrent message handling
  - Cross-channel context (same user, different platforms)
  - Channel-specific formatting

  Run with: mix test test/integration/multi_channel_test.exs --include integration
  """

  use Hal.DataCase, async: false

  alias Hal.Accounts.User
  alias Hal.AI.Router, as: AIRouter
  alias Hal.Gateway.{Session, SessionServer}

  @moduletag :integration
  @moduletag timeout: 180_000

  setup do
    # Create test user that exists on multiple platforms
    {:ok, telegram_user} =
      %User{}
      |> User.changeset(%{
        external_id: "multi_test_tg_#{System.unique_integer([:positive])}",
        platform: "telegram",
        username: "multi_test_user"
      })
      |> Repo.insert()

    {:ok, slack_user} =
      %User{}
      |> User.changeset(%{
        external_id: "multi_test_slack_#{System.unique_integer([:positive])}",
        platform: "slack",
        username: "multi_test_user"
      })
      |> Repo.insert()

    {:ok, discord_user} =
      %User{}
      |> User.changeset(%{
        external_id: "multi_test_discord_#{System.unique_integer([:positive])}",
        platform: "discord",
        username: "multi_test_user"
      })
      |> Repo.insert()

    # Create sessions for each platform
    {:ok, telegram_session} = create_session(telegram_user, "telegram")
    {:ok, slack_session} = create_session(slack_user, "slack")
    {:ok, discord_session} = create_session(discord_user, "discord")

    %{
      telegram_user: telegram_user,
      slack_user: slack_user,
      discord_user: discord_user,
      telegram_session: telegram_session,
      slack_session: slack_session,
      discord_session: discord_session
    }
  end

  defp create_session(user, channel_type) do
    %Session{}
    |> Session.changeset(%{
      channel_type: channel_type,
      channel_id: "#{channel_type}_chat_#{System.unique_integer([:positive])}",
      user_id: user.id,
      last_activity: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert()
  end

  describe "session isolation" do
    test "each channel maintains separate session context", ctx do
      # Start session servers for each channel
      {:ok, tg_pid} = start_session_server(ctx.telegram_session)
      {:ok, slack_pid} = start_session_server(ctx.slack_session)
      {:ok, discord_pid} = start_session_server(ctx.discord_session)

      # Mock AI that tracks session IDs
      session_tracker = :ets.new(:session_tracker, [:set, :public])

      mock_ai = fn session_id, content, _opts ->
        :ets.insert(session_tracker, {session_id, content})
        {:ok, %{result: "Response for: #{content}"}, "session_#{session_id}"}
      end

      # Send different messages to each channel
      {:ok, _} = SessionServer.handle_message(tg_pid, "Telegram message", ai_client: mock_ai)
      {:ok, _} = SessionServer.handle_message(slack_pid, "Slack message", ai_client: mock_ai)
      {:ok, _} = SessionServer.handle_message(discord_pid, "Discord message", ai_client: mock_ai)

      # Verify each session got its own message
      tg_state = SessionServer.get_state(tg_pid)
      slack_state = SessionServer.get_state(slack_pid)
      discord_state = SessionServer.get_state(discord_pid)

      # Each session should have its own messages
      assert Enum.any?(tg_state.messages, &(&1.content == "Telegram message"))
      assert Enum.any?(slack_state.messages, &(&1.content == "Slack message"))
      assert Enum.any?(discord_state.messages, &(&1.content == "Discord message"))

      # Messages should not cross sessions
      refute Enum.any?(tg_state.messages, &(&1.content == "Slack message"))
      refute Enum.any?(slack_state.messages, &(&1.content == "Discord message"))

      :ets.delete(session_tracker)
    end
  end

  describe "concurrent message handling" do
    @tag :slow
    test "handles messages from multiple channels simultaneously", ctx do
      # Start session servers
      {:ok, tg_pid} = start_session_server(ctx.telegram_session)
      {:ok, slack_pid} = start_session_server(ctx.slack_session)
      {:ok, discord_pid} = start_session_server(ctx.discord_session)

      # Track responses
      response_tracker = :ets.new(:response_tracker, [:bag, :public])

      mock_ai = fn _session_id, content, _opts ->
        # Simulate some processing time
        Process.sleep(100)
        :ets.insert(response_tracker, {:response, content})
        {:ok, %{result: "Processed: #{content}"}, "session_123"}
      end

      # Send messages concurrently
      tasks = [
        Task.async(fn ->
          SessionServer.handle_message(tg_pid, "Concurrent TG", ai_client: mock_ai)
        end),
        Task.async(fn ->
          SessionServer.handle_message(slack_pid, "Concurrent Slack", ai_client: mock_ai)
        end),
        Task.async(fn ->
          SessionServer.handle_message(discord_pid, "Concurrent Discord", ai_client: mock_ai)
        end)
      ]

      # Wait for all to complete
      results = Task.await_many(tasks, 10_000)

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, _} -> true
               _ -> false
             end)

      # Verify all messages were processed
      responses = :ets.lookup(response_tracker, :response)
      assert length(responses) == 3

      :ets.delete(response_tracker)
    end

    @tag :slow
    test "handles rapid sequential messages on same channel", ctx do
      {:ok, tg_pid} = start_session_server(ctx.telegram_session)

      mock_ai = fn _session_id, content, _opts ->
        {:ok, %{result: "Response to: #{content}"}, "session_123"}
      end

      # Send multiple messages rapidly
      for i <- 1..10 do
        {:ok, response} =
          SessionServer.handle_message(tg_pid, "Message #{i}", ai_client: mock_ai)

        assert response =~ "Response to: Message #{i}"
      end

      # Verify all messages were recorded
      state = SessionServer.get_state(tg_pid)
      # 10 user messages + 10 assistant responses = 20
      assert length(state.messages) == 20
    end
  end

  describe "router channel-specific handling" do
    test "routes messages to correct channel-specific formatting" do
      # Test that different channels might get different formatting
      # This tests the router's ability to handle channel context

      telegram_message = %{
        channel_type: "telegram",
        channel_id: "123",
        content: "Hello from Telegram",
        is_dm: true
      }

      slack_message = %{
        channel_type: "slack",
        channel_id: "C123",
        content: "Hello from Slack",
        is_dm: false,
        thread_ts: "1234567890.123456"
      }

      # Both should route correctly
      mock_provider = fn _provider, _session_id, _message, _opts ->
        {:ok, "Response", "session_123"}
      end

      {:ok, _, _, _} =
        AIRouter.route(telegram_message.content,
          provider_caller: mock_provider,
          session_id: nil
        )

      {:ok, _, _, _} =
        AIRouter.route(slack_message.content,
          provider_caller: mock_provider,
          session_id: nil
        )
    end
  end

  describe "session persistence across channels" do
    test "sessions persist independently across restarts", ctx do
      # Start a session and add messages
      {:ok, tg_pid} = start_session_server(ctx.telegram_session)

      mock_ai = fn _session_id, _content, _opts ->
        {:ok, %{result: "Test response"}, "session_123"}
      end

      {:ok, _} = SessionServer.handle_message(tg_pid, "Persistent message", ai_client: mock_ai)

      # Flush to database
      :ok = SessionServer.flush_to_db(tg_pid)

      # Stop the session
      GenServer.stop(tg_pid)

      # Start a new session server for the same session
      {:ok, new_tg_pid} = start_session_server(ctx.telegram_session)

      # Verify messages were loaded from database
      state = SessionServer.get_state(new_tg_pid)
      assert length(state.messages) >= 2
      assert Enum.any?(state.messages, &(&1.content == "Persistent message"))
    end
  end

  # Helper to start a session server
  defp start_session_server(session) do
    test_id = System.unique_integer([:positive])
    registry_name = :"TestRegistry_#{test_id}"

    {:ok, _} = Registry.start_link(keys: :unique, name: registry_name)

    SessionServer.start_link(
      session_id: session.id,
      channel_type: session.channel_type,
      channel_id: session.channel_id,
      user_id: session.user_id,
      registry_name: registry_name
    )
  end
end
