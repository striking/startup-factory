defmodule HAL.Memory.EmbeddingTest do
  use ExUnit.Case, async: true

  alias HAL.Memory.EmbeddingMock

  describe "EmbeddingMock.embed/2" do
    test "returns embedding vector of correct dimension" do
      {:ok, embedding} = EmbeddingMock.embed("Hello world")

      assert is_list(embedding)
      assert length(embedding) == 3072
      assert Enum.all?(embedding, &is_float/1)
    end

    test "returns deterministic embeddings for same input" do
      {:ok, e1} = EmbeddingMock.embed("test input")
      {:ok, e2} = EmbeddingMock.embed("test input")

      assert e1 == e2
    end

    test "returns different embeddings for different inputs" do
      {:ok, e1} = EmbeddingMock.embed("hello")
      {:ok, e2} = EmbeddingMock.embed("goodbye")

      refute e1 == e2
    end

    test "respects custom dimensions option" do
      {:ok, embedding} = EmbeddingMock.embed("test", dimensions: 768)

      assert length(embedding) == 768
    end

    test "returns normalized vectors (unit length)" do
      {:ok, embedding} = EmbeddingMock.embed("test")

      magnitude = :math.sqrt(Enum.map(embedding, &(&1 * &1)) |> Enum.sum())

      # Should be very close to 1.0 (unit vector)
      assert_in_delta magnitude, 1.0, 0.0001
    end
  end

  describe "EmbeddingMock.embed_batch/2" do
    test "returns embeddings for multiple texts" do
      texts = ["one", "two", "three"]
      {:ok, embeddings} = EmbeddingMock.embed_batch(texts)

      assert length(embeddings) == 3
      assert Enum.all?(embeddings, fn e -> length(e) == 3072 end)
    end

    test "returns empty list for empty input" do
      {:ok, embeddings} = EmbeddingMock.embed_batch([])

      assert embeddings == []
    end

    test "batch results match individual embed results" do
      texts = ["alpha", "beta"]
      {:ok, batch_embeddings} = EmbeddingMock.embed_batch(texts)

      {:ok, e1} = EmbeddingMock.embed("alpha")
      {:ok, e2} = EmbeddingMock.embed("beta")

      assert Enum.at(batch_embeddings, 0) == e1
      assert Enum.at(batch_embeddings, 1) == e2
    end

    test "can simulate failures" do
      # Always fail
      {:error, _} = EmbeddingMock.embed_batch(["test"], failure_rate: 1.0)
    end
  end

  describe "EmbeddingMock.get_embedding_dimension/0" do
    test "returns default dimension" do
      assert EmbeddingMock.get_embedding_dimension() == 3072
    end
  end

  describe "EmbeddingMock.cosine_similarity/2" do
    test "returns 1.0 for identical vectors" do
      {:ok, e1} = EmbeddingMock.embed("same text")
      {:ok, e2} = EmbeddingMock.embed("same text")

      similarity = EmbeddingMock.cosine_similarity(e1, e2)

      assert_in_delta similarity, 1.0, 0.0001
    end

    test "returns value between -1 and 1 for different vectors" do
      {:ok, e1} = EmbeddingMock.embed("hello world")
      {:ok, e2} = EmbeddingMock.embed("goodbye moon")

      similarity = EmbeddingMock.cosine_similarity(e1, e2)

      assert similarity >= -1.0
      assert similarity <= 1.0
    end

    test "handles orthogonal vectors" do
      # Create two orthogonal unit vectors
      v1 = [1.0, 0.0, 0.0]
      v2 = [0.0, 1.0, 0.0]

      similarity = EmbeddingMock.cosine_similarity(v1, v2)

      assert_in_delta similarity, 0.0, 0.0001
    end

    test "handles opposite vectors" do
      v1 = [1.0, 0.0, 0.0]
      v2 = [-1.0, 0.0, 0.0]

      similarity = EmbeddingMock.cosine_similarity(v1, v2)

      assert_in_delta similarity, -1.0, 0.0001
    end
  end

  describe "EmbeddingMock.random_embedding/1" do
    test "returns vector of specified dimension" do
      vec = EmbeddingMock.random_embedding(100)

      assert length(vec) == 100
    end

    test "returns normalized vector" do
      vec = EmbeddingMock.random_embedding(100)

      magnitude = :math.sqrt(Enum.map(vec, &(&1 * &1)) |> Enum.sum())

      assert_in_delta magnitude, 1.0, 0.0001
    end

    test "returns different vectors each time" do
      v1 = EmbeddingMock.random_embedding(100)
      v2 = EmbeddingMock.random_embedding(100)

      refute v1 == v2
    end
  end
end
