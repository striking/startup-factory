defmodule HAL.Voice.STTTest do
  use ExUnit.Case, async: true

  alias HAL.Voice.STT

  @moduletag :voice

  # Sample audio file path for testing
  @sample_audio_path "/tmp/test_audio_sample.mp3"

  setup do
    # Create a sample audio file for testing
    File.write!(@sample_audio_path, "fake audio content for testing")

    on_exit(fn ->
      File.rm(@sample_audio_path)
    end)

    :ok
  end

  describe "transcribe/2" do
    test "returns {:ok, text} on successful transcription" do
      mock_response = %HTTPoison.Response{
        status_code: 200,
        body: ~s({"text": "Hello, this is a test transcription."}),
        headers: [{"content-type", "application/json"}]
      }

      opts = [
        http_client: fn _url, _body, _headers, _opts ->
          {:ok, mock_response}
        end
      ]

      result = STT.transcribe(@sample_audio_path, opts)

      assert {:ok, "Hello, this is a test transcription."} = result
    end

    test "returns {:error, reason} when API returns error status" do
      mock_response = %HTTPoison.Response{
        status_code: 401,
        body: ~s({"error": {"message": "Invalid API key", "type": "invalid_request_error"}}),
        headers: []
      }

      opts = [
        http_client: fn _url, _body, _headers, _opts ->
          {:ok, mock_response}
        end
      ]

      result = STT.transcribe(@sample_audio_path, opts)

      assert {:error, reason} = result
      assert reason =~ "API error"
    end

    test "returns {:error, reason} when HTTP request fails" do
      opts = [
        http_client: fn _url, _body, _headers, _opts ->
          {:error, %HTTPoison.Error{reason: :timeout}}
        end
      ]

      result = STT.transcribe(@sample_audio_path, opts)

      assert {:error, reason} = result
      assert reason =~ "HTTP error"
    end

    test "returns {:error, reason} when file does not exist" do
      result = STT.transcribe("/nonexistent/file.mp3")

      assert {:error, reason} = result
      assert reason =~ "File not found"
    end

    test "returns {:error, reason} when file path is empty" do
      result = STT.transcribe("")

      assert {:error, "File path cannot be empty"} = result
    end

    test "returns {:error, reason} when file path is nil" do
      result = STT.transcribe(nil)

      assert {:error, "File path cannot be empty"} = result
    end

    test "uses custom model when provided" do
      mock_response = %HTTPoison.Response{
        status_code: 200,
        body: ~s({"text": "Test"}),
        headers: []
      }

      captured_body = :ets.new(:captured_body, [:set, :public])

      opts = [
        model: "whisper-1-turbo",
        http_client: fn _url, body, _headers, _opts ->
          :ets.insert(captured_body, {:body, body})
          {:ok, mock_response}
        end
      ]

      {:ok, _text} = STT.transcribe(@sample_audio_path, opts)

      [{:body, body}] = :ets.lookup(captured_body, :body)

      # Check that the multipart body contains the model
      # Body is {:multipart, boundary, body_string}
      {:multipart, _boundary, body_string} = body
      assert body_string =~ "whisper-1-turbo"

      :ets.delete(captured_body)
    end

    test "uses language hint when provided" do
      mock_response = %HTTPoison.Response{
        status_code: 200,
        body: ~s({"text": "Bonjour"}),
        headers: []
      }

      captured_body = :ets.new(:captured_body, [:set, :public])

      opts = [
        language: "fr",
        http_client: fn _url, body, _headers, _opts ->
          :ets.insert(captured_body, {:body, body})
          {:ok, mock_response}
        end
      ]

      {:ok, "Bonjour"} = STT.transcribe(@sample_audio_path, opts)

      [{:body, body}] = :ets.lookup(captured_body, :body)

      # Check that the multipart body contains the language
      # Body is {:multipart, boundary, body_string}
      {:multipart, _boundary, body_string} = body
      assert body_string =~ "fr"

      :ets.delete(captured_body)
    end

    test "handles JSON parse errors gracefully" do
      mock_response = %HTTPoison.Response{
        status_code: 200,
        body: "not valid json",
        headers: []
      }

      opts = [
        http_client: fn _url, _body, _headers, _opts ->
          {:ok, mock_response}
        end
      ]

      result = STT.transcribe(@sample_audio_path, opts)

      assert {:error, reason} = result
      assert reason =~ "Failed to parse" or reason =~ "JSON"
    end

    test "handles response with missing text field" do
      mock_response = %HTTPoison.Response{
        status_code: 200,
        body: ~s({"result": "no text field"}),
        headers: []
      }

      opts = [
        http_client: fn _url, _body, _headers, _opts ->
          {:ok, mock_response}
        end
      ]

      result = STT.transcribe(@sample_audio_path, opts)

      assert {:error, reason} = result
      assert reason =~ "text"
    end
  end

  describe "supported_formats/0" do
    test "returns list of supported audio formats" do
      formats = STT.supported_formats()

      assert is_list(formats)
      assert "mp3" in formats
      assert "wav" in formats
      assert "m4a" in formats
    end
  end

  describe "validate_file/1" do
    test "returns :ok for supported file formats" do
      result = STT.validate_file(@sample_audio_path)
      assert :ok = result
    end

    test "returns :ok for wav files" do
      wav_path = "/tmp/test_audio.wav"
      File.write!(wav_path, "fake wav content")

      result = STT.validate_file(wav_path)
      assert :ok = result

      File.rm(wav_path)
    end

    test "returns {:error, reason} for unsupported formats" do
      txt_path = "/tmp/test.txt"
      File.write!(txt_path, "text content")

      result = STT.validate_file(txt_path)
      assert {:error, reason} = result
      assert reason =~ "Unsupported"

      File.rm(txt_path)
    end

    test "returns {:error, reason} for non-existent files" do
      result = STT.validate_file("/nonexistent/file.mp3")
      assert {:error, reason} = result
      assert reason =~ "not found" or reason =~ "does not exist"
    end
  end

  describe "integration tests" do
    @describetag :integration
    @describetag :skip

    test "transcribes audio with real Whisper API" do
      # This test requires OPENAI_API_KEY to be set
      api_key = System.get_env("OPENAI_API_KEY")

      if api_key do
        # Create a real audio file or use existing test fixture
        # For now, we skip if no test audio file exists
        test_audio = System.get_env("TEST_AUDIO_PATH")

        if test_audio && File.exists?(test_audio) do
          result = STT.transcribe(test_audio, api_key: api_key)
          assert {:ok, text} = result
          assert is_binary(text)
          assert String.length(text) > 0
        end
      end
    end
  end
end
