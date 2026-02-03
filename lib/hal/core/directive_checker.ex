defmodule HAL.Core.DirectiveChecker do
  @moduledoc """
  Utility functions for prime directive validation.

  **Note:** As of the Replicant architecture update, `Hal.Tools.Executor.execute/3`
  now automatically checks prime directives before execution. You no longer need
  to call `execute_with_check/3` - just use the Executor directly.

  This module remains useful for:
  - `would_allow?/3` - Check if an action would be allowed without executing
  - `check_action/3` - Get detailed info about which directive would block
  - `with_check/3` - Wrap arbitrary (non-tool) operations with directive checking

  ## Usage

      # Check if an action would be allowed
      if DirectiveChecker.would_allow?("hal_email_send", args, opts) do
        # proceed
      end

      # Get detailed violation info
      case DirectiveChecker.check_action("hal_email_send", args, opts) do
        :ok -> proceed()
        {:violation, :no_exfiltration, reason} -> handle_blocked(reason)
      end

      # Wrap arbitrary operations
      DirectiveChecker.with_check(:external_action, context, fn ->
        # some operation
      end)
  """

  alias HAL.Core.PrimeDirectives
  alias Hal.Tools.Executor

  @type tool_name :: String.t()
  @type tool_args :: map()
  @type context :: keyword()
  @type result :: {:ok, map()} | {:error, map()}

  @doc """
  Execute a tool with prime directive checking.

  **Deprecated:** `Hal.Tools.Executor.execute/3` now automatically checks
  prime directives. This function simply delegates to the Executor.
  """
  @deprecated "Use Hal.Tools.Executor.execute/3 directly - it now checks directives automatically"
  @spec execute_with_check(tool_name(), tool_args(), context()) :: result()
  def execute_with_check(tool_name, args, opts \\ []) do
    # Executor now does directive checking automatically
    Executor.execute(tool_name, args, opts)
  end

  @doc """
  Check if an action would be allowed without executing it.

  Useful for preview/dry-run scenarios.
  """
  @spec would_allow?(tool_name(), tool_args(), context()) :: boolean()
  def would_allow?(tool_name, args, opts \\ []) do
    check_context = %{
      tool: tool_name,
      args: args,
      user_id: Keyword.get(opts, :user_id)
    }

    case PrimeDirectives.check_all(:tool_use, check_context) do
      :ok -> true
      {:violation, _reason} -> false
    end
  end

  @doc """
  Get detailed check result for an action.

  Returns the specific directive that would block the action, if any.
  """
  @spec check_action(tool_name(), tool_args(), context()) ::
          :ok | {:violation, atom(), String.t()}
  def check_action(tool_name, args, opts \\ []) do
    check_context = %{
      tool: tool_name,
      args: args,
      user_id: Keyword.get(opts, :user_id)
    }

    # Check each directive individually to identify which one fails
    PrimeDirectives.keys()
    |> Enum.reduce_while(:ok, fn directive, _acc ->
      case PrimeDirectives.check(directive, check_context) do
        :ok -> {:cont, :ok}
        {:violation, reason} -> {:halt, {:violation, directive, reason}}
      end
    end)
  end

  @doc """
  Wrap a function with directive checking.

  Useful for wrapping arbitrary operations that aren't tool calls.
  """
  @spec with_check(atom(), map(), (-> any())) :: {:ok, any()} | {:error, map()}
  def with_check(action_type, context, fun) do
    case PrimeDirectives.check_all(action_type, context) do
      :ok ->
        result = fun.()
        {:ok, result}

      {:violation, reason} ->
        {:error, directive_violation_response(reason)}
    end
  end

  # Private functions

  defp directive_violation_response(reason) do
    %{
      success: false,
      error: "Action blocked by prime directive",
      reason: reason,
      type: :directive_violation,
      help:
        "This action violates HAL's core safety principles. " <>
          "If you believe this is an error, please confirm the action explicitly."
    }
  end
end
