defmodule Hal.ToolsTest do
  use Hal.DataCase, async: true

  alias Hal.Tools
  alias Hal.Accounts.User
  alias Hal.Repo

  describe "tool definitions" do
    test "returns all tool definitions" do
      tools = Tools.all()

      assert is_list(tools)
      assert length(tools) > 0

      # Check structure of first tool
      first_tool = List.first(tools)
      assert Map.has_key?(first_tool, :name)
      assert Map.has_key?(first_tool, :description)
      assert Map.has_key?(first_tool, :input_schema)
    end

    test "includes all expected tools" do
      tools = Tools.all()
      tool_names = Enum.map(tools, & &1.name)

      # Memory tools
      assert "hal_memory_search" in tool_names
      assert "hal_memory_store" in tool_names
      assert "hal_memory_forget" in tool_names

      # Calendar tools
      assert "hal_calendar_get_events" in tool_names
      assert "hal_calendar_create_event" in tool_names

      # Email tools
      assert "hal_email_get_unread" in tool_names
      assert "hal_email_send" in tool_names

      # Task tools
      assert "hal_tasks_list" in tool_names
      assert "hal_tasks_create" in tool_names
      assert "hal_tasks_complete" in tool_names

      # Notification tools
      assert "hal_send_notification" in tool_names
    end

    test "system prompt includes tools" do
      prompt = Tools.system_prompt()

      assert is_binary(prompt)
      assert String.contains?(prompt, "hal_memory_search")
      assert String.contains?(prompt, "hal_calendar_get_events")
      assert String.contains?(prompt, "hal_email_get_unread")
    end
  end

  describe "tool execution" do
    setup do
      {:ok, user} =
        %User{}
        |> User.changeset(%{
          external_id: "test_user_#{:rand.uniform(100_000)}",
          platform: "telegram",
          role: "owner",
          username: "Test User"
        })
        |> Repo.insert()

      %{user: user}
    end

    test "executes memory search tool", %{user: user} do
      # Store a test memory first using the correct API
      {:ok, _memory} = HAL.Memory.store("I prefer dark mode", "user_input")

      # Execute search tool
      {:ok, result} =
        Tools.execute(
          "hal_memory_search",
          %{"query" => "dark mode", "limit" => 5},
          user_id: user.id
        )

      assert result.success == true
      assert is_list(result.result)
      assert String.contains?(result.message, "Found")
    end

    test "executes calendar get_events tool (requires OAuth)", %{user: user} do
      # Calendar tool requires Google OAuth - returns error when not connected
      {:error, result} =
        Tools.execute(
          "hal_calendar_get_events",
          %{"limit" => 5},
          user_id: user.id
        )

      assert result.success == false
      assert String.contains?(result.error, "Google credentials not configured")
    end

    test "executes email get_unread tool (requires OAuth)", %{user: user} do
      # Email tool requires Google OAuth - returns error when not connected
      {:error, result} =
        Tools.execute(
          "hal_email_get_unread",
          %{"limit" => 10},
          user_id: user.id
        )

      assert result.success == false
      assert String.contains?(result.error, "Google credentials not configured")
    end

    test "executes tasks list tool (requires Linear)", %{user: user} do
      {:error, result} =
        Tools.execute(
          "hal_tasks_list",
          %{"status" => "pending"},
          user_id: user.id
        )

      assert result.success == false
      assert String.contains?(result.error, "Tasks not available")
    end

    test "executes notification send tool (requires channel config)", %{user: user} do
      {:error, result} =
        Tools.execute(
          "hal_send_notification",
          %{"message" => "Test notification", "priority" => "normal"},
          user_id: user.id
        )

      assert result.success == false
      assert String.contains?(result.error, "Notification channel not configured")
    end

    test "returns error for unknown tool", %{user: user} do
      {:error, result} =
        Tools.execute(
          "hal_unknown_tool",
          %{},
          user_id: user.id
        )

      assert result.success == false
      assert String.contains?(result.error, "Unknown tool")
    end

    test "returns error for missing required argument", %{user: user} do
      {:error, result} =
        Tools.execute(
          "hal_memory_search",
          %{},
          user_id: user.id
        )

      assert result.success == false
      assert String.contains?(result.error, "Missing required argument")
    end
  end

  describe "tool call interception" do
    setup do
      {:ok, user} =
        %User{}
        |> User.changeset(%{
          external_id: "test_user_#{:rand.uniform(100_000)}",
          platform: "telegram",
          role: "owner",
          username: "Test User"
        })
        |> Repo.insert()

      %{user: user}
    end

    test "detects tool calls in response" do
      response_with_tools = %{
        result: "Let me check that for you",
        tool_use: [
          %{
            id: "toolu_123",
            name: "hal_memory_search",
            input: %{"query" => "preferences"}
          }
        ]
      }

      assert Tools.has_tool_calls?(response_with_tools) == true

      response_without_tools = %{
        result: "Here's your answer"
      }

      assert Tools.has_tool_calls?(response_without_tools) == false
    end

    test "executes tool calls from response", %{user: user} do
      # Use memory tool which doesn't require OAuth
      response = %{
        tool_use: [
          %{
            id: "toolu_123",
            name: "hal_memory_search",
            input: %{"query" => "test query"}
          }
        ]
      }

      {:ok, results} = Tools.execute_tool_calls(response, user_id: user.id)

      assert is_list(results)
      assert length(results) == 1

      result = List.first(results)
      assert result.tool_use_id == "toolu_123"
      assert result.type == "tool_result"
      # Memory search should work without OAuth
      assert result.content.success == true
    end
  end
end
