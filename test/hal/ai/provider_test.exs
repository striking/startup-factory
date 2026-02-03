defmodule Hal.AI.ProviderTest do
  use ExUnit.Case, async: true

  alias Hal.AI.Provider

  describe "behaviour definition" do
    test "defines required callbacks" do
      callbacks = Provider.behaviour_info(:callbacks)

      assert {:prompt, 3} in callbacks
      assert {:supports?, 1} in callbacks
      assert {:cost_estimate, 1} in callbacks
      assert {:name, 0} in callbacks
    end
  end

  describe "extract_text/1" do
    test "extracts result from Claude Code response map" do
      response = %{result: "Hello world", session_id: "abc123"}
      assert Provider.extract_text(response) == "Hello world"
    end

    test "returns string response directly" do
      assert Provider.extract_text("Hello world") == "Hello world"
    end

    test "inspects other response types" do
      assert Provider.extract_text({:ok, "test"}) == ~s|{:ok, "test"}|
    end
  end

  describe "parse_cost/1" do
    test "parses string cost" do
      assert Provider.parse_cost("0.05") == 0.05
    end

    test "handles float cost" do
      assert Provider.parse_cost(0.05) == 0.05
    end

    test "handles integer cost" do
      assert Provider.parse_cost(5) == 5.0
    end

    test "returns 0.0 for nil" do
      assert Provider.parse_cost(nil) == 0.0
    end

    test "returns 0.0 for invalid string" do
      assert Provider.parse_cost("invalid") == 0.0
    end
  end
end
