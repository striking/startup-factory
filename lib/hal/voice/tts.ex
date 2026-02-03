defmodule HAL.Voice.TTS do
  @moduledoc """
  Text-to-Speech module using ElevenLabs API.

  Provides functionality to convert text to speech audio files.

  ## Configuration

  The following configuration options are available:

      config :hal, HAL.Voice.TTS,
        api_key: "your_elevenlabs_api_key",
        voice_id: "21m00Tcm4TlvDq8ikWAM"

  ## Usage

      # Basic usage
      {:ok, audio_path} = HAL.Voice.TTS.synthesize("Hello, world!")

      # With custom options
      {:ok, audio_path} = HAL.Voice.TTS.synthesize("Hello!",
        voice_id: "custom_voice",
        stability: 0.8,
        similarity_boost: 0.9
      )

      # Clean up after use
      :ok = HAL.Voice.TTS.cleanup(audio_path)
  """

  require Logger

  @base_url "https://api.elevenlabs.io/v1/text-to-speech"
  @default_voice_id "21m00Tcm4TlvDq8ikWAM"
  @default_model_id "eleven_monolingual_v1"
  @default_stability 0.5
  @default_similarity_boost 0.75

  @type synthesize_opts :: [
          api_key: String.t(),
          voice_id: String.t(),
          model_id: String.t(),
          stability: float(),
          similarity_boost: float(),
          http_client: function()
        ]

  @doc """
  Synthesizes text to speech using ElevenLabs API.

  ## Options

    * `:api_key` - ElevenLabs API key (defaults to config)
    * `:voice_id` - Voice ID to use (defaults to config or "21m00Tcm4TlvDq8ikWAM")
    * `:model_id` - Model ID (defaults to "eleven_monolingual_v1")
    * `:stability` - Voice stability 0.0-1.0 (defaults to 0.5)
    * `:similarity_boost` - Similarity boost 0.0-1.0 (defaults to 0.75)
    * `:http_client` - Custom HTTP client function for testing

  ## Returns

    * `{:ok, audio_file_path}` - Path to the generated MP3 file
    * `{:error, reason}` - Error description

  ## Examples

      iex> HAL.Voice.TTS.synthesize("Hello, world!")
      {:ok, "/tmp/hal_tts_abc123.mp3"}

      iex> HAL.Voice.TTS.synthesize("")
      {:error, "Text cannot be empty"}
  """
  @spec synthesize(String.t() | nil, synthesize_opts()) ::
          {:ok, String.t()} | {:error, String.t()}
  def synthesize(text, opts \\ [])

  def synthesize(nil, _opts), do: {:error, "Text cannot be empty"}
  def synthesize("", _opts), do: {:error, "Text cannot be empty"}

  def synthesize(text, opts) when is_binary(text) do
    voice_id = Keyword.get(opts, :voice_id, default_voice_id())
    model_id = Keyword.get(opts, :model_id, @default_model_id)
    stability = Keyword.get(opts, :stability, @default_stability)
    similarity_boost = Keyword.get(opts, :similarity_boost, @default_similarity_boost)
    http_client = Keyword.get(opts, :http_client, &default_http_client/4)
    api_key = Keyword.get(opts, :api_key, get_api_key())

    url = "#{@base_url}/#{voice_id}"

    body =
      Jason.encode!(%{
        text: text,
        model_id: model_id,
        voice_settings: %{
          stability: stability,
          similarity_boost: similarity_boost
        }
      })

    headers = [
      {"Accept", "audio/mpeg"},
      {"Content-Type", "application/json"},
      {"xi-api-key", api_key}
    ]

    Logger.debug("TTS: Synthesizing text with voice_id=#{voice_id}")

    case http_client.(url, body, headers, recv_timeout: 30_000) do
      {:ok, %{status_code: 200, body: audio_data}} ->
        save_audio_file(audio_data)

      {:ok, %{status_code: status_code, body: error_body}} ->
        Logger.error("TTS API error: status=#{status_code}, body=#{error_body}")
        {:error, "API error: status #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("TTS HTTP error: #{inspect(reason)}")
        {:error, "HTTP error: #{inspect(reason)}"}

      {:error, reason} ->
        Logger.error("TTS error: #{inspect(reason)}")
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end

  @doc """
  Cleans up (deletes) an audio file created by synthesize/2.

  Always returns :ok, even if the file doesn't exist.

  ## Examples

      iex> HAL.Voice.TTS.cleanup("/tmp/hal_tts_abc123.mp3")
      :ok
  """
  @spec cleanup(String.t()) :: :ok
  def cleanup(file_path) when is_binary(file_path) do
    case File.rm(file_path) do
      :ok ->
        Logger.debug("TTS: Cleaned up file #{file_path}")
        :ok

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        Logger.warning("TTS: Failed to clean up #{file_path}: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Returns the default voice ID from configuration or fallback.
  """
  @spec default_voice_id() :: String.t()
  def default_voice_id do
    get_config(:voice_id, @default_voice_id)
  end

  # Private functions

  defp save_audio_file(audio_data) do
    tmp_dir = System.tmp_dir!()
    filename = "hal_tts_#{generate_id()}.mp3"
    file_path = Path.join(tmp_dir, filename)

    case File.write(file_path, audio_data) do
      :ok ->
        Logger.debug("TTS: Saved audio to #{file_path}")
        {:ok, file_path}

      {:error, reason} ->
        Logger.error("TTS: Failed to save audio: #{inspect(reason)}")
        {:error, "Failed to save audio file: #{inspect(reason)}"}
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp default_http_client(url, body, headers, opts) do
    HTTPoison.post(url, body, headers, opts)
  end

  defp get_api_key do
    get_config(:api_key, System.get_env("ELEVENLABS_API_KEY") || "")
  end

  defp get_config(key, default) do
    :hal
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, default)
  end
end
