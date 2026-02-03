defmodule Hal.AI.ClaudeClientBehaviour do
  @moduledoc """
  Behaviour for Claude API clients.

  This allows us to swap between the real Python-based client
  and a mock client for testing.
  """

  @type prompt_opts :: [
          allowed_tools: [String.t()],
          include_model_tools: boolean(),
          system_prompt: String.t(),
          timeout: pos_integer()
        ]

  @callback prompt(String.t(), prompt_opts()) :: {:ok, String.t()} | {:error, term()}
  @callback get_status() :: {:ok, map()} | {:error, term()}
end
