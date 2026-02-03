defmodule HAL.Voice.STT do
  @moduledoc """
  Speech-to-Text module using OpenAI's Whisper API.

  Provides functionality to transcribe audio files to text.

  ## Configuration

  The following configuration options are available:

      config :hal, HAL.Voice.STT,
        api_key: "your_openai_api_key"

  ## Usage

      # Basic usage
      {:ok, text} = HAL.Voice.STT.transcribe("/path/to/audio.mp3")

      # With custom options
      {:ok, text} = HAL.Voice.STT.transcribe("/path/to/audio.mp3",
        model: "whisper-1",
        language: "en"
      )

  ## Supported Formats

      HAL.Voice.STT.supported_formats()
      # => ["mp3", "mp4", "mpeg", "mpga", "m4a", "wav", "webm", "ogg"]
  """

  require Logger

  @base_url "https://api.openai.com/v1/audio/transcriptions"
  @default_model "whisper-1"
  @supported_formats ["mp3", "mp4", "mpeg", "mpga", "m4a", "wav", "webm", "ogg"]

  @type transcribe_opts :: [
          api_key: String.t(),
          model: String.t(),
          language: String.t(),
          prompt: String.t(),
          http_client: function()
        ]

  @doc """
  Transcribes an audio file to text using OpenAI's Whisper API.

  ## Options

    * `:api_key` - OpenAI API key (defaults to config)
    * `:model` - Model to use (defaults to "whisper-1")
    * `:language` - Language hint in ISO-639-1 format (optional)
    * `:prompt` - Optional text to guide transcription style
    * `:http_client` - Custom HTTP client function for testing

  ## Returns

    * `{:ok, text}` - Transcribed text
    * `{:error, reason}` - Error description

  ## Examples

      iex> HAL.Voice.STT.transcribe("/path/to/audio.mp3")
      {:ok, "Hello, this is a test transcription."}

      iex> HAL.Voice.STT.transcribe("/nonexistent/file.mp3")
      {:error, "File not found: /nonexistent/file.mp3"}
  """
  @spec transcribe(String.t() | nil, transcribe_opts()) ::
          {:ok, String.t()} | {:error, String.t()}
  def transcribe(file_path, opts \\ [])

  def transcribe(nil, _opts), do: {:error, "File path cannot be empty"}
  def transcribe("", _opts), do: {:error, "File path cannot be empty"}

  def transcribe(file_path, opts) when is_binary(file_path) do
    with :ok <- check_file_exists(file_path),
         :ok <- validate_format(file_path) do
      do_transcribe(file_path, opts)
    end
  end

  @doc """
  Returns list of supported audio file formats.

  ## Examples

      iex> HAL.Voice.STT.supported_formats()
      ["mp3", "mp4", "mpeg", "mpga", "m4a", "wav", "webm", "ogg"]
  """
  @spec supported_formats() :: [String.t()]
  def supported_formats, do: @supported_formats

  @doc """
  Validates that a file exists and has a supported format.

  ## Examples

      iex> HAL.Voice.STT.validate_file("/path/to/audio.mp3")
      :ok

      iex> HAL.Voice.STT.validate_file("/path/to/file.txt")
      {:error, "Unsupported audio format: txt"}
  """
  @spec validate_file(String.t()) :: :ok | {:error, String.t()}
  def validate_file(file_path) when is_binary(file_path) do
    with :ok <- check_file_exists(file_path) do
      validate_format(file_path)
    end
  end

  # Private functions

  defp do_transcribe(file_path, opts) do
    model = Keyword.get(opts, :model, @default_model)
    language = Keyword.get(opts, :language)
    prompt = Keyword.get(opts, :prompt)
    api_key = Keyword.get(opts, :api_key, get_api_key())
    http_client = Keyword.get(opts, :http_client, &default_http_client/4)

    # Build multipart form data
    form_data = build_form_data(file_path, model, language, prompt)

    headers = [
      {"Authorization", "Bearer #{api_key}"}
    ]

    Logger.debug("STT: Transcribing file #{file_path} with model=#{model}")

    case http_client.(@base_url, form_data, headers, recv_timeout: 60_000) do
      {:ok, %{status_code: 200, body: body}} ->
        parse_response(body)

      {:ok, %{status_code: status_code, body: error_body}} ->
        Logger.error("STT API error: status=#{status_code}, body=#{error_body}")
        {:error, "API error: status #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("STT HTTP error: #{inspect(reason)}")
        {:error, "HTTP error: #{inspect(reason)}"}

      {:error, reason} ->
        Logger.error("STT error: #{inspect(reason)}")
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end

  defp build_form_data(file_path, model, language, prompt) do
    base_parts = [
      {:file, file_path},
      {"model", model}
    ]

    base_parts
    |> maybe_add_part("language", language)
    |> maybe_add_part("prompt", prompt)
    |> build_multipart_body()
  end

  defp maybe_add_part(parts, _key, nil), do: parts
  defp maybe_add_part(parts, key, value), do: parts ++ [{key, value}]

  defp build_multipart_body(parts) do
    # Create multipart form data as a string for HTTPoison
    boundary = generate_boundary()

    body =
      Enum.map_join(parts, "", fn
        {:file, file_path} ->
          format_file_part(file_path, boundary)

        {key, value} ->
          format_field_part(key, value, boundary)
      end) <> "--#{boundary}--\r\n"

    {:multipart, boundary, body}
  end

  defp format_file_part(file_path, boundary) do
    content = File.read!(file_path)
    filename = Path.basename(file_path)
    content_type = get_content_type(file_path)

    """
    --#{boundary}\r
    Content-Disposition: form-data; name="file"; filename="#{filename}"\r
    Content-Type: #{content_type}\r
    \r
    #{content}\r
    """
  end

  defp format_field_part(key, value, boundary) do
    """
    --#{boundary}\r
    Content-Disposition: form-data; name="#{key}"\r
    \r
    #{value}\r
    """
  end

  defp generate_boundary do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  @content_types %{
    "mp3" => "audio/mpeg",
    "mp4" => "audio/mp4",
    "mpeg" => "audio/mpeg",
    "mpga" => "audio/mpeg",
    "m4a" => "audio/m4a",
    "wav" => "audio/wav",
    "webm" => "audio/webm",
    "ogg" => "audio/ogg"
  }

  defp get_content_type(file_path) do
    ext = file_path |> Path.extname() |> String.trim_leading(".") |> String.downcase()
    Map.get(@content_types, ext, "application/octet-stream")
  end

  defp parse_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"text" => text}} ->
        {:ok, text}

      {:ok, _response} ->
        Logger.error("STT: Response missing text field")
        {:error, "Response missing text field"}

      {:error, reason} ->
        Logger.error("STT: Failed to parse JSON response: #{inspect(reason)}")
        {:error, "Failed to parse JSON response"}
    end
  end

  defp check_file_exists(file_path) do
    if File.exists?(file_path) do
      :ok
    else
      {:error, "File not found: #{file_path}"}
    end
  end

  defp validate_format(file_path) do
    ext = file_path |> Path.extname() |> String.trim_leading(".") |> String.downcase()

    if ext in @supported_formats do
      :ok
    else
      {:error, "Unsupported audio format: #{ext}"}
    end
  end

  defp default_http_client(url, {:multipart, boundary, body}, headers, opts) do
    content_type = "multipart/form-data; boundary=#{boundary}"
    full_headers = [{"Content-Type", content_type} | headers]

    HTTPoison.post(url, body, full_headers, opts)
  end

  defp get_api_key do
    config = Application.get_env(:hal, __MODULE__, [])

    Keyword.get(
      config,
      :api_key,
      System.get_env("OPENAI_API_KEY") || ""
    )
  end
end
