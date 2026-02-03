defmodule HAL.Turns.Runner do
  @moduledoc """
  Canonical "turn runner" for HAL.

  A *turn* is any single model invocation with a fully defined HAL context:
  - interactive chat turns (web/telegram/slack/discord)
  - autonomous heartbeat turns
  - autonomous task-step turns
  - multi-agent subagent turns

  This module exists to ensure every turn shares the same:
  - identity + safety context (user/channel/session metadata)
  - routing mode (interactive vs autonomous)
  - structured logging in the event log
  """

  require Logger

  alias Hal.AI.Router
  alias Hal.Accounts.DefaultUser
  alias HAL.Costs.Budget
  alias HAL.Costs.Tracker
  alias HAL.EventLog

  @type mode :: :interactive | :autonomous

  @type run_result ::
          {:ok,
           %{
             text: String.t(),
             raw: term(),
             provider: atom(),
             provider_session_id: String.t() | nil
           }}
          | {:error, term()}

  @doc """
  Runs one HAL turn.

  ## Options (common)
  - `:user_id` (required; falls back to DefaultUser when available)
  - `:channel_type` (default `"terminal"`)
  - `:channel_id` (default `"interactive"`)
  - `:hal_session_id` (HAL session identity for tool context)
  - `:session_id` (provider session id; e.g. Claude session UUID)
  - `:conversation_history` (list of `%{role, content}` maps)

  ## Options (behavior)
  - `:mode` - `:interactive` (default) or `:autonomous`
    - autonomous turns force Claude and disable routing by default
  - `:log` - whether to log turn start/end (default `true` for autonomous)

  ## Testing
  - `:ai_client` - optional function `(provider_session_id, message, opts) -> {:ok, resp, new_session_id} | {:error, reason}`
    used by SessionServer tests to avoid external calls.
  """
  @spec run(String.t(), keyword()) :: run_result()
  def run(message, opts \\ []) when is_binary(message) do
    user_id = Keyword.get(opts, :user_id) || default_user_id()

    if is_nil(user_id) do
      {:error, :no_user}
    else
      mode = Keyword.get(opts, :mode, :interactive)
      log? = Keyword.get(opts, :log, mode != :interactive)

      channel_type = Keyword.get(opts, :channel_type, "terminal")
      channel_id = Keyword.get(opts, :channel_id, "interactive")

      session_type =
        Keyword.get(opts, :session_type) || infer_session_type(channel_type, channel_id)

      turn_id = Keyword.get(opts, :turn_id) || Ecto.UUID.generate()
      started_at_ms = System.monotonic_time(:millisecond)

      router_opts =
        opts
        |> Keyword.put(:user_id, user_id)
        |> Keyword.put(:channel_type, channel_type)
        |> Keyword.put(:channel_id, channel_id)
        |> Keyword.put(:session_type, session_type)
        |> Keyword.put_new(:hal_session_id, Keyword.get(opts, :hal_session_id))
        |> apply_mode_defaults(mode)

      with :ok <- enforce_budget(mode, user_id, opts) do
        if log? do
          EventLog.log(:decision_made, %{
            decision: "turn_started",
            turn_id: turn_id,
            mode: to_string(mode),
            channel_type: channel_type,
            channel_id: channel_id,
            user_id: user_id,
            message_preview: preview(message)
          })
        end

        result =
          case Keyword.get(opts, :ai_client) do
            fun when is_function(fun, 3) ->
              fun.(Keyword.get(router_opts, :session_id), message, router_opts)
              |> normalize_ai_client_result()

            _ ->
              Router.route(message, router_opts)
              |> normalize_router_result()
          end

        duration_ms = System.monotonic_time(:millisecond) - started_at_ms

        case result do
          {:ok,
           %{text: text, raw: raw, provider: provider, provider_session_id: provider_session_id}} ->
            maybe_track_costs(
              mode,
              user_id,
              provider,
              message,
              text,
              router_opts,
              duration_ms,
              opts
            )

            if log? do
              EventLog.log(:action_taken, %{
                action: "turn_completed",
                turn_id: turn_id,
                mode: to_string(mode),
                provider: to_string(provider),
                duration_ms: duration_ms,
                user_id: user_id,
                channel_type: channel_type,
                channel_id: channel_id,
                response_preview: preview(text)
              })
            end

            {:ok,
             %{text: text, raw: raw, provider: provider, provider_session_id: provider_session_id}}

          {:error, reason} = error ->
            if log? do
              EventLog.log(:action_failed, %{
                action: "turn_failed",
                turn_id: turn_id,
                mode: to_string(mode),
                duration_ms: duration_ms,
                user_id: user_id,
                channel_type: channel_type,
                channel_id: channel_id,
                error: inspect(reason)
              })
            end

            error
        end
      end
    end
  end

  defp default_user_id do
    case DefaultUser.get() do
      %{} = user -> user.id
      nil -> nil
    end
  end

  defp apply_mode_defaults(opts, :autonomous) do
    opts
    |> Keyword.put_new(:enable_routing, false)
    |> Keyword.put_new(:default_provider, :claude_code)
  end

  defp apply_mode_defaults(opts, _), do: opts

  defp infer_session_type(channel_type, channel_id) when is_binary(channel_type) do
    cond do
      channel_type in ["terminal", "web"] ->
        :main

      channel_type in ["slack", "discord"] ->
        :shared

      channel_type == "telegram" and telegram_group_id?(channel_id) ->
        :shared

      true ->
        :main
    end
  end

  defp infer_session_type(_channel_type, _channel_id), do: :main

  defp telegram_group_id?(channel_id) when is_integer(channel_id), do: channel_id < 0

  defp telegram_group_id?(channel_id) when is_binary(channel_id) do
    case Integer.parse(channel_id) do
      {id, ""} -> id < 0
      _ -> false
    end
  end

  defp telegram_group_id?(_), do: false

  defp normalize_ai_client_result({:ok, response, new_session_id}) do
    {:ok,
     %{
       text: extract_text(response),
       raw: response,
       provider: :mock,
       provider_session_id: new_session_id
     }}
  end

  defp normalize_ai_client_result({:error, reason}), do: {:error, reason}
  defp normalize_ai_client_result(other), do: {:error, {:unexpected_ai_client_response, other}}

  defp normalize_router_result({:ok, response, new_session_id, provider}) do
    {:ok,
     %{
       text: extract_text(response),
       raw: response,
       provider: provider,
       provider_session_id: new_session_id
     }}
  end

  defp normalize_router_result({:error, reason}), do: {:error, reason}
  defp normalize_router_result(other), do: {:error, {:unexpected_router_response, other}}

  defp extract_text(%{result: result}) when is_binary(result), do: result
  defp extract_text(%{"result" => result}) when is_binary(result), do: result
  defp extract_text(text) when is_binary(text), do: text
  defp extract_text(other), do: inspect(other)

  defp preview(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 240)
  end

  defp preview(_), do: ""

  defp enforce_budget(:autonomous, user_id, opts) do
    enforce? =
      Keyword.get(opts, :enforce_budget, budget_enforced_by_default?())

    if enforce? and not Budget.within_budget?(user_id) do
      remaining = Budget.get_remaining(user_id)
      {:error, {:budget_exceeded, remaining}}
    else
      :ok
    end
  end

  defp enforce_budget(_mode, _user_id, _opts), do: :ok

  defp budget_enforced_by_default? do
    Application.get_env(:hal, Budget, [])
    |> Keyword.get(:enforce_autonomy, true)
  end

  defp maybe_track_costs(
         mode,
         user_id,
         provider,
         message,
         response_text,
         router_opts,
         duration_ms,
         opts
       ) do
    track? =
      Keyword.get(opts, :track_costs, mode == :autonomous)

    provider = provider_to_cost_provider(provider)

    if track? and provider != nil do
      usage = %{
        model: model_for_provider(provider, router_opts),
        input_tokens: estimate_tokens(build_effective_prompt(message, router_opts)),
        output_tokens: estimate_tokens(response_text),
        task_type: to_string(mode),
        metadata: %{
          provider: provider,
          duration_ms: duration_ms,
          channel_type: Keyword.get(router_opts, :channel_type),
          channel_id: Keyword.get(router_opts, :channel_id)
        }
      }

      tracker_opts =
        []
        |> Keyword.put(:user_id, user_id)
        |> maybe_put_session_id(router_opts)

      case Tracker.track_message(provider, usage, tracker_opts) do
        {:ok, _record} -> :ok
        {:error, reason} -> Logger.debug("Cost tracking failed: #{inspect(reason)}")
      end
    end

    :ok
  end

  defp provider_to_cost_provider(:claude_code), do: "claude"
  defp provider_to_cost_provider(:gemini), do: "gemini"
  defp provider_to_cost_provider(:openai), do: "openai"
  defp provider_to_cost_provider(:codex), do: "codex"
  defp provider_to_cost_provider(:mock), do: nil
  defp provider_to_cost_provider(_), do: nil

  defp model_for_provider("claude", router_opts) do
    Keyword.get(router_opts, :model) ||
      Application.get_env(:hal, HAL.AI.AgentSDK, []) |> Keyword.get(:model) ||
      "default"
  end

  defp model_for_provider("gemini", router_opts) do
    Keyword.get(router_opts, :model) ||
      Application.get_env(:hal, Hal.AI.Gemini, []) |> Keyword.get(:model) ||
      "default"
  end

  defp model_for_provider("openai", router_opts) do
    Keyword.get(router_opts, :model) ||
      Application.get_env(:hal, Hal.AI.OpenAI, []) |> Keyword.get(:model) ||
      "default"
  end

  defp model_for_provider("codex", router_opts) do
    Keyword.get(router_opts, :model) ||
      Application.get_env(:hal, Hal.AI.Codex, []) |> Keyword.get(:model) ||
      "default"
  end

  defp model_for_provider(_, _), do: "default"

  defp build_effective_prompt(message, router_opts) do
    history = Keyword.get(router_opts, :conversation_history, [])

    if is_list(history) and history != [] do
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
    else
      message
    end
  end

  defp estimate_tokens(text) when is_binary(text), do: ceil(String.length(text) / 4)
  defp estimate_tokens(_), do: 0

  defp maybe_put_session_id(opts, router_opts) do
    case Keyword.get(router_opts, :hal_session_id) do
      id when is_binary(id) ->
        if uuid?(id), do: Keyword.put(opts, :session_id, id), else: opts

      _ ->
        opts
    end
  end

  defp uuid?(string) when is_binary(string) do
    Regex.match?(~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i, string)
  end

  defp uuid?(_), do: false
end
