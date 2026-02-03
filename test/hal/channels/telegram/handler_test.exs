defmodule Hal.Channels.Telegram.HandlerTest do
  @moduledoc """
  Tests for the Telegram Handler GenServer.
  """
  use Hal.DataCase, async: false

  alias Hal.Accounts.User
  alias Hal.Channels.Telegram.Handler
  alias Hal.Channels.Telegram.Sender
  alias Hal.Gateway.Router
  alias Hal.Gateway.SessionManager

  # Mock sender that just captures messages
  defmodule MockSender do
    use GenServer

    def start_link(opts) do
      name = Keyword.fetch!(opts, :name)
      GenServer.start_link(__MODULE__, opts, name: name)
    end

    def init(_opts), do: {:ok, %{messages: []}}

    def get_messages(server), do: GenServer.call(server, :get_messages)

    def handle_call({:send_message, chat_id, text, opts}, _from, state) do
      message = {chat_id, text, opts}
      {:reply, :ok, %{state | messages: [message | state.messages]}}
    end

    def handle_call(:get_messages, _from, state) do
      {:reply, Enum.reverse(state.messages), state}
    end
  end

  # Mock router that returns a fixed response
  defmodule MockRouter do
    use GenServer

    def start_link(opts) do
      name = Keyword.fetch!(opts, :name)
      GenServer.start_link(__MODULE__, opts, name: name)
    end

    def init(opts) do
      response = Keyword.get(opts, :response, {:ok, "Mock response"})
      {:ok, %{response: response, messages: []}}
    end

    def get_messages(server), do: GenServer.call(server, :get_messages)

    def handle_call({:route_message, message, _opts}, _from, state) do
      {:reply, state.response, %{state | messages: [message | state.messages]}}
    end

    def handle_call(:get_messages, _from, state) do
      {:reply, Enum.reverse(state.messages), state}
    end
  end

  setup do
    test_id = System.unique_integer([:positive])

    # Start mock processes
    sender_name = :"test_sender_#{test_id}"
    router_name = :"test_router_#{test_id}"
    handler_name = :"test_handler_#{test_id}"

    {:ok, _sender} = MockSender.start_link(name: sender_name)
    {:ok, _router} = MockRouter.start_link(name: router_name, response: {:ok, "Test response"})

    # Start the handler
    {:ok, handler} =
      Handler.start_link(
        name: handler_name,
        sender_name: sender_name,
        router: router_name,
        session_manager: Hal.Gateway.SessionManager
      )

    # Set mock bot info
    bot_info = %{id: 123_456_789, username: "test_bot"}
    Handler.set_bot_info(handler, bot_info)

    %{
      handler: handler,
      handler_name: handler_name,
      sender_name: sender_name,
      router_name: router_name,
      bot_info: bot_info
    }
  end

  describe "text message handling" do
    test "processes DM text messages", %{
      handler_name: handler_name,
      sender_name: sender_name,
      router_name: router_name
    } do
      # Create a DM message
      message = build_text_message("Hello HAL!", type: "private")

      # Send to handler
      Handler.handle_update(handler_name, :text_message, message, %{})

      # Wait for async processing
      Process.sleep(100)

      # Verify router received the message
      [routed] = MockRouter.get_messages(router_name)
      assert routed.channel_type == "telegram"
      assert routed.content == "Hello HAL!"
      assert routed.is_dm == true

      # Verify sender sent the response
      [{_chat_id, response_text, _opts}] = MockSender.get_messages(sender_name)
      assert response_text == "Test response"
    end

    test "processes group messages with @mention", %{
      handler_name: handler_name,
      router_name: router_name
    } do
      message = build_text_message("@test_bot help me", type: "group")

      Handler.handle_update(handler_name, :text_message, message, %{})
      Process.sleep(100)

      [routed] = MockRouter.get_messages(router_name)
      assert routed.content == "help me"
      assert routed.is_dm == false
      assert routed.mentions_bot == true
    end

    test "ignores group messages without @mention", %{
      handler_name: handler_name,
      router_name: router_name
    } do
      message = build_text_message("Hello everyone!", type: "group")

      Handler.handle_update(handler_name, :text_message, message, %{})
      Process.sleep(100)

      # Router should not receive any message
      assert MockRouter.get_messages(router_name) == []
    end
  end

  describe "mention detection" do
    test "detects @username mention", %{handler_name: handler_name, router_name: router_name} do
      message = build_text_message("@test_bot what is Elixir?", type: "group")

      Handler.handle_update(handler_name, :text_message, message, %{})
      Process.sleep(100)

      [routed] = MockRouter.get_messages(router_name)
      assert routed.mentions_bot == true
      assert routed.content == "what is Elixir?"
    end

    test "detects @hal mention", %{handler_name: handler_name, router_name: router_name} do
      message = build_text_message("@hal help", type: "group")

      Handler.handle_update(handler_name, :text_message, message, %{})
      Process.sleep(100)

      [routed] = MockRouter.get_messages(router_name)
      assert routed.mentions_bot == true
    end

    test "detects hal: prefix", %{handler_name: handler_name, router_name: router_name} do
      message = build_text_message("hal: tell me a joke", type: "group")

      Handler.handle_update(handler_name, :text_message, message, %{})
      Process.sleep(100)

      [routed] = MockRouter.get_messages(router_name)
      assert routed.mentions_bot == true
      assert routed.content == "tell me a joke"
    end
  end

  describe "user creation" do
    test "creates new user for new Telegram user", %{
      handler_name: handler_name,
      router_name: router_name
    } do
      telegram_user_id = System.unique_integer([:positive])
      message = build_text_message("Hello!", type: "private", user_id: telegram_user_id)

      Handler.handle_update(handler_name, :text_message, message, %{})
      Process.sleep(100)

      # Verify user was created
      user = Repo.one(from u in User, where: u.external_id == ^to_string(telegram_user_id))
      assert user != nil
      assert user.platform == "telegram"

      # Verify router got the user_id
      [routed] = MockRouter.get_messages(router_name)
      assert routed.user_id == user.id
    end

    test "reuses existing user", %{handler_name: handler_name, router_name: router_name} do
      # Create user first
      telegram_user_id = System.unique_integer([:positive])

      {:ok, existing_user} =
        %User{}
        |> User.changeset(%{
          external_id: to_string(telegram_user_id),
          platform: "telegram"
        })
        |> Repo.insert()

      message = build_text_message("Hello again!", type: "private", user_id: telegram_user_id)

      Handler.handle_update(handler_name, :text_message, message, %{})
      Process.sleep(100)

      # Verify same user was used
      [routed] = MockRouter.get_messages(router_name)
      assert routed.user_id == existing_user.id

      # Verify no duplicate was created
      count =
        Repo.aggregate(
          from(u in User, where: u.external_id == ^to_string(telegram_user_id)),
          :count
        )

      assert count == 1
    end
  end

  describe "command handling" do
    test "handles /start command", %{handler_name: handler_name, sender_name: sender_name} do
      message = build_text_message("/start", type: "private")

      Handler.handle_update(handler_name, :command, %{command: :start, message: message}, %{})
      Process.sleep(100)

      [{_chat_id, text, _opts}] = MockSender.get_messages(sender_name)
      assert String.contains?(text, "Hello")
      assert String.contains?(text, "HAL")
    end

    test "handles /help command", %{handler_name: handler_name, sender_name: sender_name} do
      message = build_text_message("/help", type: "private")

      Handler.handle_update(handler_name, :command, %{command: :help, message: message}, %{})
      Process.sleep(100)

      [{_chat_id, text, opts}] = MockSender.get_messages(sender_name)
      assert String.contains?(text, "Help")
      assert Keyword.get(opts, :parse_mode) == "Markdown"
    end
  end

  # Helper functions

  defp build_text_message(text, opts \\ []) do
    type = Keyword.get(opts, :type, "private")
    user_id = Keyword.get(opts, :user_id, System.unique_integer([:positive]))
    chat_id = Keyword.get(opts, :chat_id, System.unique_integer([:positive]))

    %{
      message_id: System.unique_integer([:positive]),
      text: text,
      chat: %{
        id: chat_id,
        type: type
      },
      from: %{
        id: user_id,
        username: "test_user",
        first_name: "Test",
        last_name: "User",
        language_code: "en"
      }
    }
  end
end
