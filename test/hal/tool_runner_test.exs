defmodule HAL.ToolRunnerTest do
  @moduledoc """
  Tests for HAL.ToolRunner - the tool execution and validation module.
  """
  use ExUnit.Case, async: true

  alias HAL.ToolRunner

  # Mock tool for testing successful execution
  defmodule MockTool do
    @moduledoc false

    def schema, do: %{name: "mock_tool"}

    def execute(%{"value" => value}) do
      {:ok, "Result: #{value}"}
    end

    def execute(_args) do
      {:error, "Missing 'value' key"}
    end
  end

  # Mock tool that always raises an error
  defmodule FailingTool do
    @moduledoc false

    def schema, do: %{name: "failing_tool"}

    def execute(_args) do
      raise "Intentional tool failure"
    end
  end

  # Mock tool with string name key in schema
  defmodule AnotherMockTool do
    @moduledoc false

    def schema, do: %{name: "another_tool"}

    def execute(%{"count" => count}) when is_integer(count) do
      {:ok, count * 2}
    end

    def execute(_) do
      {:error, "Invalid count"}
    end
  end

  describe "execute/3" do
    test "successfully executes a valid tool with valid args" do
      tools = [MockTool, AnotherMockTool]
      args = %{"value" => "hello"}

      assert {:ok, "Result: hello"} = ToolRunner.execute("mock_tool", args, tools)
    end

    test "returns error for unknown tool" do
      tools = [MockTool]
      args = %{"value" => "test"}

      assert {:error, "Tool not found: nonexistent_tool"} =
               ToolRunner.execute("nonexistent_tool", args, tools)
    end

    test "returns error when args is not a map" do
      tools = [MockTool]

      assert {:error, "Invalid arguments for mock_tool"} =
               ToolRunner.execute("mock_tool", "not a map", tools)

      assert {:error, "Invalid arguments for mock_tool"} =
               ToolRunner.execute("mock_tool", nil, tools)

      assert {:error, "Invalid arguments for mock_tool"} =
               ToolRunner.execute("mock_tool", [1, 2, 3], tools)
    end

    test "handles tool execution errors gracefully" do
      tools = [FailingTool]
      args = %{}

      result = ToolRunner.execute("failing_tool", args, tools)

      assert {:error, message} = result
      assert message =~ "Tool execution failed"
      assert message =~ "Intentional tool failure"
    end

    test "handles tool returning an error tuple" do
      tools = [MockTool]
      args = %{"wrong_key" => "value"}

      assert {:error, "Missing 'value' key"} =
               ToolRunner.execute("mock_tool", args, tools)
    end

    test "works with multiple tools and finds the correct one" do
      tools = [MockTool, AnotherMockTool, FailingTool]

      assert {:ok, "Result: test"} =
               ToolRunner.execute("mock_tool", %{"value" => "test"}, tools)

      assert {:ok, 20} =
               ToolRunner.execute("another_tool", %{"count" => 10}, tools)
    end

    test "handles empty tools list" do
      assert {:error, "Tool not found: any_tool"} =
               ToolRunner.execute("any_tool", %{}, [])
    end
  end

  describe "telemetry events" do
    setup do
      # Attach a telemetry handler to capture events
      test_pid = self()
      ref = make_ref()

      handler_id = "test-handler-#{inspect(ref)}"

      :telemetry.attach(
        handler_id,
        [:hal, :tools, :execute],
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event_name, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      :ok
    end

    test "emits telemetry event on successful execution" do
      tools = [MockTool]
      args = %{"value" => "test"}

      {:ok, _result} = ToolRunner.execute("mock_tool", args, tools)

      assert_receive {:telemetry_event, [:hal, :tools, :execute], measurements, metadata}

      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
      assert metadata.tool == "mock_tool"
      assert metadata.result == :ok
    end

    test "emits telemetry event on tool error" do
      tools = [FailingTool]
      args = %{}

      {:error, _} = ToolRunner.execute("failing_tool", args, tools)

      assert_receive {:telemetry_event, [:hal, :tools, :execute], measurements, metadata}

      assert is_integer(measurements.duration)
      assert metadata.tool == "failing_tool"
      assert metadata.result == :error
    end

    test "emits telemetry event when tool returns error tuple" do
      tools = [MockTool]
      args = %{"wrong_key" => "value"}

      {:error, _} = ToolRunner.execute("mock_tool", args, tools)

      assert_receive {:telemetry_event, [:hal, :tools, :execute], measurements, metadata}

      assert is_integer(measurements.duration)
      assert metadata.tool == "mock_tool"
      assert metadata.result == :error
    end

    test "does not emit telemetry when tool not found" do
      tools = [MockTool]

      {:error, _} = ToolRunner.execute("nonexistent", %{}, tools)

      refute_receive {:telemetry_event, [:hal, :tools, :execute], _, _}, 100
    end

    test "does not emit telemetry when args invalid" do
      tools = [MockTool]

      {:error, _} = ToolRunner.execute("mock_tool", "not a map", tools)

      refute_receive {:telemetry_event, [:hal, :tools, :execute], _, _}, 100
    end
  end
end
