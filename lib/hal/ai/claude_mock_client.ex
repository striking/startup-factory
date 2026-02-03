defmodule Hal.AI.ClaudeMockClient do
  @moduledoc """
  Mock Claude client for testing.

  Returns canned responses without making real API calls.
  Useful for unit tests and development without consuming API quota.

  ## Configuration

  In `config/test.exs`:

      config :hal, :claude_client, Hal.AI.ClaudeMockClient

  ## Usage

  The mock client returns sensible default responses. You can also
  configure specific responses for testing:

      # In your test
      Hal.AI.ClaudeMockClient.set_response("Custom response for this test")

      # Or set an error
      Hal.AI.ClaudeMockClient.set_error({:error, :timeout})

      # Reset to defaults
      Hal.AI.ClaudeMockClient.reset()
  """

  use GenServer
  require Logger

  @behaviour Hal.AI.ClaudeClientBehaviour

  @default_response """
  I'm HAL, your AI assistant. This is a mock response for testing.

  I received your message and would normally process it through the Claude API,
  but we're running in test mode to save API quota.

  If you need to test actual API integration, use `@tag :integration` on your test.
  """

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Hal.AI.ClaudeClientBehaviour
  def prompt(message, opts \\ []) do
    GenServer.call(__MODULE__, {:prompt, message, opts})
  end

  @impl Hal.AI.ClaudeClientBehaviour
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Set a custom response for the next prompt call.
  """
  def set_response(response) when is_binary(response) do
    GenServer.cast(__MODULE__, {:set_response, response})
  end

  @doc """
  Set an error to be returned for the next prompt call.
  """
  def set_error(error) do
    GenServer.cast(__MODULE__, {:set_error, error})
  end

  @doc """
  Reset to default mock behavior.
  """
  def reset do
    GenServer.cast(__MODULE__, :reset)
  end

  @doc """
  Get the history of prompts received (for test assertions).
  """
  def get_prompt_history do
    GenServer.call(__MODULE__, :get_prompt_history)
  end

  @doc """
  Clear prompt history.
  """
  def clear_history do
    GenServer.cast(__MODULE__, :clear_history)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting Claude Mock Client (test mode - no API calls)")

    {:ok,
     %{
       custom_response: nil,
       custom_error: nil,
       prompt_history: []
     }}
  end

  @impl true
  def handle_call({:prompt, message, opts}, _from, state) do
    # Record the prompt for test assertions
    history_entry = %{
      message: message,
      opts: opts,
      timestamp: DateTime.utc_now()
    }

    new_state = %{state | prompt_history: state.prompt_history ++ [history_entry]}

    # Simulate a small delay like a real API call
    Process.sleep(50)

    result =
      cond do
        state.custom_error != nil ->
          state.custom_error

        state.custom_response != nil ->
          {:ok, state.custom_response}

        true ->
          {:ok, generate_mock_response(message)}
      end

    # Clear custom response/error after use (one-shot)
    final_state = %{new_state | custom_response: nil, custom_error: nil}

    {:reply, result, final_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      "sdk_available" => true,
      "python_version" => "mock",
      "auth_method" => "mock_client",
      "mode" => "testing"
    }

    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call(:get_prompt_history, _from, state) do
    {:reply, state.prompt_history, state}
  end

  @impl true
  def handle_cast({:set_response, response}, state) do
    {:noreply, %{state | custom_response: response}}
  end

  @impl true
  def handle_cast({:set_error, error}, state) do
    {:noreply, %{state | custom_error: error}}
  end

  @impl true
  def handle_cast(:reset, state) do
    {:noreply, %{state | custom_response: nil, custom_error: nil}}
  end

  @impl true
  def handle_cast(:clear_history, state) do
    {:noreply, %{state | prompt_history: []}}
  end

  # Private helpers

  defp generate_mock_response(message) do
    message_lower = String.downcase(message)

    cond do
      String.contains?(message_lower, "hello") or String.contains?(message_lower, "hi") ->
        "Hello! I'm HAL, your AI assistant. How can I help you today? (Mock response)"

      String.contains?(message_lower, "test") ->
        "This is a test response from the mock Claude client. Everything is working correctly!"

      String.contains?(message_lower, "code") or String.contains?(message_lower, "function") ->
        """
        Here's a mock code response:

        ```elixir
        def example_function do
          :ok
        end
        ```

        (This is a mock response - no actual code analysis was performed)
        """

      true ->
        @default_response
    end
  end
end
