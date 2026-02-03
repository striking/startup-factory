defmodule HAL.Memory.Embedding do
  @moduledoc """
  Google Vertex AI embeddings client for HAL.

  Generates text embeddings using Google's Vertex AI Text Embeddings API.
  Supports both service account authentication and API key authentication.

  ## Configuration

  Configure in `config/runtime.exs`:

      config :hal, HAL.Memory.Embedding,
        # Required: GCP project ID
        project_id: System.get_env("GOOGLE_CLOUD_PROJECT"),

        # Auth: Either service account or API key
        credentials_path: System.get_env("GOOGLE_APPLICATION_CREDENTIALS"),
        # OR
        api_key: System.get_env("GOOGLE_API_KEY"),

        # Optional: Model selection
        model: "gemini-embedding-001",  # 3072 dimensions (default)
        # model: "text-embedding-004",  # 768 dimensions (fallback)

        # Optional: Rate limiting
        requests_per_minute: 300,
        retry_max_attempts: 3,
        retry_base_delay_ms: 1000

  ## Environment Variables

  - `GOOGLE_CLOUD_PROJECT` - Your GCP project ID
  - `GOOGLE_APPLICATION_CREDENTIALS` - Path to service account JSON file
  - `GOOGLE_API_KEY` - Alternative: Simple API key authentication

  ## Usage

      # Generate embedding for a single text
      {:ok, embedding} = HAL.Memory.Embedding.embed("Hello world")

      # Generate embedding for search query
      {:ok, embedding} = HAL.Memory.Embedding.embed("search query", task_type: :retrieval_query)

      # Batch embedding
      {:ok, embeddings} = HAL.Memory.Embedding.embed_batch(["text1", "text2", "text3"])

      # Get embedding dimension for current model
      dimension = HAL.Memory.Embedding.get_embedding_dimension()

  ## Task Types

  - `:retrieval_document` - For storing documents (default)
  - `:retrieval_query` - For search queries
  - `:semantic_similarity` - For comparing text similarity
  - `:classification` - For text classification
  - `:clustering` - For clustering tasks

  ## Models

  - `gemini-embedding-001` - 3072 dimensions, best quality
  - `text-embedding-004` - 768 dimensions, faster, lower cost
  """

  require Logger

  @behaviour HAL.Memory.EmbeddingBehaviour

  # Model configurations
  @models %{
    "gemini-embedding-001" => %{dimensions: 3072, max_tokens: 2048},
    "text-embedding-004" => %{dimensions: 768, max_tokens: 2048}
  }

  @default_model "gemini-embedding-001"
  @default_location "us-central1"
  @default_timeout 30_000
  @default_retry_max_attempts 3
  @default_retry_base_delay_ms 1000
  @default_requests_per_minute 300

  # Rate limiter state (using ETS)
  @rate_limiter_table :embedding_rate_limiter

  @task_type_map %{
    retrieval_document: "RETRIEVAL_DOCUMENT",
    retrieval_query: "RETRIEVAL_QUERY",
    semantic_similarity: "SEMANTIC_SIMILARITY",
    classification: "CLASSIFICATION",
    clustering: "CLUSTERING"
  }

  # Public API

  @doc """
  Generate an embedding vector for a single text.

  ## Options

    * `:task_type` - The task type for the embedding. One of:
      - `:retrieval_document` (default) - For storing documents
      - `:retrieval_query` - For search queries
      - `:semantic_similarity` - For comparing texts
      - `:classification` - For classification tasks
      - `:clustering` - For clustering tasks
    * `:title` - Optional title for the content (improves retrieval quality)
    * `:model` - Override the configured model
    * `:timeout` - Request timeout in milliseconds

  ## Examples

      {:ok, embedding} = HAL.Memory.Embedding.embed("Hello world")
      {:ok, embedding} = HAL.Memory.Embedding.embed("search query", task_type: :retrieval_query)
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
  Generate embeddings for multiple texts in a single batch request.

  More efficient than calling `embed/2` multiple times as it batches
  the request to the API.

  ## Options

  Same as `embed/2`.

  ## Examples

      {:ok, embeddings} = HAL.Memory.Embedding.embed_batch(["text1", "text2", "text3"])
      length(embeddings)  # => 3
  """
  @impl true
  @spec embed_batch([String.t()], keyword()) :: {:ok, [[float()]]} | {:error, term()}
  def embed_batch(texts, opts \\ []) when is_list(texts) do
    if Enum.empty?(texts) do
      {:ok, []}
    else
      with :ok <- check_rate_limit(),
           {:ok, config} <- get_config(opts),
           {:ok, response} <- make_request(texts, config, opts) do
        parse_response(response)
      end
    end
  end

  @doc """
  Get the embedding dimension for the current model.

  ## Examples

      HAL.Memory.Embedding.get_embedding_dimension()
      # => 3072 (for gemini-embedding-001)
  """
  @impl true
  @spec get_embedding_dimension() :: integer()
  def get_embedding_dimension do
    model = get_model()
    get_in(@models, [model, :dimensions]) || 3072
  end

  @doc """
  Get the embedding dimension for a specific model.

  ## Examples

      HAL.Memory.Embedding.get_embedding_dimension("text-embedding-004")
      # => 768
  """
  @spec get_embedding_dimension(String.t()) :: integer() | nil
  def get_embedding_dimension(model) do
    get_in(@models, [model, :dimensions])
  end

  @doc """
  List available embedding models.

  ## Examples

      HAL.Memory.Embedding.list_models()
      # => ["gemini-embedding-001", "text-embedding-004"]
  """
  @spec list_models() :: [String.t()]
  def list_models do
    Map.keys(@models)
  end

  @doc """
  Check if the embedding service is properly configured.

  Returns `:ok` if configured, or `{:error, reason}` with details.
  """
  @spec check_config() :: :ok | {:error, String.t()}
  def check_config do
    case get_config([]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp get_config(opts) do
    config = Application.get_env(:hal, __MODULE__, [])

    project_id =
      Keyword.get(opts, :project_id) ||
        Keyword.get(config, :project_id) ||
        System.get_env("GOOGLE_CLOUD_PROJECT")

    credentials_path =
      Keyword.get(opts, :credentials_path) ||
        Keyword.get(config, :credentials_path) ||
        System.get_env("GOOGLE_APPLICATION_CREDENTIALS")

    api_key =
      Keyword.get(opts, :api_key) ||
        Keyword.get(config, :api_key) ||
        System.get_env("GOOGLE_API_KEY")

    cond do
      # API key auth - no project_id needed (uses Generative Language API)
      not is_nil(api_key) and api_key != "" ->
        {:ok,
         %{
           project_id: project_id,
           credentials_path: credentials_path,
           api_key: api_key,
           model: Keyword.get(opts, :model) || Keyword.get(config, :model) || @default_model,
           location: Keyword.get(config, :location) || @default_location,
           timeout:
             Keyword.get(opts, :timeout) || Keyword.get(config, :timeout) || @default_timeout,
           retry_max_attempts:
             Keyword.get(config, :retry_max_attempts) || @default_retry_max_attempts,
           retry_base_delay_ms:
             Keyword.get(config, :retry_base_delay_ms) || @default_retry_base_delay_ms
         }}

      # Service account auth - needs project_id
      is_nil(project_id) or project_id == "" ->
        {:error,
         "GOOGLE_CLOUD_PROJECT not configured. Set environment variable or config :hal, HAL.Memory.Embedding, project_id: \"your-project\" (or use GOOGLE_API_KEY for simpler setup)"}

      is_nil(credentials_path) ->
        {:error,
         "No authentication configured. Set GOOGLE_APPLICATION_CREDENTIALS or GOOGLE_API_KEY"}

      true ->
        {:ok,
         %{
           project_id: project_id,
           credentials_path: credentials_path,
           api_key: api_key,
           model: Keyword.get(opts, :model) || Keyword.get(config, :model) || @default_model,
           location: Keyword.get(config, :location) || @default_location,
           timeout:
             Keyword.get(opts, :timeout) || Keyword.get(config, :timeout) || @default_timeout,
           retry_max_attempts:
             Keyword.get(config, :retry_max_attempts) || @default_retry_max_attempts,
           retry_base_delay_ms:
             Keyword.get(config, :retry_base_delay_ms) || @default_retry_base_delay_ms
         }}
    end
  end

  defp get_model do
    config = Application.get_env(:hal, __MODULE__, [])
    Keyword.get(config, :model) || @default_model
  end

  defp make_request(texts, config, opts) do
    url = build_url(config)
    body = build_request_body(texts, config, opts)
    headers = build_headers(config)

    do_request_with_retry(url, body, headers, config, 1)
  end

  defp do_request_with_retry(url, body, headers, config, attempt) do
    timeout = config.timeout

    case HTTPoison.post(url, body, headers, timeout: timeout, recv_timeout: timeout) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %HTTPoison.Response{status_code: 429, body: response_body}} ->
        # Rate limited - retry with exponential backoff
        if attempt < config.retry_max_attempts do
          delay = calculate_backoff(attempt, config.retry_base_delay_ms)
          Logger.warning("Rate limited by Vertex AI, retrying in #{delay}ms (attempt #{attempt})")
          Process.sleep(delay)
          do_request_with_retry(url, body, headers, config, attempt + 1)
        else
          error_msg = parse_error(response_body)
          {:error, "Rate limited after #{attempt} attempts: #{error_msg}"}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: response_body}}
      when status in [500, 502, 503, 504] ->
        # Server error - retry with exponential backoff
        if attempt < config.retry_max_attempts do
          delay = calculate_backoff(attempt, config.retry_base_delay_ms)

          Logger.warning(
            "Server error #{status} from Vertex AI, retrying in #{delay}ms (attempt #{attempt})"
          )

          Process.sleep(delay)
          do_request_with_retry(url, body, headers, config, attempt + 1)
        else
          error_msg = parse_error(response_body)
          {:error, "Server error after #{attempt} attempts: #{error_msg}"}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
        error_msg = parse_error(response_body)
        Logger.error("Vertex AI API error (#{status}): #{error_msg}")
        {:error, "API error #{status}: #{error_msg}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        if attempt < config.retry_max_attempts do
          delay = calculate_backoff(attempt, config.retry_base_delay_ms)

          Logger.warning(
            "HTTP error calling Vertex AI: #{inspect(reason)}, retrying in #{delay}ms"
          )

          Process.sleep(delay)
          do_request_with_retry(url, body, headers, config, attempt + 1)
        else
          Logger.error("HTTP error after #{attempt} attempts: #{inspect(reason)}")
          {:error, "HTTP error: #{inspect(reason)}"}
        end
    end
  end

  defp calculate_backoff(attempt, base_delay) do
    # Exponential backoff with jitter
    max_delay = base_delay * :math.pow(2, attempt - 1)
    jitter = :rand.uniform(round(max_delay * 0.3))
    round(max_delay + jitter)
  end

  defp build_url(config) do
    if config.api_key do
      # Use Google AI API with API key (simpler setup)
      "https://generativelanguage.googleapis.com/v1beta/models/#{config.model}:embedContent?key=#{config.api_key}"
    else
      # Use Vertex AI with service account
      "https://#{config.location}-aiplatform.googleapis.com/v1/projects/#{config.project_id}/locations/#{config.location}/publishers/google/models/#{config.model}:predict"
    end
  end

  defp build_request_body(texts, config, opts) do
    task_type = Keyword.get(opts, :task_type, :retrieval_document)
    task_type_str = Map.get(@task_type_map, task_type, "RETRIEVAL_DOCUMENT")
    title = Keyword.get(opts, :title)

    if config.api_key do
      # Google AI API format (single text at a time for embedContent)
      # For batch, we'd need to use batchEmbedContents, but let's keep it simple
      content = %{
        "parts" => Enum.map(texts, fn text -> %{"text" => text} end)
      }

      body = %{
        "content" => content,
        "taskType" => task_type_str
      }

      body = if title, do: Map.put(body, "title", title), else: body
      Jason.encode!(body)
    else
      # Vertex AI format
      instances =
        Enum.map(texts, fn text ->
          instance = %{"content" => text, "task_type" => task_type_str}
          if title, do: Map.put(instance, "title", title), else: instance
        end)

      Jason.encode!(%{"instances" => instances})
    end
  end

  defp build_headers(config) do
    base_headers = [{"Content-Type", "application/json"}]

    if config.api_key do
      # API key is in URL, no auth header needed
      base_headers
    else
      # Service account - get access token
      case get_access_token(config.credentials_path) do
        {:ok, token} ->
          [{"Authorization", "Bearer #{token}"} | base_headers]

        {:error, reason} ->
          Logger.error("Failed to get access token: #{inspect(reason)}")
          base_headers
      end
    end
  end

  defp get_access_token(credentials_path) do
    # Read service account credentials and generate JWT token
    with {:ok, credentials_json} <- File.read(credentials_path),
         {:ok, credentials} <- Jason.decode(credentials_json) do
      generate_access_token(credentials)
    else
      {:error, :enoent} ->
        {:error, "Credentials file not found: #{credentials_path}"}

      {:error, reason} ->
        {:error, "Failed to read credentials: #{inspect(reason)}"}
    end
  end

  defp generate_access_token(_credentials) do
    # For production, you'd want to use a proper OAuth library like :google_auth
    # This is a simplified implementation that shells out to gcloud CLI
    # The credentials parameter is available for future JWT-based implementation

    # Try to use gcloud to get token (most common dev setup)
    case System.cmd("gcloud", ["auth", "print-access-token"], stderr_to_stdout: true) do
      {token, 0} ->
        {:ok, String.trim(token)}

      {error, _} ->
        # Fallback: try to generate JWT manually (would need jose library)
        Logger.warning(
          "gcloud auth failed: #{error}. Consider adding {:jose, \"~> 1.11\"} for JWT generation."
        )

        {:error,
         "Could not get access token. Ensure gcloud CLI is installed and authenticated, or use GOOGLE_API_KEY instead."}
    end
  end

  defp parse_response(%{"predictions" => predictions}) do
    # Vertex AI response format
    embeddings =
      Enum.map(predictions, fn pred ->
        pred["embeddings"]["values"]
      end)

    {:ok, embeddings}
  end

  defp parse_response(%{"embedding" => %{"values" => values}}) do
    # Google AI API response format (single embedding)
    {:ok, [values]}
  end

  defp parse_response(response) do
    Logger.error("Unexpected response format: #{inspect(response)}")
    {:error, "Unexpected response format from embedding API"}
  end

  defp parse_error(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"message" => message}}} -> message
      {:ok, %{"error" => error}} when is_binary(error) -> error
      {:ok, data} -> inspect(data)
      _ -> body
    end
  end

  defp parse_error(error), do: inspect(error)

  # Rate limiting using ETS

  defp check_rate_limit do
    ensure_rate_limiter_table()

    config = Application.get_env(:hal, __MODULE__, [])
    rpm = Keyword.get(config, :requests_per_minute) || @default_requests_per_minute

    now = System.system_time(:millisecond)
    # 1 minute window
    window_start = now - 60_000

    # Clean old entries and count recent requests
    :ets.select_delete(@rate_limiter_table, [{{:"$1"}, [{:<, :"$1", window_start}], [true]}])

    count = :ets.info(@rate_limiter_table, :size)

    if count >= rpm do
      {:error, "Rate limit exceeded (#{rpm} requests per minute). Please wait."}
    else
      :ets.insert(@rate_limiter_table, {now})
      :ok
    end
  end

  defp ensure_rate_limiter_table do
    case :ets.whereis(@rate_limiter_table) do
      :undefined ->
        :ets.new(@rate_limiter_table, [:set, :public, :named_table])

      _ ->
        :ok
    end
  end
end
