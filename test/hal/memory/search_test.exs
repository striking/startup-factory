defmodule HAL.Memory.SearchTest do
  use Hal.DataCase, async: true

  alias HAL.Memory.Search
  alias HAL.Memory.EmbeddingMock
  alias Hal.Memory.Store

  describe "search/2" do
    test "returns empty list when no memories exist" do
      {:ok, results} = Search.search("test query")

      assert results == []
    end

    test "returns memories sorted by similarity" do
      # Create memories with known embeddings
      {:ok, target_embedding} = EmbeddingMock.embed("I prefer dark mode")
      {:ok, related_embedding} = EmbeddingMock.embed("I like dark themes")
      {:ok, unrelated_embedding} = EmbeddingMock.embed("The weather is sunny")

      {:ok, target_memory} =
        Store.create_memory("I prefer dark mode", target_embedding, source: "conversation")

      {:ok, _related_memory} =
        Store.create_memory("I like dark themes", related_embedding, source: "conversation")

      {:ok, _unrelated_memory} =
        Store.create_memory("The weather is sunny", unrelated_embedding, source: "observation")

      # Search for "dark mode preferences" (which should match dark mode/themes)
      {:ok, results} = Search.search("I prefer dark mode", limit: 10, threshold: 0.0)

      assert length(results) >= 1

      # The exact match should be first
      first_result = List.first(results)
      assert first_result.memory.id == target_memory.id
      assert first_result.similarity >= 0.99

      # All results should have similarity scores
      assert Enum.all?(results, fn r -> is_float(r.similarity) end)
    end

    test "respects limit option" do
      # Create multiple memories
      for i <- 1..10 do
        {:ok, embedding} = EmbeddingMock.embed("Memory #{i}")
        Store.create_memory("Memory #{i}", embedding, source: "conversation")
      end

      {:ok, results} = Search.search("Memory", limit: 3, threshold: 0.0)

      assert length(results) <= 3
    end

    test "filters by source" do
      {:ok, conv_embedding} = EmbeddingMock.embed("conversation memory")
      {:ok, doc_embedding} = EmbeddingMock.embed("document memory")

      {:ok, _conv} =
        Store.create_memory("conversation memory", conv_embedding, source: "conversation")

      {:ok, _doc} =
        Store.create_memory("document memory", doc_embedding, source: "document")

      {:ok, results} =
        Search.search("memory", limit: 10, threshold: 0.0, source: "conversation")

      assert Enum.all?(results, fn r -> r.memory.source == "conversation" end)
    end

    test "filters by threshold" do
      {:ok, embedding} = EmbeddingMock.embed("specific topic")

      {:ok, _memory} =
        Store.create_memory("specific topic", embedding, source: "conversation")

      # High threshold should filter out dissimilar results
      {:ok, high_threshold_results} = Search.search("completely different", threshold: 0.99)

      assert high_threshold_results == []

      # Low threshold should include more results
      {:ok, low_threshold_results} = Search.search("specific topic", threshold: 0.0)

      assert length(low_threshold_results) >= 1
    end
  end

  describe "search_similar/2" do
    test "returns error for non-existent memory" do
      fake_id = Ecto.UUID.generate()

      assert {:error, :not_found} = Search.search_similar(fake_id)
    end

    test "returns error for memory without embedding" do
      {:ok, memory} =
        Store.create_memory("No embedding", nil, source: "conversation")

      assert {:error, :no_embedding} = Search.search_similar(memory.id)
    end

    test "finds similar memories" do
      {:ok, embedding1} = EmbeddingMock.embed("dark mode preference")
      {:ok, embedding2} = EmbeddingMock.embed("dark theme setting")
      {:ok, embedding3} = EmbeddingMock.embed("light mode preference")

      {:ok, memory1} =
        Store.create_memory("dark mode preference", embedding1, source: "conversation")

      {:ok, _memory2} =
        Store.create_memory("dark theme setting", embedding2, source: "conversation")

      {:ok, _memory3} =
        Store.create_memory("light mode preference", embedding3, source: "conversation")

      {:ok, results} = Search.search_similar(memory1.id, limit: 10, threshold: 0.0)

      # Should include the source memory itself (similarity 1.0)
      assert length(results) >= 1

      # First result should be the same memory
      first = List.first(results)
      assert first.memory.id == memory1.id
      assert_in_delta first.similarity, 1.0, 0.001
    end
  end

  describe "get_relevant_context/2" do
    test "returns empty string when no memories match" do
      context = Search.get_relevant_context("nonexistent query")

      assert context == ""
    end

    test "returns formatted text context" do
      {:ok, embedding} = EmbeddingMock.embed("user prefers dark mode")

      {:ok, _memory} =
        Store.create_memory("user prefers dark mode", embedding, source: "conversation")

      context = Search.get_relevant_context("user prefers dark mode", format: :text)

      assert String.starts_with?(context, "Relevant context from memory:")
      assert String.contains?(context, "user prefers dark mode")
    end

    test "returns structured XML context" do
      {:ok, embedding} = EmbeddingMock.embed("structured test")

      {:ok, _memory} =
        Store.create_memory("structured test", embedding, source: "conversation")

      context = Search.get_relevant_context("structured test", format: :structured)

      assert String.starts_with?(context, "<relevant_memories>")
      assert String.contains?(context, "<memory")
      assert String.contains?(context, "similarity=")
      assert String.ends_with?(context, "</relevant_memories>")
    end

    test "truncates output when max_chars is set" do
      {:ok, embedding} = EmbeddingMock.embed("long content for truncation test")

      {:ok, _memory} =
        Store.create_memory(
          "This is a very long piece of content that should be truncated when we set a max_chars limit",
          embedding,
          source: "conversation"
        )

      context =
        Search.get_relevant_context("long content", max_chars: 50, threshold: 0.0)

      # Should be truncated to max_chars
      assert String.length(context) <= 50
      assert String.ends_with?(context, "...")
    end
  end

  describe "query compilation" do
    test "pgvector query compiles correctly" do
      # This test verifies the Ecto query with pgvector fragment compiles
      # It doesn't need to return results, just not raise
      assert {:ok, _} = Search.search("test query compilation")
    end
  end
end
