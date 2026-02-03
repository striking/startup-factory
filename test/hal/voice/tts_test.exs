defmodule HAL.Voice.TTSTest do
  use ExUnit.Case, async: true

  alias HAL.Voice.TTS

  @moduletag :voice

  describe "synthesize/2" do
    test "returns {:ok, audio_file_path} on successful synthesis" do
      # Mock successful API response
      mock_response = %HTTPoison.Response{
        status_code: 200,
        body: <<0, 1, 2, 3, 4, 5>>,
        headers: [{"content-type", "audio/mpeg"}]
      }

      opts = [
        http_client: fn _url, _body, _headers, _opts ->
          {:ok, mock_response}
        end
      ]

      result = TTS.synthesize("Hello, world!", opts)

      assert {:ok, file_path} = result
      assert String.ends_with?(file_path, ".mp3")
      assert File.exists?(file_path)

      # Clean up
      File.rm(file_path)
    end

    test "returns {:error, reason} when API returns error status" do
      mock_response = %HTTPoison.Response{
        status_code: 401,
        body: ~s({"detail": {"message": "Invalid API key"}}),
        headers: []
      }

      opts = [
        http_client: fn _url, _body, _headers, _opts ->
          {:ok, mock_response}
        end
      ]

      result = TTS.synthesize("Hello, world!", opts)

      assert {:error, reason} = result
      assert reason =~ "API error"
    end

    test "returns {:error, reason} when HTTP request fails" do
      opts = [
        http_client: fn _url, _body, _headers, _opts ->
          {:error, %HTTPoison.Error{reason: :timeout}}
        end
      ]

      result = TTS.synthesize("Hello, world!", opts)

      assert {:error, reason} = result
      assert reason =~ "HTTP error"
    end

    test "returns {:error, reason} when text is empty" do
      result = TTS.synthesize("")
      assert {:error, "Text cannot be empty"} = result
    end

    test "returns {:error, reason} when text is nil" do
      result = TTS.synthesize(nil)
      assert {:error, "Text cannot be empty"} = result
    end

    test "uses custom voice_id when provided" do
      mock_response = %HTTPoison.Response{
        status_code: 200,
        body: <<0, 1, 2, 3>>,
        headers: [{"content-type", "audio/mpeg"}]
      }

      custom_voice_id = "custom_voice_123"
      captured_url = :ets.new(:captured_url, [:set, :public])

      opts = [
        voice_id: custom_voice_id,
        http_client: fn url, _body, _headers, _opts ->
          :ets.insert(captured_url, {:url, url})
          {:ok, mock_response}
        end
      ]

      {:ok, file_path} = TTS.synthesize("Test", opts)

      [{:url, url}] = :ets.lookup(captured_url, :url)
      assert url =~ custom_voice_id

      # Clean up
      File.rm(file_path)
      :ets.delete(captured_url)
    end

    test "uses stability and similarity_boost settings when provided" do
      mock_response = %HTTPoison.Response{
        status_code: 200,
        body: <<0, 1, 2, 3>>,
        headers: [{"content-type", "audio/mpeg"}]
      }

      captured_body = :ets.new(:captured_body, [:set, :public])

      opts = [
        stability: 0.8,
        similarity_boost: 0.9,
        http_client: fn _url, body, _headers, _opts ->
          :ets.insert(captured_body, {:body, body})
          {:ok, mock_response}
        end
      ]

      {:ok, file_path} = TTS.synthesize("Test", opts)

      [{:body, body}] = :ets.lookup(captured_body, :body)
      decoded = Jason.decode!(body)

      assert decoded["voice_settings"]["stability"] == 0.8
      assert decoded["voice_settings"]["similarity_boost"] == 0.9

      # Clean up
      File.rm(file_path)
      :ets.delete(captured_body)
    end
  end

  describe "cleanup/1" do
    test "deletes the audio file" do
      # Create a temp file
      tmp_dir = System.tmp_dir!()
      file_path = Path.join(tmp_dir, "test_audio_#{:rand.uniform(1_000_000)}.mp3")
      File.write!(file_path, "test content")

      assert File.exists?(file_path)

      :ok = TTS.cleanup(file_path)

      refute File.exists?(file_path)
    end

    test "returns :ok even if file does not exist" do
      result = TTS.cleanup("/nonexistent/file.mp3")
      assert :ok = result
    end
  end

  describe "configuration" do
    test "default_voice_id returns configured or default value" do
      voice_id = TTS.default_voice_id()
      assert is_binary(voice_id)
      assert String.length(voice_id) > 0
    end
  end

  describe "integration tests" do
    @describetag :integration
    @describetag :skip

    test "synthesizes text with real ElevenLabs API" do
      # This test requires ELEVENLABS_API_KEY to be set
      api_key = System.get_env("ELEVENLABS_API_KEY")

      if api_key do
        result = TTS.synthesize("Hello, this is a test.", api_key: api_key)
        assert {:ok, file_path} = result
        assert File.exists?(file_path)
        assert File.stat!(file_path).size > 0

        # Clean up
        TTS.cleanup(file_path)
      end
    end
  end
end
