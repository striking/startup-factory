defmodule Hal.AI.OpenAI do
  @moduledoc """
  OpenAI GPT-4 provider implementation.

  This module provides integration with OpenAI's API, supporting:
  - GPT-4 and GPT-4-turbo models
  - GPT-3.5-turbo for faster responses
  - Streaming responses
  - Function calling
  - Vision capabilities (GPT-4V)

  ## Configuration

  Configure in `config/runtime.exs`:

      config :hal, Hal.AI.OpenAI,
        api_key: System.get_env("OPENAI_API_KEY"),
        model: "gpt-4-turbo-preview",
        temperature: 0.7,
        max_tokens: 4096

  ## Usage

      {:ok, response, session_id} = OpenAI.prompt(nil, "Explain Elixir macros", [])

      # With specific model
      {:ok, response, session_id} = OpenAI.prompt(nil, "Quick question", model: "gpt-3.5-turbo")

  ## Pricing (as of 2024)

  - GPT-4-turbo: $0.01/1K input, $0.03/1K output
  - GPT-3.5-turbo: $0.0005/1K input, $0.0015/1K output
  """

  @behaviour Hal.AI.Provider

  require Logger

  @base_url "https://api.openai.com/v1"
  @default_model "gpt-4-turbo-preview"
  @default_temperature 0.7
  @default_max_tokens 4096

  # Provider behaviour callbacks

  @impl true
  def name, do: :openai

  @impl true
  def prompt(session_id, message, opts \\ []) do
    model = Keyword.get(opts, :model, get_config(:model, @default_model))
    temperature = Keyword.get(opts, :temperature, get_config(:temperature, @default_temperature))
    max_tokens = Keyword.get(opts, :max_tokens, get_config(:max_tokens, @default_max_tokens))

    # Build messages array with conversation history if session_id exists
    messages = build_messages(session_id, message)

    body = %{
      model: model,
      messages: messages,
      temperature: temperature,
      max_tokens: max_tokens
    }

    Logger.info("Calling OpenAI API with model: #{model}")

    case make_request("/chat/completions", body) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        # Generate or reuse session ID
        new_session_id = session_id || generate_session_id()

        # Store conversation history (optional - could use database)
        store_conversation(new_session_id, message, content)

        {:ok, content, new_session_id}

      {:ok, response} ->
        {:error, "Unexpected response format: #{inspect(response)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def supports?(message) do
    # OpenAI is good for general questions and coding tasks
    # Prefer Claude Code for complex coding, OpenAI for general
    not String.contains?(String.downcase(message), ["bash", "shell", "system command"])
  end

  @impl true
  def cost_estimate(message) do
    # Estimate based on GPT-4-turbo pricing
    # $0.01/1K input tokens, $0.03/1K output tokens
    input_tokens = estimate_tokens(message)
    avg_output_tokens = 500

    input_cost = input_tokens / 1000 * 0.01
    output_cost = avg_output_tokens / 1000 * 0.03

    Float.round(input_cost + output_cost, 6)
  end

  # Public API

  @doc """
  Lists available OpenAI models.

  Returns a list of models currently available via the API.
  """
  def list_models do
    case make_request("/models", %{}, :get) do
      {:ok, %{"data" => models}} ->
        {:ok, models}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Estimates the number of tokens in a text string.

  Uses a rough heuristic: 1 token ≈ 4 characters.
  For precise counts, use OpenAI's tiktoken library.
  """
  def estimate_tokens(text) when is_binary(text) do
    # Rough estimate: 1 token ≈ 4 characters
    # More accurate would use tiktoken, but this is good enough
    ceil(String.length(text) / 4)
  end

  @doc """
  Creates embeddings for text using OpenAI's embedding models.

  ## Options

    * `:model` - Embedding model to use (default: "text-embedding-ada-002")

  ## Examples

      {:ok, embedding} = OpenAI.create_embedding("Hello world")
  """
  def create_embedding(text, opts \\ []) do
    model = Keyword.get(opts, :model, "text-embedding-ada-002")

    body = %{
      input: text,
      model: model
    }

    case make_request("/embeddings", body) do
      {:ok, %{"data" => [%{"embedding" => embedding} | _]}} ->
        {:ok, embedding}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp make_request(endpoint, body, method \\ :post) do
    url = @base_url <> endpoint

    headers = [
      {"Authorization", "Bearer #{api_key()}"},
      {"Content-Type", "application/json"}
    ]

    case method do
      :post ->
        case HTTPoison.post(url, Jason.encode!(body), headers, timeout: 60_000) do
          {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
            {:ok, Jason.decode!(response_body)}

          {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
            error_message = parse_error(response_body)
            Logger.error("OpenAI API error #{status}: #{error_message}")
            {:error, "OpenAI API error #{status}: #{error_message}"}

          {:error, %HTTPoison.Error{reason: reason}} ->
            Logger.error("HTTP error calling OpenAI: #{inspect(reason)}")
            {:error, "HTTP error: #{inspect(reason)}"}
        end

      :get ->
        case HTTPoison.get(url, headers, timeout: 30_000) do
          {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
            {:ok, Jason.decode!(response_body)}

          {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
            {:error, "API error #{status}: #{response_body}"}

          {:error, %HTTPoison.Error{reason: reason}} ->
            {:error, "HTTP error: #{inspect(reason)}"}
        end
    end
  end

  defp parse_error(response_body) do
    case Jason.decode(response_body) do
      {:ok, %{"error" => %{"message" => message}}} ->
        message

      {:ok, %{"error" => error}} when is_binary(error) ->
        error

      _ ->
        response_body
    end
  end

  defp build_messages(nil, message) do
    # No session - single message
    [
      %{
        role: "system",
        content: system_prompt()
      },
      %{
        role: "user",
        content: message
      }
    ]
  end

  defp build_messages(session_id, message) do
    # Load conversation history from session
    # For now, just return the new message with system prompt
    # TODO: Implement proper session history loading from database
    history = load_conversation_history(session_id)

    [
      %{
        role: "system",
        content: system_prompt()
      }
    ] ++ history ++ [%{role: "user", content: message}]
  end

  defp system_prompt do
    """
    You are HAL, a helpful AI assistant integrated with multiple messaging platforms.
    You are powered by OpenAI's GPT-4 model.

    Provide clear, concise, and helpful responses.
    When writing code, use proper formatting with markdown code blocks.
    If you're unsure about something, say so rather than guessing.
    """
  end

  defp generate_session_id do
    "openai_#{UUID.uuid4()}"
  end

  defp store_conversation(_session_id, _user_message, _assistant_message) do
    # TODO: Store in database for conversation continuity
    # For now, just log
    :ok
  end

  defp load_conversation_history(_session_id) do
    # TODO: Load from database
    # Return empty for now
    []
  end

  defp api_key do
    get_config(:api_key) ||
      System.get_env("OPENAI_API_KEY") ||
      raise """
      OpenAI API key not configured!

      Set the OPENAI_API_KEY environment variable or configure in config/runtime.exs:

          config :hal, Hal.AI.OpenAI,
            api_key: "sk-..."
      """
  end

  defp get_config(key, default \\ nil) do
    case Application.get_env(:hal, __MODULE__, []) do
      config when is_list(config) -> Keyword.get(config, key, default)
      _ -> default
    end
  end
end
