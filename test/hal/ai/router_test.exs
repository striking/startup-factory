defmodule Hal.AI.RouterTest do
  use ExUnit.Case, async: true

  alias Hal.AI.Router

  describe "route/2" do
    test "routes to forced provider when /claude command is used" do
      mock_provider = fn :claude_code, _session_id, _message, _opts ->
        {:ok, "Claude response", "session-123"}
      end

      {:ok, response, _session_id, provider} =
        Router.route("/claude What is Elixir?",
          provider_caller: mock_provider,
          session_id: nil
        )

      assert response == "Claude response"
      assert provider == :claude_code
    end

    test "routes to forced provider when /gemini command is used" do
      mock_provider = fn :gemini, _session_id, _message, _opts ->
        {:ok, "Gemini response", nil}
      end

      {:ok, response, _session_id, provider} =
        Router.route("/gemini What is the weather?",
          provider_caller: mock_provider,
          session_id: nil
        )

      assert response == "Gemini response"
      assert provider == :gemini
    end

    test "routes to forced provider when /codex command is used" do
      mock_provider = fn :codex, _session_id, _message, _opts ->
        {:ok, "Codex response", nil}
      end

      {:ok, response, _session_id, provider} =
        Router.route("/codex Generate a sorting function",
          provider_caller: mock_provider,
          session_id: nil
        )

      assert response == "Codex response"
      assert provider == :codex
    end

    test "routes to forced provider when /openai command is used" do
      mock_provider = fn :openai, _session_id, _message, _opts ->
        {:ok, "OpenAI response", "openai-session-123"}
      end

      {:ok, response, _session_id, provider} =
        Router.route("/openai Explain machine learning",
          provider_caller: mock_provider,
          session_id: nil
        )

      assert response == "OpenAI response"
      assert provider == :openai
    end

    test "routes to forced provider when /gpt command is used" do
      mock_provider = fn :openai, _session_id, _message, _opts ->
        {:ok, "GPT response", "openai-session-456"}
      end

      {:ok, response, _session_id, provider} =
        Router.route("/gpt Tell me a joke",
          provider_caller: mock_provider,
          session_id: nil
        )

      assert response == "GPT response"
      assert provider == :openai
    end

    test "routes coding tasks to Claude Code" do
      mock_provider = fn :claude_code, _session_id, message, _opts ->
        send(self(), {:called, :claude_code, message})
        {:ok, "Code written", "session-123"}
      end

      {:ok, _response, _session_id, provider} =
        Router.route("write a function that sorts a list",
          provider_caller: mock_provider,
          session_id: nil
        )

      assert provider == :claude_code
      assert_receive {:called, :claude_code, "write a function that sorts a list"}
    end

    test "routes simple questions to Gemini when enable_routing is true" do
      mock_provider = fn :gemini, _session_id, message, _opts ->
        send(self(), {:called, :gemini, message})
        {:ok, "France capital is Paris", nil}
      end

      {:ok, _response, _session_id, provider} =
        Router.route("What is the capital of France?",
          provider_caller: mock_provider,
          session_id: nil,
          enable_routing: true
        )

      assert provider == :gemini
      assert_receive {:called, :gemini, "What is the capital of France?"}
    end

    test "defaults to Claude Code when routing is disabled" do
      mock_provider = fn :claude_code, _session_id, _message, _opts ->
        {:ok, "Claude response", "session-123"}
      end

      {:ok, _response, _session_id, provider} =
        Router.route("What is the capital of France?",
          provider_caller: mock_provider,
          session_id: nil,
          enable_routing: false
        )

      assert provider == :claude_code
    end

    test "passes session_id to provider" do
      mock_provider = fn _provider, session_id, _message, _opts ->
        send(self(), {:session_id, session_id})
        {:ok, "Response", session_id}
      end

      Router.route("Write some code for me",
        provider_caller: mock_provider,
        session_id: "existing-session-123"
      )

      assert_receive {:session_id, "existing-session-123"}
    end

    test "returns error when provider fails" do
      mock_provider = fn _provider, _session_id, _message, _opts ->
        {:error, "API rate limit exceeded"}
      end

      # Use a coding task to ensure Claude Code is used
      {:error, reason} =
        Router.route("Write a function",
          provider_caller: mock_provider,
          session_id: nil,
          enable_fallback: false
        )

      assert reason == "API rate limit exceeded"
    end

    test "falls back to Claude Code when Gemini fails" do
      call_count = :counters.new(1, [:atomics])

      mock_provider = fn
        :gemini, _session_id, _message, _opts ->
          :counters.add(call_count, 1, 1)
          {:error, "Gemini API error"}

        :claude_code, _session_id, _message, _opts ->
          :counters.add(call_count, 1, 1)
          {:ok, "Claude fallback response", "session-123"}
      end

      {:ok, response, _session_id, provider} =
        Router.route("What is the weather?",
          provider_caller: mock_provider,
          session_id: nil,
          enable_routing: true,
          enable_fallback: true
        )

      # Should have tried Gemini first, then Claude Code
      assert :counters.get(call_count, 1) == 2
      assert response == "Claude fallback response"
      assert provider == :claude_code
    end

    test "does not fall back when fallback is disabled" do
      mock_provider = fn :gemini, _session_id, _message, _opts ->
        {:error, "Gemini API error"}
      end

      {:error, reason} =
        Router.route("What is the weather?",
          provider_caller: mock_provider,
          session_id: nil,
          enable_routing: true,
          enable_fallback: false
        )

      assert reason == "Gemini API error"
    end
  end

  describe "parse_command/1" do
    test "extracts /claude command" do
      {:claude_code, "Hello world"} = Router.parse_command("/claude Hello world")
    end

    test "extracts /gemini command" do
      {:gemini, "What is AI?"} = Router.parse_command("/gemini What is AI?")
    end

    test "extracts /codex command" do
      {:codex, "Generate code"} = Router.parse_command("/codex Generate code")
    end

    test "extracts /openai command" do
      {:openai, "Explain AI"} = Router.parse_command("/openai Explain AI")
    end

    test "extracts /gpt command as openai" do
      {:openai, "Tell me a story"} = Router.parse_command("/gpt Tell me a story")
    end

    test "returns nil for messages without command" do
      assert is_nil(Router.parse_command("Just a regular message"))
    end

    test "is case insensitive" do
      {:claude_code, "Hello"} = Router.parse_command("/CLAUDE Hello")
      {:gemini, "Hello"} = Router.parse_command("/GEMINI Hello")
    end

    test "handles empty message after command" do
      {:claude_code, ""} = Router.parse_command("/claude")
      {:gemini, ""} = Router.parse_command("/gemini   ")
    end
  end

  describe "determine_provider/1" do
    test "returns :claude_code for coding tasks" do
      assert Router.determine_provider("Write a function that calculates factorial") ==
               :claude_code

      assert Router.determine_provider("debug this code: def foo, do: :bar") == :claude_code
      assert Router.determine_provider("refactor the authentication module") == :claude_code
      assert Router.determine_provider("Fix the bug in lib/app/users.ex") == :claude_code
      assert Router.determine_provider("Create a test for the User module") == :claude_code
    end

    test "returns :gemini for simple questions" do
      assert Router.determine_provider("What is the capital of France?") == :gemini
      assert Router.determine_provider("How does photosynthesis work?") == :gemini
      assert Router.determine_provider("Tell me about quantum physics") == :gemini
      assert Router.determine_provider("Explain machine learning") == :gemini
    end

    test "returns :claude_code for file path mentions" do
      assert Router.determine_provider("Read the file at /src/app.js") == :claude_code
      assert Router.determine_provider("What's in lib/hal/router.ex?") == :claude_code
    end

    test "returns :claude_code for code block detection" do
      message = """
      Here's my code:
      ```elixir
      def hello, do: :world
      ```
      What's wrong with it?
      """

      assert Router.determine_provider(message) == :claude_code
    end

    test "defaults to :gemini for ambiguous messages" do
      assert Router.determine_provider("Hello, how are you?") == :gemini
    end
  end

  describe "coding_task?/1" do
    test "returns true for coding keywords" do
      assert Router.coding_task?("write a function")
      assert Router.coding_task?("Write code to")
      assert Router.coding_task?("debug this issue")
      assert Router.coding_task?("refactor the module")
      assert Router.coding_task?("fix the bug in")
      assert Router.coding_task?("create a test for")
      assert Router.coding_task?("implement the feature")
      assert Router.coding_task?("edit the file")
      assert Router.coding_task?("read the source")
    end

    test "returns true for file path patterns" do
      assert Router.coding_task?("Look at /src/app.js")
      assert Router.coding_task?("Check lib/hal/router.ex")
      assert Router.coding_task?("What's in ./config/config.exs?")
    end

    test "returns true for code blocks" do
      assert Router.coding_task?("```python\nprint('hello')\n```")
      assert Router.coding_task?("Here's the code: ```def foo```")
    end

    test "returns false for regular questions" do
      refute Router.coding_task?("What is the weather today?")
      refute Router.coding_task?("Tell me about history")
      refute Router.coding_task?("How does the economy work?")
    end
  end

  describe "simple_question?/1" do
    test "returns true for question patterns" do
      assert Router.simple_question?("What is machine learning?")
      assert Router.simple_question?("How does DNA work?")
      assert Router.simple_question?("Why is the sky blue?")
      assert Router.simple_question?("When was the moon landing?")
      assert Router.simple_question?("Who invented the telephone?")
      assert Router.simple_question?("Where is Mount Everest?")
    end

    test "returns true for explanation requests" do
      assert Router.simple_question?("Explain quantum physics")
      assert Router.simple_question?("Tell me about black holes")
      assert Router.simple_question?("Describe the water cycle")
    end

    test "returns false for coding-related questions" do
      # Even with question words, coding context overrides
      refute Router.simple_question?("What does this code do? ```def foo```")
      refute Router.simple_question?("How do I fix this function?")
    end
  end

  describe "cost_estimation" do
    test "estimates cost for different providers" do
      # OpenAI (GPT-4-turbo) is most expensive, then Claude Code, then Gemini
      claude_cost = Router.estimate_cost(:claude_code, "Short message")
      gemini_cost = Router.estimate_cost(:gemini, "Short message")
      openai_cost = Router.estimate_cost(:openai, "Short message")

      assert is_float(claude_cost)
      assert is_float(gemini_cost)
      assert is_float(openai_cost)
      assert claude_cost > gemini_cost
      assert openai_cost > gemini_cost
      assert openai_cost > claude_cost
    end
  end

  describe "provider configuration" do
    test "respects default_provider config" do
      mock_provider = fn :gemini, _session_id, _message, _opts ->
        {:ok, "Gemini response", nil}
      end

      {:ok, _response, _session_id, provider} =
        Router.route("Hello",
          provider_caller: mock_provider,
          session_id: nil,
          default_provider: :gemini,
          enable_routing: false
        )

      assert provider == :gemini
    end
  end
end
