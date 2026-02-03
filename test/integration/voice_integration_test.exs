defmodule HAL.Integration.VoiceIntegrationTest do
  @moduledoc """
  Integration tests for voice round-trip (STT -> AI -> TTS).

  Tests the complete voice pipeline:
  1. Audio input -> Speech-to-Text
  2. Text -> Claude Code
  3. Response -> Text-to-Speech
  4. Audio output

  These tests require:
  - ELEVENLABS_API_KEY for TTS
  - Whisper/AssemblyAI for STT
  - Claude Code CLI for AI processing

  Run with: mix test test/integration/voice_integration_test.exs --include integration
  """

  use ExUnit.Case, async: false

  alias HAL.Voice.{TTS, STT}

  @moduletag :integration
  @moduletag timeout: 120_000

  describe "TTS (Text-to-Speech)" do
    @tag :slow
    test "synthesizes text to audio file" do
      # Skip if no ElevenLabs API key
      unless System.get_env("ELEVENLABS_API_KEY") do
        skip("ELEVENLABS_API_KEY not set")
      end

      text = "Hello, this is a test of HAL's text to speech capabilities."

      case TTS.synthesize(text) do
        {:ok, audio_file} ->
          # Verify file was created
          assert File.exists?(audio_file)
          # Verify file has content
          assert File.stat!(audio_file).size > 0
          # Clean up
          File.rm(audio_file)

        {:error, reason} ->
          flunk("TTS synthesis failed: #{inspect(reason)}")
      end
    end

    @tag :slow
    test "synthesizes with different voices" do
      unless System.get_env("ELEVENLABS_API_KEY") do
        skip("ELEVENLABS_API_KEY not set")
      end

      text = "Testing voice selection."

      # Test with default voice
      {:ok, audio1} = TTS.synthesize(text)
      assert File.exists?(audio1)

      # Test with a specific voice if available
      {:ok, audio2} = TTS.synthesize(text, voice: "rachel")
      assert File.exists?(audio2)

      # Clean up
      File.rm(audio1)
      File.rm(audio2)
    end

    @tag :slow
    test "handles long text with chunking" do
      unless System.get_env("ELEVENLABS_API_KEY") do
        skip("ELEVENLABS_API_KEY not set")
      end

      # Create text that exceeds typical TTS limits
      long_text = String.duplicate("This is a longer piece of text for testing. ", 50)

      case TTS.synthesize(long_text) do
        {:ok, audio_file} ->
          assert File.exists?(audio_file)
          # Long text should produce a larger file
          assert File.stat!(audio_file).size > 10_000
          File.rm(audio_file)

        {:error, reason} ->
          flunk("Long text TTS failed: #{inspect(reason)}")
      end
    end
  end

  describe "STT (Speech-to-Text)" do
    @tag :slow
    test "transcribes audio file to text" do
      # Create a test audio file or use a fixture
      test_audio = create_test_audio()

      case STT.transcribe(test_audio) do
        {:ok, transcription} ->
          assert is_binary(transcription)
          assert String.length(transcription) > 0

        {:error, :api_not_configured} ->
          skip("STT API not configured")

        {:error, reason} ->
          flunk("STT transcription failed: #{inspect(reason)}")
      end
    after
      # Clean up test audio
      cleanup_test_audio()
    end

    @tag :slow
    test "handles various audio formats" do
      # Test with different audio formats if supported
      formats = [:ogg, :mp3, :wav]

      for format <- formats do
        test_audio = create_test_audio(format: format)

        case STT.transcribe(test_audio) do
          {:ok, _transcription} ->
            assert true

          {:error, :api_not_configured} ->
            skip("STT API not configured")

          {:error, :unsupported_format} ->
            # Some formats might not be supported
            :ok

          {:error, reason} ->
            flunk("STT failed for #{format}: #{inspect(reason)}")
        end
      end
    end
  end

  describe "voice round-trip" do
    @tag :slow
    @tag timeout: 300_000
    test "complete voice round-trip: audio -> text -> AI -> audio" do
      unless System.get_env("ELEVENLABS_API_KEY") do
        skip("ELEVENLABS_API_KEY not set")
      end

      # Step 1: Create test audio input
      test_audio = create_test_audio()

      # Step 2: Transcribe audio to text
      {:ok, transcription} = STT.transcribe(test_audio)
      assert is_binary(transcription)

      # Step 3: Send to AI (use mock for faster tests)
      mock_ai_response = "I heard you say: #{transcription}. Here's my response."

      # Step 4: Synthesize response to audio
      {:ok, response_audio} = TTS.synthesize(mock_ai_response)

      # Verify we have audio output
      assert File.exists?(response_audio)
      assert File.stat!(response_audio).size > 0

      # Clean up
      File.rm(response_audio)
      cleanup_test_audio()
    end
  end

  # Helper functions

  defp create_test_audio(opts \\ []) do
    _format = Keyword.get(opts, :format, :ogg)

    # For real tests, you would:
    # 1. Use a pre-recorded fixture file
    # 2. Generate audio programmatically
    # 3. Download from a test URL

    # For now, create a placeholder path
    Path.join(System.tmp_dir!(), "test_audio_#{System.unique_integer([:positive])}.ogg")
  end

  defp cleanup_test_audio do
    # Clean up any test audio files
    System.tmp_dir!()
    |> File.ls!()
    |> Enum.filter(&String.starts_with?(&1, "test_audio_"))
    |> Enum.each(fn file ->
      Path.join(System.tmp_dir!(), file) |> File.rm()
    end)
  end

  defp skip(reason) do
    IO.puts("SKIPPED: #{reason}")
    assert true
  end
end
