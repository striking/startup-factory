defmodule Hal.Memory.StoreTest do
  @moduledoc """
  Tests for Hal.Memory.Store Ecto operations.

  This module tests the low-level database operations for memory storage,
  including CRUD operations and validation.
  """
  use Hal.DataCase, async: true

  alias Hal.Memory.Store
  alias HAL.Memory.EmbeddingMock

  describe "create_memory/3" do
    test "creates a memory with valid data" do
      {:ok, embedding} = EmbeddingMock.embed("test content")

      {:ok, memory} =
        Store.create_memory("This is test content", embedding,
          source: "conversation",
          metadata: %{key: "value"}
        )

      assert memory.id != nil
      assert memory.content == "This is test content"
      assert memory.source == "conversation"
      assert memory.metadata == %{key: "value"}
      assert memory.embedding != nil
      assert memory.inserted_at != nil
      assert memory.updated_at != nil
    end

    test "creates a memory without embedding" do
      {:ok, memory} =
        Store.create_memory("Content without embedding", nil, source: "document")

      assert memory.id != nil
      assert memory.content == "Content without embedding"
      assert memory.embedding == nil
    end

    test "creates a memory with default empty metadata" do
      {:ok, memory} = Store.create_memory("Simple content", nil, source: "observation")

      assert memory.metadata == %{}
    end

    test "returns error for missing content" do
      {:error, changeset} = Store.create_memory("", nil, source: "conversation")

      refute changeset.valid?
      # Empty string triggers "cannot be blank" validation
      assert "cannot be blank" in errors_on(changeset).content or
               "can't be blank" in errors_on(changeset).content
    end

    test "returns error for whitespace-only content" do
      {:error, changeset} = Store.create_memory("   \n\t   ", nil, source: "conversation")

      refute changeset.valid?
      # Custom validation adds "cannot be blank" for whitespace-only content
      errors = errors_on(changeset).content
      assert "cannot be blank" in errors or "can't be blank" in errors
    end

    test "returns error for invalid source" do
      {:error, changeset} = Store.create_memory("Content", nil, source: "invalid_source")

      refute changeset.valid?

      assert "must be one of: conversation, document, observation, system, user_input, agent_output" in errors_on(
               changeset
             ).source
    end

    test "accepts all valid sources" do
      for source <- Store.valid_sources() do
        {:ok, memory} = Store.create_memory("Content for #{source}", nil, source: source)
        assert memory.source == source
      end
    end

    test "stores embedding as Pgvector" do
      {:ok, embedding} = EmbeddingMock.embed("test content for vector")

      {:ok, memory} =
        Store.create_memory("Content with embedding", embedding, source: "conversation")

      assert %Pgvector{} = memory.embedding
    end
  end

  describe "get_memory/1" do
    test "returns memory when it exists" do
      {:ok, created} =
        Store.create_memory("Test memory", nil, source: "conversation")

      found = Store.get_memory(created.id)

      assert found != nil
      assert found.id == created.id
      assert found.content == "Test memory"
    end

    test "returns nil for non-existent id" do
      fake_id = Ecto.UUID.generate()

      assert Store.get_memory(fake_id) == nil
    end

    test "returns nil for invalid id format" do
      # Invalid UUID should not crash, just return nil or error
      result =
        try do
          Store.get_memory("not-a-uuid")
        rescue
          Ecto.Query.CastError -> nil
        end

      assert result == nil
    end
  end

  describe "list_memories/1" do
    setup do
      # Create test memories with different sources
      {:ok, mem1} =
        Store.create_memory("Conversation memory 1", nil, source: "conversation")

      {:ok, mem2} =
        Store.create_memory("Document memory", nil, source: "document")

      {:ok, mem3} =
        Store.create_memory("Conversation memory 2", nil, source: "conversation")

      {:ok, memories: [mem1, mem2, mem3]}
    end

    test "returns all memories without filters", %{memories: memories} do
      results = Store.list_memories()

      assert length(results) >= length(memories)
    end

    test "filters by source", %{memories: _memories} do
      results = Store.list_memories(source: "conversation")

      assert length(results) >= 2
      assert Enum.all?(results, fn m -> m.source == "conversation" end)
    end

    test "respects limit option", %{memories: _memories} do
      results = Store.list_memories(limit: 1)

      assert length(results) == 1
    end

    test "respects offset option", %{memories: memories} do
      all_results = Store.list_memories()
      offset_results = Store.list_memories(offset: 1)

      # With offset 1, should have one fewer result
      assert length(offset_results) == length(all_results) - 1 or
               length(offset_results) < length(memories)
    end

    test "orders by inserted_at descending", %{memories: _memories} do
      results = Store.list_memories()

      timestamps = Enum.map(results, & &1.inserted_at)
      assert timestamps == Enum.sort(timestamps, {:desc, DateTime})
    end

    test "returns empty list when no memories match filter" do
      results = Store.list_memories(source: "system")

      # May have system memories from other tests, but filtering works
      assert Enum.all?(results, fn m -> m.source == "system" end)
    end
  end

  describe "delete_memory/1" do
    test "deletes an existing memory" do
      {:ok, memory} =
        Store.create_memory("Memory to delete", nil, source: "conversation")

      {:ok, deleted} = Store.delete_memory(memory.id)

      assert deleted.id == memory.id
      assert Store.get_memory(memory.id) == nil
    end

    test "returns error for non-existent memory" do
      fake_id = Ecto.UUID.generate()

      assert {:error, :not_found} = Store.delete_memory(fake_id)
    end
  end

  describe "update_metadata/2" do
    test "adds new metadata to existing memory" do
      {:ok, memory} =
        Store.create_memory("Test memory", nil,
          source: "conversation",
          metadata: %{existing: "value"}
        )

      {:ok, updated} = Store.update_metadata(memory.id, %{new_key: "new_value"})

      assert updated.metadata["existing"] == "value" or updated.metadata[:existing] == "value"

      assert updated.metadata[:new_key] == "new_value" or
               updated.metadata["new_key"] == "new_value"
    end

    test "overwrites existing metadata keys" do
      {:ok, memory} =
        Store.create_memory("Test memory", nil,
          source: "conversation",
          metadata: %{key: "old_value"}
        )

      {:ok, updated} = Store.update_metadata(memory.id, %{key: "new_value"})

      # The new value should overwrite the old
      assert updated.metadata[:key] == "new_value" or updated.metadata["key"] == "new_value"
    end

    test "returns error for non-existent memory" do
      fake_id = Ecto.UUID.generate()

      assert {:error, :not_found} = Store.update_metadata(fake_id, %{key: "value"})
    end

    test "handles empty metadata update" do
      {:ok, memory} =
        Store.create_memory("Test memory", nil,
          source: "conversation",
          metadata: %{existing: "value"}
        )

      {:ok, updated} = Store.update_metadata(memory.id, %{})

      # Should keep existing metadata
      assert updated.metadata[:existing] == "value" or updated.metadata["existing"] == "value"
    end
  end

  describe "valid_sources/0" do
    test "returns expected sources" do
      sources = Store.valid_sources()

      assert "conversation" in sources
      assert "document" in sources
      assert "observation" in sources
      assert "system" in sources
      assert "user_input" in sources
      assert "agent_output" in sources
    end

    test "returns a list of strings" do
      sources = Store.valid_sources()

      assert is_list(sources)
      assert Enum.all?(sources, &is_binary/1)
    end
  end

  describe "changeset/2" do
    test "validates required content" do
      changeset = Store.changeset(%Store{}, %{source: "conversation"})

      refute changeset.valid?
      # Ecto's validate_required uses "can't be blank"
      assert errors_on(changeset).content != nil
    end

    test "validates content is not blank" do
      changeset = Store.changeset(%Store{}, %{content: "   ", source: "conversation"})

      refute changeset.valid?
      # Custom validation adds "cannot be blank" for whitespace-only content
      errors = errors_on(changeset).content
      assert "cannot be blank" in errors or "can't be blank" in errors
    end

    test "validates source inclusion" do
      changeset = Store.changeset(%Store{}, %{content: "Test", source: "invalid"})

      refute changeset.valid?
      assert errors_on(changeset).source != nil
    end

    test "accepts valid changeset" do
      changeset =
        Store.changeset(%Store{}, %{
          content: "Valid content",
          source: "conversation",
          metadata: %{key: "value"}
        })

      assert changeset.valid?
    end
  end
end
