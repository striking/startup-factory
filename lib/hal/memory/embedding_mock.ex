defmodule HAL.Memory.EmbeddingMock do
  @moduledoc """
  Mock embedding client for testing.

  Generates deterministic pseudo-random embedding vectors based on input text.
  This allows tests to run without requiring actual API credentials.

  ## Configuration

  Configure your test environment to use the mock:

      # config/test.exs
      config :hal, :embedding_client, HAL.Memory.EmbeddingMock

  Or use in tests directly:

      HAL.Memory.EmbeddingMock.embed("test text")

  ## Behavior

  - Generates consistent embeddings for the same input text
  - Uses a hash of the input to seed the random number generator
  - Produces normalized vectors (unit length)
  - Supports configurable dimensions and latency simulation

  ## Options

      config :hal, HAL.Memory.EmbeddingMock,
        dimensions: 3072,           # Match real model dimensions
        simulate_latency: false,    # Add artificial delay
        latency_ms: 100,            # Delay amount if enabled
        failure_rate: 0.0           # Simulate random failures (0.0-1.0)
  """

  @behaviour HAL.Memory.EmbeddingBehaviour

  require Logger

  @default_dimensions 3072
  @default_simulate_latency false
  @default_latency_ms 100
  @default_failure_rate 0.0

  # Public API

  @doc """
  Generate a mock embedding vector for a single text.

  Returns a deterministic vector based on the hash of the input text.

  ## Options

    * `:dimensions` - Override the vector dimensions
    * `:simulate_latency` - Add artificial delay
    * `:failure_rate` - Probability of simulated failure (0.0-1.0)

  ## Examples

      {:ok, embedding} = HAL.Memory.EmbeddingMock.embed("Hello world")
      length(embedding)  # => 3072

      # Same input always produces same output
      {:ok, e1} = HAL.Memory.EmbeddingMock.embed("test")
      {:ok, e2} = HAL.Memory.EmbeddingMock.embed("test")
      e1 == e2  # => true
  """
  @impl true
  @spec embed(String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  def embed(text, opts \\ []) when is_binary(text) do
    case embed_batch([text], opts) do
      {:ok, [embedding]} -> {:ok, embedding}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Generate mock embeddings for multiple texts.

  ## Examples

      {:ok, embeddings} = HAL.Memory.EmbeddingMock.embed_batch(["a", "b", "c"])
      length(embeddings)  # => 3
  """
  @impl true
  @spec embed_batch([String.t()], keyword()) :: {:ok, [[float()]]} | {:error, term()}
  def embed_batch(texts, opts \\ []) when is_list(texts) do
    config = get_config(opts)

    # Simulate latency if configured
    if config.simulate_latency do
      Process.sleep(config.latency_ms)
    end

    # Simulate random failures if configured
    if config.failure_rate > 0 and :rand.uniform() < config.failure_rate do
      Logger.debug("Mock embedding: simulating failure")
      {:error, "Simulated API failure"}
    else
      embeddings =
        Enum.map(texts, fn text ->
          generate_embedding(text, config.dimensions)
        end)

      {:ok, embeddings}
    end
  end

  @doc """
  Get the embedding dimension for the mock.

  Returns the configured dimension or default (3072).
  """
  @impl true
  @spec get_embedding_dimension() :: integer()
  def get_embedding_dimension do
    config = Application.get_env(:hal, __MODULE__, [])
    Keyword.get(config, :dimensions) || @default_dimensions
  end

  @doc """
  Calculate cosine similarity between two embedding vectors.

  Useful for testing retrieval logic.

  ## Examples

      {:ok, e1} = HAL.Memory.EmbeddingMock.embed("hello")
      {:ok, e2} = HAL.Memory.EmbeddingMock.embed("hello")
      HAL.Memory.EmbeddingMock.cosine_similarity(e1, e2)
      # => 1.0

      {:ok, e3} = HAL.Memory.EmbeddingMock.embed("goodbye")
      HAL.Memory.EmbeddingMock.cosine_similarity(e1, e3)
      # => some value between -1.0 and 1.0
  """
  @spec cosine_similarity([float()], [float()]) :: float()
  def cosine_similarity(vec1, vec2) when length(vec1) == length(vec2) do
    dot_product = Enum.zip(vec1, vec2) |> Enum.map(fn {a, b} -> a * b end) |> Enum.sum()
    magnitude1 = :math.sqrt(Enum.map(vec1, &(&1 * &1)) |> Enum.sum())
    magnitude2 = :math.sqrt(Enum.map(vec2, &(&1 * &1)) |> Enum.sum())

    if magnitude1 == 0 or magnitude2 == 0 do
      0.0
    else
      dot_product / (magnitude1 * magnitude2)
    end
  end

  @doc """
  Generate a random embedding vector (not deterministic).

  Useful for generating test data that needs variety.

  ## Examples

      random_vec = HAL.Memory.EmbeddingMock.random_embedding(3072)
  """
  @spec random_embedding(integer()) :: [float()]
  def random_embedding(dimensions \\ @default_dimensions) do
    # Generate random values and normalize
    raw = for _ <- 1..dimensions, do: :rand.normal()
    normalize(raw)
  end

  # Private functions

  defp get_config(opts) do
    app_config = Application.get_env(:hal, __MODULE__, [])

    %{
      dimensions:
        Keyword.get(opts, :dimensions) ||
          Keyword.get(app_config, :dimensions) ||
          @default_dimensions,
      simulate_latency:
        Keyword.get(opts, :simulate_latency) ||
          Keyword.get(app_config, :simulate_latency) ||
          @default_simulate_latency,
      latency_ms:
        Keyword.get(opts, :latency_ms) ||
          Keyword.get(app_config, :latency_ms) ||
          @default_latency_ms,
      failure_rate:
        Keyword.get(opts, :failure_rate) ||
          Keyword.get(app_config, :failure_rate) ||
          @default_failure_rate
    }
  end

  defp generate_embedding(text, dimensions) do
    # Create deterministic seed from text hash
    seed = text_to_seed(text)

    # Generate pseudo-random vector using the seed
    raw_vector = seeded_random_vector(seed, dimensions)

    # Normalize to unit length (like real embeddings)
    normalize(raw_vector)
  end

  defp text_to_seed(text) do
    # Use erlang phash2 for deterministic hash
    :erlang.phash2(text, 1_000_000_000)
  end

  defp seeded_random_vector(seed, dimensions) do
    # Use the seed to create deterministic "random" values
    # This ensures same input text always produces same embedding
    :rand.seed(:exsss, {seed, seed * 2, seed * 3})

    for _ <- 1..dimensions do
      # Generate values with normal-ish distribution centered at 0
      :rand.normal()
    end
  end

  defp normalize(vector) do
    # Calculate magnitude (L2 norm)
    magnitude = :math.sqrt(Enum.map(vector, &(&1 * &1)) |> Enum.sum())

    if magnitude == 0 do
      # Avoid division by zero - return unit vector in first dimension
      [1.0 | List.duplicate(0.0, length(vector) - 1)]
    else
      Enum.map(vector, &(&1 / magnitude))
    end
  end
end
