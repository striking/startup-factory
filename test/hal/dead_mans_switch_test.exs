defmodule HAL.DeadMansSwitchTest do
  @moduledoc """
  Tests for the DeadMansSwitch GenServer.

  The DeadMansSwitch sends periodic status reports to an admin channel
  via Telegram, including system metrics like uptime, active sessions,
  messages today, and memory usage.
  """
  use ExUnit.Case, async: true

  alias HAL.DeadMansSwitch

  # Mock module for Telegram sender
  defmodule MockTelegram do
    @moduledoc false
    use GenServer

    def start_link(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      GenServer.start_link(__MODULE__, test_pid, name: Keyword.get(opts, :name))
    end

    @impl true
    def init(test_pid) do
      {:ok, %{test_pid: test_pid, messages: []}}
    end

    # Match the Sender API
    def send_message(server, chat_id, text, opts \\ []) do
      GenServer.call(server, {:send_message, chat_id, text, opts})
    end

    def get_messages(server) do
      GenServer.call(server, :get_messages)
    end

    @impl true
    def handle_call({:send_message, chat_id, text, opts}, _from, state) do
      message = %{chat_id: chat_id, text: text, opts: opts}
      send(state.test_pid, {:telegram_message_sent, message})
      {:reply, :ok, %{state | messages: [message | state.messages]}}
    end

    @impl true
    def handle_call(:get_messages, _from, state) do
      {:reply, Enum.reverse(state.messages), state}
    end
  end

  # Mock module for Dashboard
  defmodule MockDashboard do
    @moduledoc false
    def count_active_sessions, do: 5
    def count_messages_today, do: 127
  end

  describe "start_link/1" do
    test "starts the GenServer with default options" do
      name = :"test_dms_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        DeadMansSwitch.start_link(
          name: name,
          admin_channel_id: "-1001234567890",
          telegram_sender: nil,
          check_interval_ms: :timer.hours(6),
          dashboard_module: MockDashboard
        )

      assert Process.alive?(pid)
      Process.exit(pid, :normal)
    end

    test "accepts custom check_interval_ms" do
      name = :"test_dms_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        DeadMansSwitch.start_link(
          name: name,
          admin_channel_id: "-1001234567890",
          telegram_sender: nil,
          check_interval_ms: :timer.minutes(30),
          dashboard_module: MockDashboard
        )

      assert Process.alive?(pid)
      Process.exit(pid, :normal)
    end
  end

  describe "handle_info(:check_in, state)" do
    test "sends status message on schedule" do
      # Start mock Telegram sender
      telegram_name = :"test_telegram_#{System.unique_integer([:positive])}"
      {:ok, telegram_pid} = MockTelegram.start_link(name: telegram_name, test_pid: self())

      # Start DeadMansSwitch with very short interval for testing
      dms_name = :"test_dms_#{System.unique_integer([:positive])}"

      {:ok, dms_pid} =
        DeadMansSwitch.start_link(
          name: dms_name,
          admin_channel_id: "-1001234567890",
          telegram_sender: telegram_name,
          check_interval_ms: 50,
          dashboard_module: MockDashboard
        )

      # Wait for the first check-in message
      assert_receive {:telegram_message_sent, message}, 200

      assert message.chat_id == "-1001234567890"
      assert is_binary(message.text)

      # Cleanup
      Process.exit(dms_pid, :normal)
      Process.exit(telegram_pid, :normal)
    end

    test "message contains all required metrics" do
      telegram_name = :"test_telegram_#{System.unique_integer([:positive])}"
      {:ok, telegram_pid} = MockTelegram.start_link(name: telegram_name, test_pid: self())

      dms_name = :"test_dms_#{System.unique_integer([:positive])}"

      {:ok, dms_pid} =
        DeadMansSwitch.start_link(
          name: dms_name,
          admin_channel_id: "-1001234567890",
          telegram_sender: telegram_name,
          check_interval_ms: 50,
          dashboard_module: MockDashboard
        )

      assert_receive {:telegram_message_sent, message}, 200

      text = message.text

      # Check for required components
      assert String.contains?(text, "HAL Status Report")
      assert String.contains?(text, "Uptime:")
      assert String.contains?(text, "Active Sessions:")
      assert String.contains?(text, "Messages Today:")
      assert String.contains?(text, "Memory:")

      # Cleanup
      Process.exit(dms_pid, :normal)
      Process.exit(telegram_pid, :normal)
    end

    test "message formatting includes emoji and readable format" do
      telegram_name = :"test_telegram_#{System.unique_integer([:positive])}"
      {:ok, telegram_pid} = MockTelegram.start_link(name: telegram_name, test_pid: self())

      dms_name = :"test_dms_#{System.unique_integer([:positive])}"

      {:ok, dms_pid} =
        DeadMansSwitch.start_link(
          name: dms_name,
          admin_channel_id: "-1001234567890",
          telegram_sender: telegram_name,
          check_interval_ms: 50,
          dashboard_module: MockDashboard
        )

      assert_receive {:telegram_message_sent, message}, 200

      text = message.text

      # Check emoji is present (checkmark for operational status)
      assert String.contains?(text, "\u2705") or String.contains?(text, "All systems operational")

      # Check timestamp format (YYYY-MM-DD HH:MM:SS UTC)
      assert Regex.match?(~r/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC/, text)

      # Check memory format (X.X MB)
      assert Regex.match?(~r/\d+\.?\d* MB/, text)

      # Cleanup
      Process.exit(dms_pid, :normal)
      Process.exit(telegram_pid, :normal)
    end

    test "uses values from dashboard module" do
      telegram_name = :"test_telegram_#{System.unique_integer([:positive])}"
      {:ok, telegram_pid} = MockTelegram.start_link(name: telegram_name, test_pid: self())

      dms_name = :"test_dms_#{System.unique_integer([:positive])}"

      {:ok, dms_pid} =
        DeadMansSwitch.start_link(
          name: dms_name,
          admin_channel_id: "-1001234567890",
          telegram_sender: telegram_name,
          check_interval_ms: 50,
          dashboard_module: MockDashboard
        )

      assert_receive {:telegram_message_sent, message}, 200

      text = message.text

      # MockDashboard returns 5 active sessions and 127 messages
      assert String.contains?(text, "5")
      assert String.contains?(text, "127")

      # Cleanup
      Process.exit(dms_pid, :normal)
      Process.exit(telegram_pid, :normal)
    end
  end

  describe "configurable interval" do
    test "schedules next check-in after configured interval" do
      telegram_name = :"test_telegram_#{System.unique_integer([:positive])}"
      {:ok, telegram_pid} = MockTelegram.start_link(name: telegram_name, test_pid: self())

      dms_name = :"test_dms_#{System.unique_integer([:positive])}"

      {:ok, dms_pid} =
        DeadMansSwitch.start_link(
          name: dms_name,
          admin_channel_id: "-1001234567890",
          telegram_sender: telegram_name,
          check_interval_ms: 100,
          dashboard_module: MockDashboard
        )

      # First message
      assert_receive {:telegram_message_sent, _}, 200

      # Second message should come after ~100ms
      assert_receive {:telegram_message_sent, _}, 200

      # Cleanup
      Process.exit(dms_pid, :normal)
      Process.exit(telegram_pid, :normal)
    end
  end

  describe "graceful handling when Telegram unavailable" do
    test "continues running when Telegram sender returns error" do
      # Use a mock that returns errors via handle_call
      defmodule FailingTelegram do
        use GenServer

        def start_link(opts) do
          GenServer.start_link(__MODULE__, nil, name: Keyword.get(opts, :name))
        end

        @impl true
        def init(_), do: {:ok, nil}

        @impl true
        def handle_call({:send_message, _chat_id, _text, _opts}, _from, state) do
          {:reply, {:error, :connection_failed}, state}
        end
      end

      telegram_name = :"test_failing_telegram_#{System.unique_integer([:positive])}"
      {:ok, telegram_pid} = FailingTelegram.start_link(name: telegram_name)

      dms_name = :"test_dms_#{System.unique_integer([:positive])}"

      {:ok, dms_pid} =
        DeadMansSwitch.start_link(
          name: dms_name,
          admin_channel_id: "-1001234567890",
          telegram_sender: telegram_name,
          check_interval_ms: 50,
          dashboard_module: MockDashboard
        )

      # Wait for a few check-in cycles
      Process.sleep(150)

      # GenServer should still be alive
      assert Process.alive?(dms_pid)

      # Cleanup
      Process.exit(dms_pid, :normal)
      Process.exit(telegram_pid, :normal)
    end

    test "handles nil telegram_sender gracefully" do
      dms_name = :"test_dms_#{System.unique_integer([:positive])}"

      {:ok, dms_pid} =
        DeadMansSwitch.start_link(
          name: dms_name,
          admin_channel_id: "-1001234567890",
          telegram_sender: nil,
          check_interval_ms: 50,
          dashboard_module: MockDashboard
        )

      # Wait for a check-in cycle
      Process.sleep(100)

      # GenServer should still be alive
      assert Process.alive?(dms_pid)

      # Cleanup
      Process.exit(dms_pid, :normal)
    end
  end

  describe "get_uptime/0" do
    test "returns formatted uptime string" do
      # This tests the uptime formatting function
      name = :"test_dms_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        DeadMansSwitch.start_link(
          name: name,
          admin_channel_id: "-1001234567890",
          telegram_sender: nil,
          check_interval_ms: :timer.hours(6),
          dashboard_module: MockDashboard
        )

      uptime = DeadMansSwitch.get_uptime(name)

      assert is_binary(uptime)
      # Should contain time indicators
      assert Regex.match?(~r/\d+[smhd]/, uptime)

      Process.exit(pid, :normal)
    end
  end

  describe "trigger_check_in/1" do
    test "manually triggers a status report" do
      telegram_name = :"test_telegram_#{System.unique_integer([:positive])}"
      {:ok, telegram_pid} = MockTelegram.start_link(name: telegram_name, test_pid: self())

      dms_name = :"test_dms_#{System.unique_integer([:positive])}"

      {:ok, dms_pid} =
        DeadMansSwitch.start_link(
          name: dms_name,
          admin_channel_id: "-1001234567890",
          telegram_sender: telegram_name,
          # Very long interval so it won't trigger automatically
          check_interval_ms: :timer.hours(24),
          dashboard_module: MockDashboard
        )

      # Manually trigger check-in
      :ok = DeadMansSwitch.trigger_check_in(dms_name)

      # Should receive the message
      assert_receive {:telegram_message_sent, message}, 200

      assert String.contains?(message.text, "HAL Status Report")

      # Cleanup
      Process.exit(dms_pid, :normal)
      Process.exit(telegram_pid, :normal)
    end
  end
end
