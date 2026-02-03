defmodule HAL.Autonomy.Brain do
  @moduledoc """
  Unified LLM entrypoint for autonomous operations.

  Uses `Hal.AI.Router` so we consistently benefit from:
  - Claude Agent SDK when available
  - HAL system prompt (prime directives + identity + skills)
  - HAL MCP tools (with approvals + directive checks)
  """

  alias Hal.Accounts.DefaultUser
  alias HAL.Turns.Runner

  @doc """
  Prompt the autonomy brain and return plain text.

  By default this:
  - Forces Claude (`enable_routing: false`, `default_provider: :claude_code`)
  - Ensures `:user_id` exists (falls back to DefaultUser)
  - Supplies basic channel context so tool calls can act safely
  """
  @spec prompt(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def prompt(message, opts \\ []) when is_binary(message) do
    user_id = Keyword.get(opts, :user_id) || default_user_id()

    if is_nil(user_id) do
      {:error, :no_user}
    else
      session_marker = Keyword.get(opts, :hal_session_id) || Keyword.get(opts, :session_id)

      opts =
        opts
        |> Keyword.put(:user_id, user_id)
        |> Keyword.put_new(:channel_type, "terminal")
        |> Keyword.put_new(:channel_id, "autonomy")
        |> maybe_put(:hal_session_id, session_marker)
        |> Keyword.put_new(:mode, :autonomous)

      case Runner.run(message, opts) do
        {:ok, %{text: response}} when is_binary(response) ->
          {:ok, response}

        {:ok, %{text: response}} ->
          {:ok, inspect(response)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp default_user_id do
    case DefaultUser.get() do
      %{} = user -> user.id
      nil -> nil
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
