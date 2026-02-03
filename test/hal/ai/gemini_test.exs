defmodule Hal.AI.GeminiTest do
  use ExUnit.Case, async: true

  alias Hal.AI.Gemini

  describe "behaviour compliance" do
    test "implements Provider behaviour" do
      assert Gemini.name() == :gemini
    end

    test "supports?/1 returns true for simple questions" do
      assert Gemini.supports?("What is the capital of France?")
      assert Gemini.supports?("Tell me about quantum physics")
      assert Gemini.supports?("How does photosynthesis work?")
    end

    test "supports?/1 returns true for coding-related queries (can handle them too)" do
      # Gemini can handle coding questions, it's just not the preferred choice
      assert Gemini.supports?("Write a function that sorts a list")
    end

    test "cost_estimate/1 returns low cost for short messages" do
      cost = Gemini.cost_estimate("Hello world")
      assert is_float(cost)
      assert cost < 0.01
    end

    test "cost_estimate/1 scales with message length" do
      short_cost = Gemini.cost_estimate("Hi")
      long_cost = Gemini.cost_estimate(String.duplicate("word ", 1000))
      assert long_cost > short_cost
    end
  end

  describe "prompt/3" do
    test "makes HTTP request to Google AI API" do
      request_ref = make_ref()

      http_client = fn url, body, headers, _opts ->
        send(self(), {:request, request_ref, url, body, headers})

        {:ok,
         %{
           status_code: 200,
           body:
             Jason.encode!(%{
               "candidates" => [
                 %{
                   "content" => %{
                     "parts" => [%{"text" => "Paris is the capital of France."}],
                     "role" => "model"
                   }
                 }
               ]
             })
         }}
      end

      {:ok, response, nil} =
        Gemini.prompt(nil, "What is the capital of France?",
          http_client: http_client,
          api_key: "test-api-key"
        )

      assert response == "Paris is the capital of France."

      assert_receive {:request, ^request_ref, url, body, headers}

      assert String.contains?(url, "generativelanguage.googleapis.com")
      assert String.contains?(url, "gemini-2.5-flash")
      assert {"Content-Type", "application/json"} in headers

      decoded_body = Jason.decode!(body)
      assert decoded_body["contents"]
    end

    test "returns error on API failure" do
      http_client = fn _url, _body, _headers, _opts ->
        {:ok,
         %{
           status_code: 400,
           body: Jason.encode!(%{"error" => %{"message" => "Invalid request"}})
         }}
      end

      {:error, reason} =
        Gemini.prompt(nil, "Hello", http_client: http_client, api_key: "test-api-key")

      assert reason =~ "Invalid request"
    end

    test "returns error on HTTP error" do
      http_client = fn _url, _body, _headers, _opts ->
        {:error, %{reason: :timeout}}
      end

      {:error, reason} =
        Gemini.prompt(nil, "Hello", http_client: http_client, api_key: "test-api-key")

      assert reason =~ "HTTP error"
    end

    test "handles missing API key" do
      # Clear any configured API key and use empty string
      # Note: api_key: nil falls back to config/env, so use empty string to force error
      {:error, reason} = Gemini.prompt(nil, "Hello", api_key: "")
      assert reason =~ "API key"
    end

    test "uses provided API key" do
      http_client = fn url, _body, _headers, _opts ->
        send(self(), {:url, url})

        {:ok,
         %{
           status_code: 200,
           body:
             Jason.encode!(%{
               "candidates" => [
                 %{"content" => %{"parts" => [%{"text" => "Response"}]}}
               ]
             })
         }}
      end

      {:ok, _, _} =
        Gemini.prompt(nil, "Hello", http_client: http_client, api_key: "test-key-123")

      assert_receive {:url, url}
      assert String.contains?(url, "key=test-key-123")
    end

    test "ignores session_id (Gemini is stateless)" do
      http_client = fn _url, _body, _headers, _opts ->
        {:ok,
         %{
           status_code: 200,
           body:
             Jason.encode!(%{
               "candidates" => [
                 %{"content" => %{"parts" => [%{"text" => "Response"}]}}
               ]
             })
         }}
      end

      # Session ID is passed but ignored for Gemini
      {:ok, _, session_id} =
        Gemini.prompt("existing-session-123", "Hello",
          http_client: http_client,
          api_key: "test-api-key"
        )

      # Gemini doesn't maintain sessions, so session_id should be nil
      assert is_nil(session_id)
    end
  end

  describe "build_request_body/2" do
    test "builds valid request body" do
      body = Gemini.build_request_body("Hello world", [])
      decoded = Jason.decode!(body)

      assert decoded["contents"] == [
               %{
                 "parts" => [%{"text" => "Hello world"}],
                 "role" => "user"
               }
             ]

      assert decoded["generationConfig"]["temperature"] == 0.7
      assert decoded["generationConfig"]["maxOutputTokens"] == 2048
    end

    test "includes system instruction when provided" do
      body = Gemini.build_request_body("Hello", system_prompt: "Be helpful")
      decoded = Jason.decode!(body)

      assert decoded["systemInstruction"] == %{
               "parts" => [%{"text" => "Be helpful"}]
             }
    end
  end

  describe "parse_response/1" do
    test "extracts text from valid response" do
      response_body = %{
        "candidates" => [
          %{
            "content" => %{
              "parts" => [%{"text" => "Hello!"}],
              "role" => "model"
            }
          }
        ]
      }

      {:ok, text} = Gemini.parse_response(response_body)
      assert text == "Hello!"
    end

    test "joins multiple parts" do
      response_body = %{
        "candidates" => [
          %{
            "content" => %{
              "parts" => [
                %{"text" => "Part 1. "},
                %{"text" => "Part 2."}
              ]
            }
          }
        ]
      }

      {:ok, text} = Gemini.parse_response(response_body)
      assert text == "Part 1. Part 2."
    end

    test "returns error for empty candidates" do
      response_body = %{"candidates" => []}
      {:error, reason} = Gemini.parse_response(response_body)
      assert reason =~ "No response"
    end

    test "returns error for blocked response" do
      response_body = %{
        "candidates" => [
          %{"finishReason" => "SAFETY", "content" => nil}
        ]
      }

      {:error, reason} = Gemini.parse_response(response_body)
      assert reason =~ "blocked"
    end
  end

  # Integration tests - require actual Google AI API key
  describe "integration with real Gemini API" do
    @tag :integration
    @tag :slow
    @tag timeout: 60_000
    test "can execute a simple prompt" do
      api_key = System.get_env("GOOGLE_AI_API_KEY")

      if is_nil(api_key) do
        IO.puts("Skipping Gemini integration test - GOOGLE_AI_API_KEY not set")
      else
        result = Gemini.prompt(nil, "What is 2 + 2? Reply with just the number.")

        case result do
          {:ok, response, _session_id} ->
            assert is_binary(response)
            assert String.contains?(response, "4")

          {:error, reason} ->
            flunk("Unexpected error: #{inspect(reason)}")
        end
      end
    end
  end
end
