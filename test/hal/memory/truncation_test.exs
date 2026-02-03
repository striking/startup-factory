defmodule HAL.Memory.TruncationTest do
  use ExUnit.Case, async: true

  alias HAL.Memory.Truncation

  describe "truncate/2" do
    test "returns original content when under limit" do
      short = "Hello, world!"
      assert Truncation.truncate(short) == short
    end

    test "returns original when exactly at limit" do
      content = String.duplicate("x", 20_000)
      assert Truncation.truncate(content) == content
    end

    test "truncates content when over limit" do
      content = String.duplicate("This is a test sentence. ", 1000)
      result = Truncation.truncate(content, max_chars: 1000)

      # Should be approximately 1000 chars (with some variance for boundaries)
      assert String.length(result) <= 1100
      assert String.contains?(result, "[... truncated ...]")
    end

    test "preserves beginning content" do
      content =
        "START_MARKER: This is the important beginning. " <>
          String.duplicate("Middle content. ", 1000) <>
          "END_MARKER: This is the conclusion."

      result = Truncation.truncate(content, max_chars: 500)

      assert String.starts_with?(result, "START_MARKER")
    end

    test "preserves ending content" do
      content =
        "START_MARKER: This is the beginning. " <>
          String.duplicate("Middle content here. ", 1000) <>
          "END_MARKER: This is the conclusion."

      result = Truncation.truncate(content, max_chars: 500)

      assert String.ends_with?(result, "END_MARKER: This is the conclusion.")
    end

    test "respects custom head_ratio and tail_ratio" do
      content = String.duplicate("word ", 5000)

      # 60% head, 30% tail
      result = Truncation.truncate(content, max_chars: 500, head_ratio: 0.6, tail_ratio: 0.3)

      assert String.contains?(result, "[... truncated ...]")
    end

    test "respects custom marker" do
      content = String.duplicate("word ", 5000)
      custom_marker = "<<< CONTENT REMOVED >>>"

      result = Truncation.truncate(content, max_chars: 500, marker: custom_marker)

      assert String.contains?(result, custom_marker)
      refute String.contains?(result, "[... truncated ...]")
    end

    test "handles empty string" do
      assert Truncation.truncate("") == ""
    end

    test "handles whitespace-only string" do
      whitespace = "   \n\t  \n  "
      assert Truncation.truncate(whitespace) == whitespace
    end

    test "handles unicode content" do
      content = String.duplicate("Hello, \u4e16\u754c! ", 5000)
      result = Truncation.truncate(content, max_chars: 500)

      assert String.valid?(result)
      assert String.contains?(result, "[... truncated ...]")
    end
  end

  describe "truncate_to_tokens/3" do
    test "truncates based on token budget" do
      content = String.duplicate("word ", 10000)

      # 1000 tokens ~= 4000 chars
      result = Truncation.truncate_to_tokens(content, 1000)

      # Should be roughly 4000 chars or less (with boundary adjustments)
      assert String.length(result) <= 4500
    end

    test "passes through short content" do
      short = "Just a few words."
      assert Truncation.truncate_to_tokens(short, 1000) == short
    end

    test "accepts additional options" do
      content = String.duplicate("word ", 10000)
      custom_marker = "---CUT---"

      result = Truncation.truncate_to_tokens(content, 500, marker: custom_marker)

      assert String.contains?(result, custom_marker)
    end
  end

  describe "needs_truncation?/2" do
    test "returns false for short content" do
      refute Truncation.needs_truncation?("Hello")
    end

    test "returns true for long content" do
      long = String.duplicate("x", 25_000)
      assert Truncation.needs_truncation?(long)
    end

    test "returns false when exactly at limit" do
      content = String.duplicate("x", 20_000)
      refute Truncation.needs_truncation?(content)
    end

    test "respects custom limit" do
      assert Truncation.needs_truncation?("hello world", 5)
      refute Truncation.needs_truncation?("hello world", 20)
    end

    test "handles empty string" do
      refute Truncation.needs_truncation?("")
    end
  end

  describe "smart_boundary/3" do
    test "finds sentence boundary before position" do
      text = "Hello world. This is a test. More content here."
      boundary = Truncation.smart_boundary(text, 20, :before)

      # Should find the boundary after "Hello world. "
      assert boundary == 13
    end

    test "finds sentence boundary after position" do
      text = "Hello world. This is a test. More content here."
      boundary = Truncation.smart_boundary(text, 15, :after)

      # Should find the boundary after "This is a test. "
      assert boundary == 29
    end

    test "falls back to word boundary when no sentence found" do
      text = "No periods just words here"
      boundary = Truncation.smart_boundary(text, 12, :before)

      # Should find a word boundary
      assert text
             |> String.slice(0, boundary)
             |> String.trim_trailing()
             |> String.ends_with?("just") or
               text
               |> String.slice(0, boundary)
               |> String.trim_trailing()
               |> String.ends_with?("periods")
    end

    test "handles position at start of text" do
      text = "Hello world."
      boundary = Truncation.smart_boundary(text, 0, :after)

      # Should find first boundary
      assert boundary > 0
    end

    test "handles position at end of text" do
      text = "Hello world."
      text_length = String.length(text)
      boundary = Truncation.smart_boundary(text, text_length, :before)

      # Should find last boundary
      assert boundary <= text_length
    end

    test "handles text without any boundaries" do
      text = "xxxxxxxxxx"
      boundary = Truncation.smart_boundary(text, 5, :before)

      # Should return original position when no boundaries found
      assert is_integer(boundary)
    end

    test "handles various sentence endings" do
      # Period
      text1 = "Hello. World"
      assert Truncation.smart_boundary(text1, 8, :before) == 7

      # Exclamation
      text2 = "Hello! World"
      assert Truncation.smart_boundary(text2, 8, :before) == 7

      # Question mark
      text3 = "Hello? World"
      assert Truncation.smart_boundary(text3, 8, :before) == 7
    end
  end

  describe "estimate_tokens/1" do
    test "estimates tokens based on character count" do
      # ~4 chars per token
      assert Truncation.estimate_tokens("Hello world!") == 3
      assert Truncation.estimate_tokens(String.duplicate("x", 100)) == 25
      assert Truncation.estimate_tokens(String.duplicate("x", 1000)) == 250
    end

    test "handles empty string" do
      assert Truncation.estimate_tokens("") == 0
    end

    test "rounds up for partial tokens" do
      # 5 chars should be 2 tokens (5/4 = 1.25, ceil = 2)
      assert Truncation.estimate_tokens("hello") == 2
    end
  end

  describe "integration scenarios" do
    test "real-world memory content truncation" do
      # Simulate a MEMORY.md file with various sections
      memory_content = """
      # HAL Memory

      ## User Preferences
      - Prefers dark mode
      - Uses Elixir for backend development
      - Works on HAL project

      ## Important Decisions
      - 2024-01-15: Chose event sourcing for state management
      - 2024-01-20: Using JSONL for event log format

      #{String.duplicate("## Daily Log Entry\n- Did some work\n- Had meetings\n", 500)}

      ## Key Insights
      - The user values simplicity over complexity
      - Testing is non-negotiable
      - Documentation should be minimal but useful
      """

      result = Truncation.truncate(memory_content, max_chars: 2000)

      # Should preserve header
      assert String.contains?(result, "# HAL Memory")

      # Should preserve beginning sections
      assert String.contains?(result, "User Preferences")

      # Should have truncation marker
      assert String.contains?(result, "[... truncated ...]")

      # Should preserve ending
      assert String.contains?(result, "Key Insights")
    end

    test "conversation context truncation" do
      # Simulate a long conversation
      conversation =
        Enum.map_join(1..100, "\n", fn i ->
          "User (turn #{i}): Hello, this is message number #{i}.\n" <>
            "HAL (turn #{i}): I understand, this is my response to message #{i}."
        end)

      result = Truncation.truncate_to_tokens(conversation, 500)

      # Should be within token budget
      assert Truncation.estimate_tokens(result) <= 600

      # Should have truncation marker
      assert String.contains?(result, "[... truncated ...]")
    end
  end
end
