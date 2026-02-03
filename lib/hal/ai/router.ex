defmodule Hal.AI.Router do
  @moduledoc """
  Intelligent router for AI provider selection.

  The Router determines which AI provider to use based on:
  1. Explicit user commands (/claude, /gemini, /codex)
  2. Message content analysis (coding vs. general questions)
  3. Session preferences
  4. Cost optimization

  ## Routing Logic

  ```
  Message received
        │
        ▼
  ┌─────────────────┐
  │ Force provider? │──Yes──▶ Use forced provider
  │ (/claude, etc.) │
  └────────┬────────┘
           │ No
           ▼
  ┌─────────────────┐
  │ Routing enabled?│──No───▶ Use default provider
  └────────┬────────┘
           │ Yes
           ▼
  ┌─────────────────┐
  │ Coding task?    │──Yes──▶ Claude Code
  │ (code, files)   │
  └────────┬────────┘
           │ No
           ▼
  ┌─────────────────┐
  │ Simple question?│──Yes──▶ Gemini (fast, cheap)
  └────────┬────────┘
           │ No
           ▼
      Default provider
  ```

  ## Configuration

  In `config/runtime.exs`:

      config :hal, Hal.AI.Router,
        default_provider: :claude_code,
        enable_routing: true,
        enable_fallback: true

  ## User Commands

  - `/claude <message>` - Force Claude Code
  - `/gemini <message>` - Force Gemini
  - `/openai <message>` - Force OpenAI GPT-4
  - `/codex <message>` - Force Codex

  ## Usage

      # Simple routing
      {:ok, response, session_id, provider} = Router.route("What is Elixir?",
        session_id: nil
      )

      # With force command
      {:ok, response, session_id, :claude_code} = Router.route("/claude Help me code",
        session_id: nil
      )
  """

  require Logger

  alias Hal.AI.ClaudeCode
  alias Hal.AI.Gemini
  alias Hal.AI.OpenAI
  alias HAL.Memory
  alias HAL.Memory.Truncation
  alias HAL.Resilience.CircuitBreaker
  alias HAL.Resilience.Supervisor, as: ResilienceSupervisor

  # Get configured Claude client (real or mock)
  # Priority: configured mock > AgentSDK (if available) > ClaudePythonClient > ClaudeCode CLI
  defp claude_client do
    configured = Application.get_env(:hal, :claude_client)

    cond do
      # Explicit mock configuration (for tests)
      configured != nil and configured != Hal.AI.ClaudePythonClient ->
        configured

      # Try AgentSDK first (TypeScript SDK via Port)
      HAL.AI.AgentSDK.available?() ->
        HAL.AI.AgentSDK

      # Fall back to Python client
      configured == Hal.AI.ClaudePythonClient ->
        Hal.AI.ClaudePythonClient

      # Final fallback
      true ->
        Hal.AI.ClaudeCode
    end
  end

  # Use SoulLoader for system prompt (includes .claude/ files)
  alias HAL.Autonomy.SoulLoader

  @type provider :: :claude_code | :gemini | :openai | :codex
  @type session_id :: String.t() | nil
  @type response :: String.t() | map()

  # Client API

  @doc """
  Routes a message to the appropriate AI provider.

  ## Options

    * `:session_id` - Session ID for conversation continuity
    * `:provider_caller` - Function to call providers (for testing)
    * `:enable_routing` - Whether to use intelligent routing (default: config value)
    * `:enable_fallback` - Whether to fall back on failure (default: true)
    * `:default_provider` - Default provider when routing is disabled (default: :claude_code)

  ## Returns

    * `{:ok, response, session_id, provider}` - Success with response, new session ID, and provider used
    * `{:error, reason}` - Error with reason
  """
  @spec route(String.t(), keyword()) ::
          {:ok, response(), session_id(), provider()} | {:error, term()}
  def route(message, opts \\ []) do
    session_id = Keyword.get(opts, :session_id)
    provider_caller = Keyword.get(opts, :provider_caller, &default_provider_caller/4)
    enable_routing = Keyword.get(opts, :enable_routing, get_config(:enable_routing, true))
    enable_fallback = Keyword.get(opts, :enable_fallback, get_config(:enable_fallback, true))

    default_provider =
      Keyword.get(opts, :default_provider, get_config(:default_provider, :claude_code))

    # Check for forced provider command
    case parse_command(message) do
      {provider, stripped_message} ->
        call_provider(provider, session_id, stripped_message, provider_caller, opts)

      nil ->
        # Determine provider based on message content
        provider =
          if enable_routing do
            determine_provider(message)
          else
            default_provider
          end

        result = call_provider(provider, session_id, message, provider_caller, opts)

        # Handle fallback if enabled and initial provider failed
        case result do
          {:error, {:circuit_open, _}} when enable_fallback and provider != :claude_code ->
            Logger.info("Circuit open for #{provider}, falling back to Claude Code")
            call_provider(:claude_code, session_id, message, provider_caller, opts)

          {:error, _reason} when enable_fallback and provider != :claude_code ->
            Logger.info("Falling back to Claude Code after #{provider} failure")
            call_provider(:claude_code, session_id, message, provider_caller, opts)

          other ->
            other
        end
    end
  end

  @doc """
  Parses a provider command from a message.

  ## Examples

      iex> Router.parse_command("/claude Hello world")
      {:claude_code, "Hello world"}

      iex> Router.parse_command("Regular message")
      nil
  """
  @spec parse_command(String.t()) :: {provider(), String.t()} | nil
  def parse_command(message) do
    message = String.trim(message)

    cond do
      String.match?(message, ~r/^\/claude\s*/i) ->
        {:claude_code, String.replace(message, ~r/^\/claude\s*/i, "") |> String.trim()}

      String.match?(message, ~r/^\/gemini\s*/i) ->
        {:gemini, String.replace(message, ~r/^\/gemini\s*/i, "") |> String.trim()}

      String.match?(message, ~r/^\/openai\s*/i) ->
        {:openai, String.replace(message, ~r/^\/openai\s*/i, "") |> String.trim()}

      String.match?(message, ~r/^\/gpt\s*/i) ->
        {:openai, String.replace(message, ~r/^\/gpt\s*/i, "") |> String.trim()}

      String.match?(message, ~r/^\/codex\s*/i) ->
        {:codex, String.replace(message, ~r/^\/codex\s*/i, "") |> String.trim()}

      true ->
        nil
    end
  end

  @doc """
  Determines the best provider for a message using AI analysis.

  Uses a fast, cheap model (Gemini) to analyze the message and decide
  which provider is best suited for the task.

  ## Returns

    * `:claude_code` - For coding tasks, file operations, complex reasoning
    * `:gemini` - For simple questions, general knowledge
  """
  @spec determine_provider(String.t()) :: provider()
  def determine_provider(message) do
    # Use configured classifier (AI in prod, can be mocked in tests)
    classifier = get_config(:classifier, &default_classifier/1)

    case classifier.(message) do
      {:ok, :coding} ->
        :claude_code

      {:ok, :complex} ->
        :claude_code

      {:ok, :simple} ->
        :gemini

      {:ok, :general} ->
        :gemini

      {:error, _} ->
        # Fallback to Claude Code on classification failure
        Logger.warning("AI classification failed, defaulting to Claude Code")
        :claude_code
    end
  end

  @doc """
  Default classifier that uses AI to analyze messages.

  Can be overridden in config for testing.
  """
  @spec default_classifier(String.t()) :: {:ok, atom()} | {:error, term()}
  def default_classifier(message) do
    classify_message_with_ai(message)
  end

  @doc """
  Uses AI to classify a message and determine the best provider.

  This replaces hardcoded keyword matching with intelligent analysis.
  """
  @spec classify_message_with_ai(String.t()) :: {:ok, atom()} | {:error, term()}
  def classify_message_with_ai(message) do
    # Use Gemini for fast, cheap classification
    prompt = """
    Classify this user message into ONE category. Reply with ONLY the category name, nothing else.

    Categories:
    - CODING: Involves writing, debugging, refactoring, or reading code/files
    - COMPLEX: Requires multi-step reasoning, research, analysis, or lengthy response
    - SIMPLE: Quick factual question with a short answer
    - GENERAL: General conversation or unclear

    Message: #{String.slice(message, 0, 500)}

    Category:
    """

    # Use Gemini directly for classification (fast and cheap)
    case Gemini.prompt(nil, prompt, stream: false, max_tokens: 10) do
      {:ok, response, _session_id} ->
        category = response |> String.trim() |> String.upcase()

        result =
          case category do
            "CODING" -> :coding
            "COMPLEX" -> :complex
            "SIMPLE" -> :simple
            "GENERAL" -> :general
            _ -> :general
          end

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if a message appears to be a coding-related task.

  Uses configured classifier (AI in production, configurable for tests).
  """
  @spec coding_task?(String.t()) :: boolean()
  def coding_task?(message) do
    classifier = get_config(:classifier, &default_classifier/1)

    case classifier.(message) do
      {:ok, :coding} -> true
      {:ok, :complex} -> true
      _ -> false
    end
  end

  @doc """
  Checks if a message appears to be a simple question.

  Uses configured classifier (AI in production, configurable for tests).
  """
  @spec simple_question?(String.t()) :: boolean()
  def simple_question?(message) do
    classifier = get_config(:classifier, &default_classifier/1)

    case classifier.(message) do
      {:ok, :simple} -> true
      _ -> false
    end
  end

  @doc """
  Estimates the cost for a message using a specific provider.

  Uses provider-specific cost estimation.
  """
  @spec estimate_cost(provider(), String.t()) :: float()
  def estimate_cost(:claude_code, message) do
    # Claude Code is more expensive
    # Approximate: $0.003/1K input, $0.015/1K output
    input_tokens = String.length(message) / 4
    avg_output_tokens = 500

    input_cost = input_tokens / 1000 * 0.003
    output_cost = avg_output_tokens / 1000 * 0.015

    Float.round(input_cost + output_cost, 6)
  end

  def estimate_cost(:gemini, message) do
    Gemini.cost_estimate(message)
  end

  def estimate_cost(:openai, message) do
    OpenAI.cost_estimate(message)
  end

  def estimate_cost(:codex, message) do
    # OpenAI GPT-4 pricing: ~$0.03/1K input, $0.06/1K output
    input_tokens = String.length(message) / 4
    avg_output_tokens = 300

    input_cost = input_tokens / 1000 * 0.03
    output_cost = avg_output_tokens / 1000 * 0.06

    Float.round(input_cost + output_cost, 6)
  end

  # Private Functions

  defp call_provider(provider, session_id, message, caller, opts) do
    Logger.info("Routing to #{provider}: #{String.slice(message, 0, 50)}...")
    start_time = System.monotonic_time(:millisecond)

    # Retrieve relevant memories before sending to AI
    message_with_context = inject_memory_context(message, opts)

    case caller.(provider, session_id, message_with_context, opts) do
      {:ok, response, new_session_id} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time
        task_type = detect_task_type(message)

        # Log successful delegation for self-improvement
        log_delegation_success(provider, task_type, duration_ms, message)

        # Optionally store the exchange in memory (async to not block response)
        maybe_store_exchange(message, response, new_session_id, opts)

        {:ok, response, new_session_id, provider}

      {:error, reason} = error ->
        duration_ms = System.monotonic_time(:millisecond) - start_time
        task_type = detect_task_type(message)

        # Log failure for learning
        log_delegation_failure(provider, task_type, reason, duration_ms)

        Logger.error("Provider #{provider} failed: #{inspect(reason)}")
        error
    end
  end

  # Memory Integration Functions

  @doc false
  # Retrieve relevant memories and inject into the message context
  defp inject_memory_context(message, opts) do
    skip_memory = Keyword.get(opts, :skip_memory, false)

    if skip_memory or not Memory.enabled?() do
      message
    else
      case Memory.get_context(message, format: :text) do
        "" ->
          # No relevant memories found
          message

        memory_context ->
          # Truncate to avoid overwhelming the context
          max_memory_chars = Memory.max_context_chars()
          truncated_context = Truncation.truncate(memory_context, max_chars: max_memory_chars)

          # Prepend memory context to the message
          """
          [Relevant context from previous conversations]
          #{truncated_context}

          [Current message]
          #{message}
          """
      end
    end
  end

  @doc false
  # Store conversation exchange in memory (async, non-blocking)
  defp maybe_store_exchange(user_message, ai_response, session_id, opts) do
    skip_store = Keyword.get(opts, :skip_memory_store, false)

    if not skip_store and Memory.auto_store_enabled?() do
      # Run async to not block the response
      Task.start(fn ->
        case Memory.store_exchange(user_message, ai_response, session_id: session_id) do
          {:ok, :skipped} ->
            :ok

          {:ok, _memories} ->
            Logger.debug("Stored conversation exchange in memory")

          {:error, reason} ->
            Logger.warning("Failed to store conversation exchange: #{inspect(reason)}")
        end
      end)
    end
  end

  # Observation logging and metrics for self-improvement
  defp log_delegation_success(provider, task_type, duration_ms, message) do
    # Record to metrics (always)
    HAL.DelegationMetrics.record(provider, task_type, :success, duration_ms)

    # Only log detailed observations for interesting delegations
    if provider != :claude_code or duration_ms > 5000 do
      Task.start(fn ->
        HAL.Observations.log(%{
          type: "delegation_success",
          provider: to_string(provider),
          task_type: task_type,
          duration_ms: duration_ms,
          message_preview: String.slice(message, 0, 100),
          observation: "#{provider} handled #{task_type} task in #{duration_ms}ms"
        })
      end)
    end
  end

  defp log_delegation_failure(provider, task_type, reason, duration_ms) do
    # Record to metrics (always)
    HAL.DelegationMetrics.record(provider, task_type, :failure, duration_ms)

    # Log detailed observation for failures
    Task.start(fn ->
      HAL.Observations.log(%{
        type: "delegation_failure",
        provider: to_string(provider),
        task_type: task_type,
        duration_ms: duration_ms,
        error: inspect(reason),
        observation: "#{provider} failed on #{task_type} task after #{duration_ms}ms",
        impact: "Consider adjusting delegation rules for #{task_type} tasks"
      })
    end)
  end

  defp detect_task_type(message) do
    # Use cached AI classification result if available
    case classify_message_with_ai(message) do
      {:ok, :coding} -> "coding"
      {:ok, :complex} -> "complex"
      {:ok, :simple} -> "question"
      {:ok, :general} -> "general"
      {:error, _} -> "general"
    end
  end

  defp default_provider_caller(provider, session_id, message, opts) do
    case provider do
      :claude_code ->
        call_with_circuit_breaker(:claude_code, fn ->
          call_claude_provider(session_id, message, opts)
        end)

      :gemini ->
        call_with_circuit_breaker(:gemini, fn ->
          Gemini.prompt(session_id, message, opts)
        end)

      :openai ->
        call_with_circuit_breaker(:openai, fn ->
          OpenAI.prompt(session_id, message, opts)
        end)

      :codex ->
        # Codex uses Claude client
        Logger.info("Using Claude client for Codex request")

        call_with_circuit_breaker(:claude_code, fn ->
          call_claude_provider(session_id, message, opts)
        end)

      _ ->
        {:error, "Unknown provider: #{provider}"}
    end
  end

  # Wrap provider calls with circuit breaker for fault tolerance
  defp call_with_circuit_breaker(breaker_name, func) do
    breaker = ResilienceSupervisor.get_breaker_name(breaker_name)

    # Check if breaker exists before using it
    case Process.whereis(breaker) do
      nil ->
        # Breaker not started (e.g., in tests), call directly
        func.()

      _pid ->
        case CircuitBreaker.call(breaker, func) do
          {:ok, result} ->
            result

          {:error, :circuit_open} ->
            Logger.warning("Circuit breaker open for #{breaker_name}, failing fast")
            {:error, {:circuit_open, breaker_name}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # Helper to call the Claude provider (AgentSDK, PythonClient, or CLI)
  # Note: This function is called from within a circuit breaker, so we don't
  # wrap internal retries with additional circuit breakers.
  defp call_claude_provider(session_id, message, opts) do
    client = claude_client()

    # Generate unique session ID for web chat to avoid conflicts
    web_session_id =
      if session_id,
        do: "hal-web-#{session_id}",
        else: "hal-web-#{:erlang.unique_integer([:positive])}"

    # Build prompt with conversation history
    conversation_history = Keyword.get(opts, :conversation_history, [])
    full_prompt = build_prompt_with_history(message, conversation_history)

    # Build HAL system prompt (prime directives + identity + skills).
    # Preserve any upstream context (e.g., memory context) by appending it after
    # the core prompt so directives stay at the top.
    user_id = Keyword.get(opts, :user_id)

    session_type = Keyword.get(opts, :session_type, :main)

    base_prompt =
      SoulLoader.build_system_prompt(session_type,
        user_id: user_id,
        # Enable progressive skill disclosure based on the current message.
        message: message
      )

    system_prompt =
      case Keyword.get(opts, :system_prompt, "") do
        "" -> base_prompt
        extra -> base_prompt <> "\n\n" <> extra
      end

    sdk_opts =
      opts
      |> maybe_put_default_claude_model(client)
      |> Keyword.put(:system_prompt, system_prompt)

    # Different clients have different interfaces
    # The outer circuit breaker (claude_code) tracks overall health
    result =
      case client do
        HAL.AI.AgentSDK ->
          # AgentSDK supports session continuity
          HAL.AI.AgentSDK.prompt_with_session(session_id, full_prompt, sdk_opts)

        Hal.AI.ClaudePythonClient ->
          case Hal.AI.ClaudePythonClient.prompt(full_prompt, sdk_opts) do
            {:ok, response} -> {:ok, response, web_session_id}
            error -> error
          end

        Hal.AI.ClaudeCode ->
          ClaudeCode.prompt(web_session_id, full_prompt, sdk_opts)

        # Mock client or other
        _ ->
          case client.prompt(full_prompt, sdk_opts) do
            {:ok, response} -> {:ok, response, web_session_id}
            error -> error
          end
      end

    case result do
      {:ok, response, new_session_id} ->
        {:ok, extract_text(response), new_session_id || web_session_id}

      {:ok, response} ->
        {:ok, extract_text(response), web_session_id}

      {:error, reason} ->
        # Fall back to CLI if SDK client fails - but still report failure
        # to circuit breaker for tracking
        Logger.warning(
          "Claude client #{inspect(client)} failed: #{inspect(reason)}, falling back to CLI"
        )

        case ClaudeCode.prompt(web_session_id, message, opts) do
          {:ok, response, _new_session_id} ->
            {:ok, extract_text(response), web_session_id}

          error ->
            error
        end
    end
  end

  defp maybe_put_default_claude_model(opts, HAL.AI.AgentSDK) do
    model =
      Application.get_env(:hal, HAL.AI.AgentSDK, [])
      |> Keyword.get(:model)

    if is_binary(model) and model != "" do
      Keyword.put_new(opts, :model, model)
    else
      opts
    end
  end

  defp maybe_put_default_claude_model(opts, _client), do: opts

  # Build a prompt that includes conversation history for context
  defp build_prompt_with_history(message, []), do: message

  defp build_prompt_with_history(message, history) when is_list(history) do
    history_text =
      history
      |> Enum.map(fn
        %{role: "user", content: content} -> "User: #{content}"
        %{role: "assistant", content: content} -> "HAL: #{content}"
        %{role: role, content: content} -> "#{role}: #{content}"
      end)
      |> Enum.join("\n\n")

    """
    [Previous conversation for context]
    #{history_text}

    [Current message]
    User: #{message}
    """
  end

  defp extract_text(%{result: result}) when is_binary(result), do: result
  defp extract_text(response) when is_binary(response), do: response
  defp extract_text(response), do: inspect(response)

  defp get_config(key, default) do
    case Application.get_env(:hal, __MODULE__, []) do
      config when is_list(config) -> Keyword.get(config, key, default)
      _ -> default
    end
  end
end
