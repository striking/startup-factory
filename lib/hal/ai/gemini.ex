defmodule Hal.AI.Gemini do
  @moduledoc """
  Google Gemini AI provider implementation.

  This module provides integration with Google's Gemini 2.5 Flash model
  through the Google AI API. Gemini is used for quick, cost-effective
  responses to simple questions and general queries.

  ## Configuration

  Set the following in your environment:

      export GOOGLE_AI_API_KEY="your-api-key"

  Or configure in `config/runtime.exs`:

      config :hal, HAL.AI.Gemini,
        api_key: System.get_env("GOOGLE_AI_API_KEY"),
        model: "gemini-2.5-flash"

  ## Usage

      # Simple prompt
      {:ok, response, nil} = Hal.AI.Gemini.prompt(nil, "What is the capital of France?")

      # With custom options
      {:ok, response, nil} = Hal.AI.Gemini.prompt(nil, "Hello",
        system_prompt: "Be concise",
        timeout: 30_000
      )

  ## Notes

  - Gemini is stateless - session IDs are ignored
  - Best for: Simple questions, general knowledge, quick responses
  - Not ideal for: Complex coding tasks, multi-step reasoning
  """

  @behaviour Hal.AI.Provider

  require Logger

  @default_model "gemini-2.5-flash"
  @default_timeout 30_000
  @base_url "https://generativelanguage.googleapis.com/v1beta/models"

  # Cost estimates (approximate, per 1K tokens)
  # Gemini 2.0 Flash: ~$0.00015 input, ~$0.0006 output
  @cost_per_1k_input_tokens 0.00015
  @cost_per_1k_output_tokens 0.0006
  @avg_output_tokens 200

  # Client API

  @impl true
  def name, do: :gemini

  @impl true
  def prompt(session_id, message, opts \\ [])

  def prompt(_session_id, message, opts) do
    api_key = Keyword.get(opts, :api_key) || get_api_key()

    if is_nil(api_key) or api_key == "" do
      {:error, "Gemini API key not configured. Set GOOGLE_AI_API_KEY environment variable."}
    else
      do_prompt(message, api_key, opts)
    end
  end

  @impl true
  def supports?(_message) do
    # Gemini can handle any text query
    # The Router will decide when to use it based on task type
    true
  end

  @impl true
  def cost_estimate(message) do
    # Estimate tokens (rough approximation: ~4 chars per token)
    input_tokens = String.length(message) / 4

    input_cost = input_tokens / 1000 * @cost_per_1k_input_tokens
    output_cost = @avg_output_tokens / 1000 * @cost_per_1k_output_tokens

    Float.round(input_cost + output_cost, 6)
  end

  @doc """
  Builds the request body for the Gemini API.

  ## Options

    * `:system_prompt` - System instruction for the model
    * `:temperature` - Sampling temperature (0.0-1.0)
    * `:max_tokens` - Maximum output tokens
  """
  @spec build_request_body(String.t(), keyword()) :: String.t()
  def build_request_body(message, opts) do
    temperature = Keyword.get(opts, :temperature, 0.7)
    max_tokens = Keyword.get(opts, :max_tokens, 2048)
    system_prompt = Keyword.get(opts, :system_prompt)

    body = %{
      "contents" => [
        %{
          "role" => "user",
          "parts" => [%{"text" => message}]
        }
      ],
      "generationConfig" => %{
        "temperature" => temperature,
        "maxOutputTokens" => max_tokens
      }
    }

    body =
      if system_prompt do
        Map.put(body, "systemInstruction", %{
          "parts" => [%{"text" => system_prompt}]
        })
      else
        body
      end

    Jason.encode!(body)
  end

  @doc """
  Parses the response from the Gemini API.

  ## Returns

    * `{:ok, text}` - Success with the response text
    * `{:error, reason}` - Error with reason
  """
  @spec parse_response(map()) :: {:ok, String.t()} | {:error, String.t()}
  def parse_response(%{"candidates" => []}) do
    {:error, "No response candidates returned from Gemini API"}
  end

  def parse_response(%{"candidates" => [first | _]}) do
    case first do
      %{"finishReason" => reason, "content" => nil} when reason in ["SAFETY", "BLOCKED"] ->
        {:error, "Response blocked by safety filters: #{reason}"}

      %{"content" => %{"parts" => parts}} ->
        text = Enum.map_join(parts, "", fn %{"text" => text} -> text end)
        {:ok, text}

      _ ->
        {:error, "Unexpected response format from Gemini API"}
    end
  end

  def parse_response(_) do
    {:error, "Invalid response format from Gemini API"}
  end

  # Private Functions

  defp do_prompt(message, api_key, opts) do
    http_client = Keyword.get(opts, :http_client, &default_http_client/4)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    model = Keyword.get(opts, :model, @default_model)

    url = build_url(model, api_key)
    body = build_request_body(message, opts)
    headers = [{"Content-Type", "application/json"}]

    Logger.debug("Sending request to Gemini API: #{model}")

    case http_client.(url, body, headers, timeout: timeout) do
      {:ok, %{status_code: 200, body: response_body}} ->
        response_body
        |> Jason.decode!()
        |> parse_response()
        |> case do
          {:ok, text} -> {:ok, text, nil}
          {:error, reason} -> {:error, reason}
        end

      {:ok, %{status_code: status, body: response_body}} ->
        error = parse_error(response_body)
        Logger.error("Gemini API error (#{status}): #{error}")
        {:error, error}

      {:error, %{reason: reason}} ->
        Logger.error("HTTP error calling Gemini API: #{inspect(reason)}")
        {:error, "HTTP error: #{inspect(reason)}"}

      {:error, reason} ->
        Logger.error("HTTP error calling Gemini API: #{inspect(reason)}")
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end

  defp build_url(model, api_key) do
    "#{@base_url}/#{model}:generateContent?key=#{api_key}"
  end

  defp get_api_key do
    case Application.get_env(:hal, __MODULE__, []) do
      config when is_list(config) -> Keyword.get(config, :api_key)
      _ -> nil
    end || System.get_env("GOOGLE_AI_API_KEY") || System.get_env("GEMINI_API_KEY")
  end

  defp parse_error(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"message" => message}}} -> message
      {:ok, data} -> inspect(data)
      _ -> body
    end
  end

  defp parse_error(error), do: inspect(error)

  defp default_http_client(url, body, headers, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    HTTPoison.post(url, body, headers,
      timeout: timeout,
      recv_timeout: timeout
    )
  end
end
