defmodule Hal.AI.Provider do
  @moduledoc """
  Behaviour defining the interface for AI providers.

  All AI providers (Claude Code, Gemini, Codex) must implement this behaviour
  to be used by the Router for intelligent routing.

  ## Implementing a Provider

      defmodule MyProvider do
        @behaviour Hal.AI.Provider

        @impl true
        def name, do: :my_provider

        @impl true
        def prompt(session_id, message, opts) do
          # Implementation here
          {:ok, response, new_session_id}
        end

        @impl true
        def supports?(message) do
          # Return true if this provider can handle the message
          true
        end

        @impl true
        def cost_estimate(message) do
          # Estimate cost in USD
          0.01
        end
      end

  ## Response Format

  The `prompt/3` callback should return one of:
  - `{:ok, response, session_id}` - Success with response data and optional session ID
  - `{:error, reason}` - Error with reason

  The response can be:
  - A string (the text response)
  - A map with at least a `:result` key containing the text response
  """

  @type session_id :: String.t() | nil
  @type message :: String.t()
  @type response :: String.t() | map()
  @type provider_name :: :claude_code | :gemini | :codex | atom()

  @doc """
  Returns the provider's name as an atom.

  This is used by the Router for logging and provider selection.

  ## Examples

      iex> MyProvider.name()
      :my_provider
  """
  @callback name() :: provider_name()

  @doc """
  Sends a prompt to the AI provider and returns the response.

  ## Arguments

    * `session_id` - Optional session ID for conversation continuity.
      Pass `nil` for new conversations.
    * `message` - The prompt message to send
    * `opts` - Provider-specific options (timeout, tools, etc.)

  ## Returns

    * `{:ok, response, session_id}` - Success with response and session ID
    * `{:error, reason}` - Error with reason string or map

  ## Examples

      {:ok, response, session_id} = Provider.prompt(nil, "Hello!")
      {:ok, response, session_id} = Provider.prompt(session_id, "Follow up")
  """
  @callback prompt(session_id(), message(), keyword()) ::
              {:ok, response(), session_id()} | {:error, term()}

  @doc """
  Checks if this provider supports handling the given message.

  This is used by the Router to determine which provider to use.
  Providers can inspect the message content to determine suitability.

  ## Arguments

    * `message` - The message to check

  ## Returns

    * `true` if the provider can handle this message type
    * `false` otherwise

  ## Examples

      iex> CodingProvider.supports?("write a function that...")
      true

      iex> CodingProvider.supports?("what's the weather?")
      false
  """
  @callback supports?(message()) :: boolean()

  @doc """
  Estimates the cost in USD for processing a message.

  This is used by the Router for cost-aware routing decisions.
  The estimate should be conservative (slightly higher than actual).

  ## Arguments

    * `message` - The message to estimate cost for

  ## Returns

  A float representing the estimated cost in USD.

  ## Examples

      iex> ExpensiveProvider.cost_estimate("short message")
      0.05

      iex> CheapProvider.cost_estimate("short message")
      0.001
  """
  @callback cost_estimate(message()) :: float()

  # Helper functions for providers

  @doc """
  Extracts the text content from a provider response.

  Handles different response formats:
  - Map with `:result` key - extracts the result value
  - String - returns as-is
  - Other - returns inspected string

  ## Examples

      iex> Provider.extract_text(%{result: "Hello"})
      "Hello"

      iex> Provider.extract_text("Hello")
      "Hello"
  """
  @spec extract_text(response()) :: String.t()
  def extract_text(%{result: result}) when is_binary(result), do: result
  def extract_text(response) when is_binary(response), do: response
  def extract_text(response), do: inspect(response)

  @doc """
  Parses a cost value to a float.

  Handles strings, integers, floats, and nil values.

  ## Examples

      iex> Provider.parse_cost("0.05")
      0.05

      iex> Provider.parse_cost(0.05)
      0.05

      iex> Provider.parse_cost(nil)
      0.0
  """
  @spec parse_cost(term()) :: float()
  def parse_cost(nil), do: 0.0
  def parse_cost(cost) when is_float(cost), do: cost
  def parse_cost(cost) when is_integer(cost), do: cost * 1.0

  def parse_cost(cost) when is_binary(cost) do
    case Float.parse(cost) do
      {value, _} -> value
      :error -> 0.0
    end
  end

  def parse_cost(_), do: 0.0
end
