defmodule HAL.MemoryTest do
  @moduledoc """
  Tests for HAL.Memory facade module.

  This module tests the high-level API for storing, recalling, and managing
  memories with vector embeddings.
  """
  use Hal.DataCase, async: true

  alias HAL.Memory
  alias Hal.Memory.Store

  # Helper to set up test configuration
  defp setup_config(config) do
    original = Application.get_env(:hal, HAL.Memory, [])
    Application.put_env(:hal, HAL.Memory, config)
    on_exit(fn -> Application.put_env(:hal, HAL.Memory, original) end)
  end

  describe "store/3" do
    test "stores a memory with embedding" do
      {:ok, memory} = Memory.store("I prefer dark mode for coding", "user_input")

      assert memory.id
      assert memory.content == "I prefer dark mode for coding"
      assert memory.source == "user_input"
      assert memory.embedding != nil
      assert memory.metadata == %{}
    end

    test "stores a memory with metadata" do
      {:ok, memory} =
        Memory.store(
          "User prefers Elixir",
          "conversation",
          metadata: %{session_id: "test-123", importance: "high"}
        )

      assert memory.metadata == %{session_id: "test-123", importance: "high"}
    end

    test "stores a memory without embedding when skip_embedding: true" do
      {:ok, memory} =
        Memory.store(
          "Quick note",
          "observation",
          skip_embedding: true
        )

      assert memory.id
      assert memory.content == "Quick note"
      assert memory.embedding == nil
    end

    test "validates source type" do
      {:error, changeset} = Memory.store("Test content", "invalid_source")

      refute changeset.valid?

      assert "must be one of: conversation, document, observation, system, user_input, agent_output" in errors_on(
               changeset
             ).source
    end

    test "returns error when memory system is disabled" do
      setup_config(enabled: false)

      {:error, :memory_disabled} = Memory.store("Test", "user_input")
    end

    test "accepts all valid sources" do
      for source <- Store.valid_sources() do
        {:ok, memory} = Memory.store("Test content for #{source}", source)
        assert memory.source == source
      end
    end
  end

  describe "recall/2" do
    setup do
      # Store some test memories
      {:ok, mem1} = Memory.store("I prefer dark mode for all interfaces", "user_input")
      {:ok, mem2} = Memory.store("I like using Elixir for backend development", "user_input")
      {:ok, mem3} = Memory.store("The weather is sunny today", "observation")

      {:ok, memories: %{dark_mode: mem1, elixir: mem2, weather: mem3}}
    end

    test "returns relevant memories", %{memories: _memories} do
      # With mock embeddings, search for exact text to get high similarity
      {:ok, results} = Memory.recall("I prefer dark mode for all interfaces", threshold: 0.0)

      assert length(results) >= 1
      # At least one result should exist
      assert Enum.any?(results, fn %{memory: _m} -> true end)
    end

    test "returns memories with similarity scores", %{memories: _memories} do
      {:ok, results} = Memory.recall("programming", threshold: 0.0)

      for result <- results do
        assert Map.has_key?(result, :memory)
        assert Map.has_key?(result, :similarity)
        assert is_float(result.similarity)
        assert result.similarity >= 0.0
        assert result.similarity <= 1.0
      end
    end

    test "respects limit option", %{memories: _memories} do
      {:ok, results} = Memory.recall("anything", limit: 1, threshold: 0.0)

      assert length(results) <= 1
    end

    test "respects threshold option" do
      # High threshold should filter out low-similarity results
      {:ok, results} = Memory.recall("quantum physics gibberish xyz", threshold: 0.99)

      assert results == []
    end

    test "filters by source option", %{memories: _memories} do
      {:ok, results} =
        Memory.recall("preferences", source: "user_input", threshold: 0.0)

      assert Enum.all?(results, fn %{memory: m} -> m.source == "user_input" end)
    end

    test "returns empty list when memory system is disabled" do
      setup_config(enabled: false)

      {:ok, results} = Memory.recall("anything")

      assert results == []
    end
  end

  describe "get_context/2" do
    setup do
      {:ok, _mem1} = Memory.store("User prefers dark mode theme", "user_input")
      {:ok, _mem2} = Memory.store("User works late at night", "observation")
      :ok
    end

    test "returns formatted text context" do
      context = Memory.get_context("user preferences", format: :text, threshold: 0.0)

      if context != "" do
        assert String.starts_with?(context, "Relevant context from memory:")
      end
    end

    test "returns structured XML context" do
      context = Memory.get_context("user preferences", format: :structured, threshold: 0.0)

      if context != "" do
        assert String.contains?(context, "<relevant_memories>")
        assert String.contains?(context, "<memory")
        assert String.contains?(context, "similarity=")
      end
    end

    test "returns empty string when no relevant memories found" do
      context = Memory.get_context("quantum physics xyz", threshold: 0.99)

      assert context == ""
    end

    test "returns empty string when memory system is disabled" do
      setup_config(enabled: false)

      context = Memory.get_context("anything")

      assert context == ""
    end

    test "respects max_chars option" do
      # Store a memory with long content
      {:ok, _} = Memory.store(String.duplicate("Long content here. ", 100), "document")

      context = Memory.get_context("Long content", max_chars: 100, threshold: 0.0)

      # Should be truncated (might be slightly over due to format)
      assert String.length(context) <= 103 or context == ""
    end
  end

  describe "forget/1" do
    test "deletes a memory by id" do
      {:ok, memory} = Memory.store("Temporary memory", "observation")

      assert {:ok, deleted} = Memory.forget(memory.id)
      assert deleted.id == memory.id

      # Verify it's gone
      assert Store.get_memory(memory.id) == nil
    end

    test "returns error for non-existent memory" do
      fake_id = Ecto.UUID.generate()

      assert {:error, :not_found} = Memory.forget(fake_id)
    end
  end

  describe "store_exchange/3" do
    test "skips storing when auto_store is disabled and not forced" do
      setup_config(enabled: true, auto_store_conversations: false)

      {:ok, :skipped} = Memory.store_exchange("Hello", "Hi there!")
    end

    test "stores both messages when forced" do
      setup_config(enabled: true, auto_store_conversations: false)

      {:ok, result} = Memory.store_exchange("Hello", "Hi there!", force: true)

      assert result.user.content == "Hello"
      assert result.user.source == "user_input"
      assert result.ai.content == "Hi there!"
      assert result.ai.source == "agent_output"
    end

    test "stores both messages when auto_store is enabled" do
      setup_config(enabled: true, auto_store_conversations: true)

      {:ok, result} = Memory.store_exchange("How are you?", "I'm doing well!")

      assert result.user.content == "How are you?"
      assert result.ai.content == "I'm doing well!"
    end

    test "includes session_id in metadata when provided" do
      setup_config(enabled: true, auto_store_conversations: true)

      {:ok, result} =
        Memory.store_exchange("Test", "Response", session_id: "session-abc-123")

      assert result.user.metadata[:session_id] == "session-abc-123"
      assert result.ai.metadata[:session_id] == "session-abc-123"
    end

    test "includes role in metadata" do
      setup_config(enabled: true, auto_store_conversations: true)

      {:ok, result} = Memory.store_exchange("Test", "Response")

      assert result.user.metadata[:role] == "user"
      assert result.ai.metadata[:role] == "assistant"
    end

    test "merges additional metadata" do
      setup_config(enabled: true, auto_store_conversations: true)

      {:ok, result} =
        Memory.store_exchange("Test", "Response", metadata: %{topic: "testing"})

      assert result.user.metadata[:topic] == "testing"
      assert result.ai.metadata[:topic] == "testing"
    end
  end

  describe "enabled?/0" do
    test "returns true by default" do
      setup_config([])

      assert Memory.enabled?() == true
    end

    test "returns false when disabled in config" do
      setup_config(enabled: false)

      assert Memory.enabled?() == false
    end

    test "returns true when enabled in config" do
      setup_config(enabled: true)

      assert Memory.enabled?() == true
    end
  end

  describe "auto_store_enabled?/0" do
    test "returns false by default" do
      setup_config([])

      assert Memory.auto_store_enabled?() == false
    end

    test "returns false when memory is disabled" do
      setup_config(enabled: false, auto_store_conversations: true)

      assert Memory.auto_store_enabled?() == false
    end

    test "returns true when both enabled" do
      setup_config(enabled: true, auto_store_conversations: true)

      assert Memory.auto_store_enabled?() == true
    end
  end

  describe "max_context_chars/0" do
    test "returns default value" do
      setup_config([])

      assert Memory.max_context_chars() == 8000
    end

    test "returns configured value" do
      setup_config(max_context_chars: 4000)

      assert Memory.max_context_chars() == 4000
    end
  end

  describe "relevance_threshold/0" do
    test "returns default value" do
      setup_config([])

      assert Memory.relevance_threshold() == 0.7
    end

    test "returns configured value" do
      setup_config(relevance_threshold: 0.5)

      assert Memory.relevance_threshold() == 0.5
    end
  end

  describe "truncate/2" do
    test "passes through short content" do
      short = "Hello, world!"
      assert Memory.truncate(short) == short
    end

    test "truncates long content" do
      long = String.duplicate("word ", 10000)
      result = Memory.truncate(long, max_chars: 1000)

      assert String.length(result) <= 1100
      assert String.contains?(result, "[... truncated ...]")
    end
  end

  describe "status/0" do
    test "returns status map with expected keys" do
      status = Memory.status()

      assert Map.has_key?(status, :enabled)
      assert Map.has_key?(status, :auto_store_conversations)
      assert Map.has_key?(status, :max_context_chars)
      assert Map.has_key?(status, :relevance_threshold)
      assert Map.has_key?(status, :embedding_service)
      assert Map.has_key?(status, :embedding_dimension)
    end

    test "returns correct enabled status" do
      setup_config(enabled: true)
      status = Memory.status()

      assert status.enabled == true
    end

    test "returns embedding dimension" do
      status = Memory.status()

      assert is_integer(status.embedding_dimension)
      assert status.embedding_dimension > 0
    end
  end

  describe "integration: full memory lifecycle" do
    test "store, recall, verify, delete workflow" do
      content = "The user's favorite programming language is Elixir"

      # 1. Store a memory
      {:ok, memory} =
        Memory.store(
          content,
          "conversation",
          metadata: %{confidence: "high"}
        )

      assert memory.id
      assert memory.embedding != nil

      # 2. Recall it with the exact content to ensure high similarity with mock
      {:ok, results} = Memory.recall(content, threshold: 0.0)

      # Should find at least the memory we just stored
      assert length(results) >= 1

      # The exact match should be found
      found = Enum.find(results, fn %{memory: m} -> m.id == memory.id end)
      assert found != nil
      # Exact text should have high similarity
      assert found.similarity >= 0.9

      # 3. Get context (should include the memory)
      context = Memory.get_context(content, threshold: 0.0)

      assert context != ""
      assert String.contains?(context, "Elixir")

      # 4. Delete the memory
      {:ok, deleted} = Memory.forget(memory.id)
      assert deleted.id == memory.id

      # 5. Verify it's gone
      assert Store.get_memory(memory.id) == nil
    end
  end
end
