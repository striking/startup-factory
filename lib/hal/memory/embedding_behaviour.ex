defmodule HAL.Memory.EmbeddingBehaviour do
  @moduledoc """
  Behaviour defining the interface for embedding implementations.

  This allows swapping between the real Vertex AI client and a mock
  implementation for testing.
  """

  @doc """
  Generate an embedding vector for a single text.

  ## Options

    * `:task_type` - The task type for the embedding
    * `:title` - Optional title for the content
    * `:model` - Override the configured model
    * `:timeout` - Request timeout in milliseconds

  ## Returns

    * `{:ok, [float()]}` - Success with embedding vector
    * `{:error, term()}` - Error with reason
  """
  @callback embed(text :: String.t(), opts :: keyword()) ::
              {:ok, [float()]} | {:error, term()}

  @doc """
  Generate embeddings for multiple texts in a single batch request.

  ## Options

  Same as `embed/2`.

  ## Returns

    * `{:ok, [[float()]]}` - Success with list of embedding vectors
    * `{:error, term()}` - Error with reason
  """
  @callback embed_batch(texts :: [String.t()], opts :: keyword()) ::
              {:ok, [[float()]]} | {:error, term()}

  @doc """
  Get the embedding dimension for the current model.

  ## Returns

    * `integer()` - The dimension of embedding vectors
  """
  @callback get_embedding_dimension() :: integer()
end
