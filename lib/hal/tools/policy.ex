defmodule Hal.Tools.Policy do
  @moduledoc """
  Central tool permission policy (OpenClaw-style).

  This module is the single source of truth for whether a HAL tool can be used
  given the current request context.

  Design goals:
  - Deterministic, audited rules (HAL executes; the brain decides *within* constraints)
  - Deny-by-default for non-owner users
  - Consistent enforcement at the tool boundary (`Hal.Tools.Executor`)
  """

  alias Hal.Accounts.User
  alias Hal.Repo
  alias HAL.Skills.Registry, as: SkillsRegistry

  @type decision :: :allow | {:deny, map()}

  @approval_required_tools [
    # Codops-impacting (human approval required)
    "hal_delegate_to_codex",
    "hal_delegate_to_jules",
    "hal_codops_create_change_request",
    "hal_codops_apply_change_request",
    # External process/tooling boundary
    "hal_mcp_start_named_connection",
    "hal_mcp_call_tool"
  ]

  @doc """
  Returns true if this tool requires explicit human approval.

  Some tools are always approval-gated; others (like `hal_skill_run`) can be
  approval-gated based on skill metadata.
  """
  @spec approval_required?(String.t()) :: boolean()
  def approval_required?(tool_name) when is_binary(tool_name),
    do: approval_required?(tool_name, %{})

  @spec approval_required?(String.t(), map()) :: boolean()
  def approval_required?(tool_name, args) when is_binary(tool_name) and is_map(args) do
    tool = normalize_tool_name(tool_name)

    cond do
      tool in @approval_required_tools ->
        true

      tool == "hal_skill_run" ->
        skill_requires_approval?(args)

      true ->
        false
    end
  end

  defp skill_requires_approval?(args) when is_map(args) do
    skill_id = Map.get(args, "skill") || Map.get(args, :skill)

    if is_binary(skill_id) and String.trim(skill_id) != "" do
      case SkillsRegistry.get_skill(String.trim(skill_id)) do
        nil ->
          false

        skill ->
          runner =
            case Map.get(skill, :runner) do
              value when is_binary(value) -> value |> String.trim() |> String.downcase()
              _ -> nil
            end

          Map.get(skill, :requires_approval) == true or
            runner in ["cli", "shell", "bash", "command"]
      end
    else
      false
    end
  end

  @doc """
  Authorize a tool call for the given context.

  Returns:
  - `:allow`
  - `{:deny, error_map}` (same format as `Hal.Tools.Executor.return_error/2`)
  """
  @spec authorize(String.t(), map(), keyword()) :: decision()
  def authorize(tool_name, _args, opts) when is_binary(tool_name) and is_list(opts) do
    tool = normalize_tool_name(tool_name)
    user_id = Keyword.get(opts, :user_id)

    cond do
      is_nil(user_id) ->
        {:deny,
         %{success: false, error: "Missing required context: user_id", type: :policy_error}}

      true ->
        case Repo.get(User, user_id) do
          nil ->
            deny(tool, "Unknown user", :unknown_user)

          %User{} = user ->
            evaluate_for_user(tool, user)
        end
    end
  end

  defp evaluate_for_user(tool, %User{} = user) do
    cond do
      user.role == "owner" ->
        :allow

      user.paired_at == nil ->
        deny(tool, "User is not paired/trusted", :not_paired)

      String.starts_with?(tool, "hal_memory_") ->
        :allow

      true ->
        deny(tool, "Tool is restricted to the owner", :owner_only)
    end
  end

  defp deny(tool, message, reason) do
    {:deny,
     %{
       success: false,
       error: "Tool not allowed",
       type: :policy_denied,
       tool: tool,
       reason: reason,
       message: message
     }}
  end

  defp normalize_tool_name(tool_name) do
    tool_name
    |> String.trim()
    |> String.replace_prefix("mcp__hal__", "")
  end
end
