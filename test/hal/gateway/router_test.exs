defmodule Hal.Gateway.RouterTest do
  @moduledoc """
  Tests for the Gateway Router.
  """
  use Hal.DataCase, async: false

  alias Hal.Accounts.User
  alias Hal.Gateway.Router
  alias Hal.Gateway.SessionManager
  alias Hal.Security.PairingRequest

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

  # Helper to start test infrastructure
  defp start_test_infrastructure do
    test_id = System.unique_integer([:positive])

    registry_name = :"TestRegistry#{test_id}"
    supervisor_name = :"TestDynamicSupervisor#{test_id}"
    session_manager_name = :"TestSessionManager#{test_id}"
    router_name = :"TestRouter#{test_id}"

    # Start Registry
    {:ok, _} = Registry.start_link(keys: :unique, name: registry_name)

    # Start DynamicSupervisor
    {:ok, _} = DynamicSupervisor.start_link(strategy: :one_for_one, name: supervisor_name)

    # Start SessionManager
    {:ok, _} =
      SessionManager.start_link(
        name: session_manager_name,
        registry_name: registry_name,
        dynamic_supervisor_name: supervisor_name
      )

    # Start Router
    {:ok, router_pid} =
      Router.start_link(
        name: router_name,
        session_manager_name: session_manager_name
      )

    %{
      router: router_pid,
      router_name: router_name,
      session_manager_name: session_manager_name,
      registry_name: registry_name,
      supervisor_name: supervisor_name
    }
  end

  describe "start_link/1" do
    test "starts the router" do
      infra = start_test_infrastructure()
      assert Process.alive?(infra.router)
    end
  end

  describe "route_message/2" do
    test "routes DM message to session" do
      infra = start_test_infrastructure()
      user = create_user()

      message = %{
        channel_type: "telegram",
        channel_id: "dm_#{user.id}",
        user_id: user.id,
        content: "Hello!",
        is_dm: true,
        mentions_bot: false
      }

      mock_ai = fn _session_id, _content, _opts ->
        {:ok, %{result: "Hi there!"}, "session_123"}
      end

      {:ok, response} = Router.route_message(infra.router_name, message, ai_client: mock_ai)

      assert response == "Hi there!"
    end

    test "DM pairing policy: unpaired user receives pairing code and no session is created" do
      infra = start_test_infrastructure()
      user = create_user()

      original = Application.get_env(:hal, Hal.Security, [])
      Application.put_env(:hal, Hal.Security, Keyword.put(original, :dm_policy, :pairing))

      on_exit(fn ->
        Application.put_env(:hal, Hal.Security, original)
      end)

      message = %{
        channel_type: "telegram",
        channel_id: "dm_#{user.id}",
        user_id: user.id,
        content: "Hello!",
        is_dm: true,
        mentions_bot: false
      }

      assert Repo.aggregate(Hal.Gateway.Session, :count, :id) == 0

      assert {:ok, response} = Router.route_message(infra.router_name, message)
      assert response =~ "Pairing required"
      assert response =~ "pairing code is:"

      assert Repo.aggregate(Hal.Gateway.Session, :count, :id) == 0
      assert Repo.aggregate(PairingRequest, :count, :id) == 1
    end

    test "group allowlist policy: ignores groups not allowlisted" do
      infra = start_test_infrastructure()
      user = create_user()

      original = Application.get_env(:hal, Hal.Security, [])

      Application.put_env(
        :hal,
        Hal.Security,
        original
        |> Keyword.put(:group_policy, :allowlist)
        |> Keyword.put(:group_allowlist, [])
      )

      on_exit(fn ->
        Application.put_env(:hal, Hal.Security, original)
      end)

      message = %{
        channel_type: "slack",
        channel_id: "C12345",
        user_id: user.id,
        content: "@hal What's the weather?",
        is_dm: false,
        mentions_bot: true
      }

      assert Router.route_message(infra.router_name, message) == :ignored
    end

    test "routes group message with bot mention to session" do
      infra = start_test_infrastructure()
      user = create_user()

      message = %{
        channel_type: "slack",
        channel_id: "C12345",
        user_id: user.id,
        content: "@hal What's the weather?",
        is_dm: false,
        mentions_bot: true
      }

      mock_ai = fn _session_id, _content, _opts ->
        {:ok, %{result: "I cannot check the weather."}, "session_456"}
      end

      {:ok, response} = Router.route_message(infra.router_name, message, ai_client: mock_ai)

      assert response == "I cannot check the weather."
    end

    test "ignores group message without bot mention" do
      infra = start_test_infrastructure()
      user = create_user()

      message = %{
        channel_type: "slack",
        channel_id: "C12345",
        user_id: user.id,
        content: "Random chat message",
        is_dm: false,
        mentions_bot: false
      }

      result = Router.route_message(infra.router_name, message)

      assert result == :ignored
    end

    test "handles missing user by returning error" do
      infra = start_test_infrastructure()

      message = %{
        channel_type: "telegram",
        channel_id: "chat_123",
        # Non-existent user
        user_id: Ecto.UUID.generate(),
        content: "Hello!",
        is_dm: true,
        mentions_bot: false
      }

      result = Router.route_message(infra.router_name, message)

      assert {:error, _reason} = result
    end
  end

  describe "should_respond?/1" do
    test "returns true for DMs" do
      message = %{is_dm: true, mentions_bot: false}
      assert Router.should_respond?(message) == true
    end

    test "returns true for group messages with bot mention" do
      message = %{is_dm: false, mentions_bot: true}
      assert Router.should_respond?(message) == true
    end

    test "returns false for group messages without bot mention" do
      message = %{is_dm: false, mentions_bot: false}
      assert Router.should_respond?(message) == false
    end
  end

  describe "parse_message_content/1" do
    test "removes bot mention from content" do
      content = "@hal What is Elixir?"
      assert Router.parse_message_content(content) == "What is Elixir?"
    end

    test "removes multiple bot mention formats" do
      assert Router.parse_message_content("@HAL help me") == "help me"
      assert Router.parse_message_content("<@U123456> explain OTP") == "explain OTP"
      assert Router.parse_message_content("hal: do something") == "do something"
    end

    test "preserves content without mention" do
      content = "Just a normal message"
      assert Router.parse_message_content(content) == "Just a normal message"
    end

    test "trims whitespace" do
      content = "  @hal   Hello  "
      assert Router.parse_message_content(content) == "Hello"
    end
  end
end
