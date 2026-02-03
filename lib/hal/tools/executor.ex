defmodule Hal.Tools.Executor do
  @moduledoc """
  Executes HAL tool calls from Claude Code.

  Processes tool invocations, validates arguments, routes to appropriate
  handlers, and returns results in the format expected by Claude Code.

  ## Tool Execution Flow

  1. Claude Code invokes a tool with arguments
  2. **Prime Directives are checked** (blocks harmful actions)
  3. Executor validates tool name and arguments
  4. Executor routes to appropriate handler module
  5. Handler executes the operation
  6. Result is returned in standardized format

  ## Return Format

  Success:
  ```
  {:ok, %{
    success: true,
    result: <tool-specific-data>,
    message: "Human-readable description"
  }}
  ```

  Error:
  ```
  {:error, %{
    success: false,
    error: "Error description",
    details: <optional-error-details>
  }}
  ```

  ## Usage

      # Execute a tool call (with automatic directive checking)
      {:ok, result} = Executor.execute("hal_memory_search", %{
        "query" => "What are my preferences?",
        "limit" => 5
      }, user_id: "user-uuid")

      # With context
      {:ok, result} = Executor.execute("hal_calendar_get_events", %{},
        user_id: "user-uuid",
        session_id: "session-uuid"
      )
  """

  require Logger

  alias HAL.Core.PrimeDirectives
  alias HAL.Autonomy.Approvals, as: HumanApprovals
  alias HAL.EventLog

  alias Hal.Tools.Handlers.{
    Memory,
    Calendar,
    Email,
    Tasks,
    Notifications,
    Delegation,
    Skills,
    Browser,
    Self,
    Codops,
    MCP
  }

  alias Hal.Tools.Policy

  @type tool_name :: String.t()
  @type tool_args :: map()
  @type context :: keyword()
  @type result :: {:ok, map()} | {:error, map()}

  @doc """
  Executes a tool call with the given arguments and context.

  ## Arguments

    * `tool_name` - The name of the tool to execute
    * `args` - Map of arguments for the tool
    * `opts` - Context options:
      * `:user_id` - UUID of the user (required for most tools)
      * `:session_id` - UUID of the current session (optional)
      * `:channel_type` - The channel type (e.g., "telegram")
      * `:channel_id` - The channel ID

  ## Returns

    * `{:ok, result_map}` - Successful execution
    * `{:error, error_map}` - Execution failed
  """
  @spec execute(tool_name(), tool_args(), context()) :: result()
  def execute(tool_name, args, opts \\ []) do
    Logger.debug("Executing tool: #{tool_name} with args: #{inspect(args)}")

    # Validate that we have required context
    user_id = Keyword.get(opts, :user_id)

    if is_nil(user_id) do
      return_error("Missing required context: user_id")
    else
      case Policy.authorize(tool_name, args, opts) do
        :allow ->
          execute_with_directives(tool_name, args, opts)

        {:deny, error_map} when is_map(error_map) ->
          {:error, error_map}
      end
    end
  end

  defp execute_with_directives(tool_name, args, opts) do
    user_id = Keyword.fetch!(opts, :user_id)

    # Check prime directives before execution
    check_context = %{
      tool: tool_name,
      args: args,
      user_id: user_id,
      session_id: Keyword.get(opts, :session_id),
      channel_type: Keyword.get(opts, :channel_type)
    }

    case PrimeDirectives.check_all(:tool_use, check_context) do
      :ok ->
        case maybe_require_human_approval(tool_name, args, opts) do
          :ok ->
            result = execute_internal(tool_name, args, opts)
            log_tool_execution(tool_name, args, result, opts)
            result

          {:approved, approval_token} ->
            result = execute_internal(tool_name, args, opts)
            log_tool_execution(tool_name, args, result, opts)

            case result do
              {:ok, response} when is_map(response) ->
                HumanApprovals.mark_execution_completed(approval_token, response)

              {:error, error} when is_map(error) ->
                HumanApprovals.mark_execution_failed(approval_token, error)

              _ ->
                :ok
            end

            result

          {:already_executing, approval} ->
            status = Map.get(approval, :execution_status) || "running"

            return_success(
              "Already queued/executing (approval: #{approval.token})",
              %{approval_token: approval.token, tool: tool_name, execution_status: status}
            )

          {:needs_approval, approval} ->
            {:error,
             %{
               success: false,
               error: "Approval required",
               type: :needs_approval,
               approval_token: approval.token,
               approval_id: approval.id,
               status: approval.status,
               tool: tool_name,
               help:
                 "Approve this action in the HAL UI at /approvals. Once approved, it will execute automatically (or retry with approval_token)."
             }}

          {:error, error_map} ->
            {:error, error_map}
        end

      {:violation, reason} ->
        Logger.warning("Directive violation blocked #{tool_name}: #{reason}")
        log_directive_violation(tool_name, args, reason, opts)

        {:error,
         %{
           success: false,
           error: "Action blocked by prime directive",
           reason: reason,
           type: :directive_violation,
           help: "This action violates HAL's core safety principles."
         }}
    end
  end

  # Internal execution after directive check passes
  defp execute_internal(tool_name, args, opts) do
    case tool_name do
      # Memory tools
      "hal_memory_search" ->
        Memory.search(args, opts)

      "hal_memory_store" ->
        Memory.store(args, opts)

      "hal_memory_forget" ->
        Memory.forget(args, opts)

      # Calendar tools
      "hal_calendar_get_events" ->
        Calendar.get_events(args, opts)

      "hal_calendar_create_event" ->
        Calendar.create_event(args, opts)

      # Email tools
      "hal_email_get_unread" ->
        Email.get_unread(args, opts)

      "hal_email_send" ->
        Email.send_email(args, opts)

      # Task tools
      "hal_tasks_list" ->
        Tasks.list(args, opts)

      "hal_tasks_create" ->
        Tasks.create(args, opts)

      "hal_tasks_complete" ->
        Tasks.complete(args, opts)

      # Notification tools
      "hal_send_notification" ->
        Notifications.send(args, opts)

      # Delegation tools (multi-agent orchestration)
      "hal_delegate_to_codex" ->
        Delegation.delegate_to_codex(args, opts)

      "hal_delegate_to_jules" ->
        Delegation.delegate_to_jules(args, opts)

      "hal_delegate_to_gemini" ->
        Delegation.delegate_to_gemini(args, opts)

      "hal_check_delegation_status" ->
        Delegation.check_status(args, opts)

      # Skills-first execution
      "hal_skill_run" ->
        Skills.run(args, opts)

      # Browser tools
      "hal_browser_navigate" ->
        Browser.navigate(args, opts)

      "hal_browser_snapshot" ->
        Browser.snapshot(args, opts)

      "hal_browser_click" ->
        Browser.click(args, opts)

      "hal_browser_fill" ->
        Browser.fill(args, opts)

      "hal_browser_screenshot" ->
        Browser.screenshot(args, opts)

      "hal_browser_evaluate" ->
        Browser.evaluate(args, opts)

      "hal_browser_console" ->
        Browser.console(args, opts)

      "hal_browser_network" ->
        Browser.network(args, opts)

      # Self-modification tools
      "hal_self_update_personality" ->
        Self.update_personality(args, opts)

      "hal_self_update_preference" ->
        Self.update_preference(args, opts)

      "hal_self_set_goal" ->
        Self.set_goal(args, opts)

      "hal_self_update_goal" ->
        Self.update_goal(args, opts)

      "hal_self_reflect" ->
        Self.reflect(args, opts)

      "hal_get_self_status" ->
        Self.get_status(args, opts)

      # Codops (safe self-improvement)
      "hal_codops_create_change_request" ->
        Codops.create_change_request(args, opts)

      "hal_codops_apply_change_request" ->
        Codops.apply_change_request(args, opts)

      # MCP tools (external tool ecosystem)
      "hal_mcp_start_named_connection" ->
        MCP.start_named_connection(args, opts)

      "hal_mcp_list_connections" ->
        MCP.list_connections(args, opts)

      "hal_mcp_list_tools" ->
        MCP.list_tools(args, opts)

      "hal_mcp_call_tool" ->
        MCP.call_tool(args, opts)

      # Unknown tool
      unknown ->
        return_error("Unknown tool: #{unknown}")
    end
  end

  # Log directive violations for self-improvement
  defp log_directive_violation(tool_name, args, reason, opts) do
    if Code.ensure_loaded?(HAL.Observations) do
      HAL.Observations.log(%{
        type: "directive_violation",
        observation: "Blocked #{tool_name}: #{reason}",
        tool: tool_name,
        args_summary: summarize_args(args),
        user_id: Keyword.get(opts, :user_id),
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      })
    end
  end

  defp summarize_args(args) when is_map(args) do
    args
    |> Enum.map(fn {k, v} ->
      {k, if(is_binary(v) and byte_size(v) > 50, do: "[#{byte_size(v)} chars]", else: v)}
    end)
    |> Enum.into(%{})
    |> inspect(limit: 200)
  end

  defp summarize_args(_), do: "non-map"

  defp log_tool_execution(tool_name, args, result, opts) do
    # Avoid double-logging: approvals are logged in HAL.Autonomy.Approvals.
    case result do
      {:error, %{type: :needs_approval}} ->
        :ok

      {:ok, response} when is_map(response) ->
        EventLog.log(:action_taken, %{
          action: "tool_execution",
          tool: tool_name,
          args_summary: summarize_args(args),
          user_id: Keyword.get(opts, :user_id),
          session_id: Keyword.get(opts, :session_id),
          result_message: Map.get(response, :message)
        })

      {:error, error} when is_map(error) ->
        EventLog.log(:action_failed, %{
          action: "tool_execution",
          tool: tool_name,
          args_summary: summarize_args(args),
          user_id: Keyword.get(opts, :user_id),
          session_id: Keyword.get(opts, :session_id),
          error: Map.get(error, :error) || inspect(error)
        })

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp maybe_require_human_approval(tool_name, args, opts) do
    if Policy.approval_required?(tool_name, args) do
      approval_token = Map.get(args, "approval_token") || Map.get(args, :approval_token)
      approval_wait? = Keyword.get(opts, :approval_wait, false)
      approval_wait_timeout_ms = Keyword.get(opts, :approval_wait_timeout_ms, 110_000)
      approval_already_claimed? = Keyword.get(opts, :approval_already_claimed, false)

      if is_binary(approval_token) and approval_token != "" do
        case HumanApprovals.validate_tool_token(approval_token, tool_name) do
          :approved ->
            maybe_claim_execution(approval_token, approval_already_claimed?)

          {:needs_approval, approval} ->
            if approval_wait? do
              case HumanApprovals.wait_for_resolution(approval.token, approval_wait_timeout_ms) do
                :approved ->
                  maybe_claim_execution(approval.token, approval_already_claimed?)

                {:denied, denied} ->
                  {:error,
                   %{
                     success: false,
                     error: "Approval denied",
                     type: :approval_denied,
                     approval_token: denied.token,
                     approval_id: denied.id,
                     tool: tool_name,
                     deny_reason: denied.deny_reason
                   }}

                :timeout ->
                  {:needs_approval, approval}

                :not_found ->
                  {:needs_approval, approval}
              end
            else
              {:needs_approval, approval}
            end

          {:denied, approval} ->
            {:error,
             %{
               success: false,
               error: "Approval denied",
               type: :approval_denied,
               approval_token: approval.token,
               approval_id: approval.id,
               tool: tool_name,
               deny_reason: approval.deny_reason
             }}

          :not_found ->
            {:error,
             %{
               success: false,
               error: "Invalid approval token",
               type: :invalid_approval_token,
               approval_token: approval_token,
               tool: tool_name
             }}

          {:mismatch, approval} ->
            {:error,
             %{
               success: false,
               error: "Approval token does not match requested tool",
               type: :approval_token_mismatch,
               approval_token: approval.token,
               approval_id: approval.id,
               tool: tool_name,
               approved_tool: approval.tool_name
             }}
        end
      else
        user_id = Keyword.fetch!(opts, :user_id)

        context = %{
          session_id: Keyword.get(opts, :session_id),
          channel_type: Keyword.get(opts, :channel_type),
          channel_id: Keyword.get(opts, :channel_id)
        }

        case HumanApprovals.request(user_id, tool_name, args, context) do
          {:ok, approval} ->
            if approval_wait? do
              case HumanApprovals.wait_for_resolution(approval.token, approval_wait_timeout_ms) do
                :approved ->
                  maybe_claim_execution(approval.token, approval_already_claimed?)

                {:denied, denied} ->
                  {:error,
                   %{
                     success: false,
                     error: "Approval denied",
                     type: :approval_denied,
                     approval_token: denied.token,
                     approval_id: denied.id,
                     tool: tool_name,
                     deny_reason: denied.deny_reason
                   }}

                :timeout ->
                  {:needs_approval, approval}

                :not_found ->
                  {:needs_approval, approval}
              end
            else
              {:needs_approval, approval}
            end

          {:error, changeset} ->
            {:error,
             %{
               success: false,
               error: "Failed to create approval request",
               type: :approval_request_failed,
               details: %{errors: format_changeset_errors(changeset)}
             }}
        end
      end
    else
      :ok
    end
  end

  defp maybe_claim_execution(token, true), do: {:approved, token}

  defp maybe_claim_execution(token, false) do
    case HumanApprovals.claim_execution(token) do
      :claimed ->
        {:approved, token}

      :already_claimed ->
        case HumanApprovals.get(token) do
          %HAL.Autonomy.ApprovalRequest{} = approval -> {:already_executing, approval}
          _ -> {:approved, token}
        end

      :not_found ->
        {:approved, token}
    end
  end

  defp format_changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc """
  Returns a standardized success response.

  ## Examples

      iex> Executor.return_success("Memory stored", %{id: "123"})
      {:ok, %{success: true, message: "Memory stored", result: %{id: "123"}}}
  """
  @spec return_success(String.t(), any()) :: {:ok, map()}
  def return_success(message, result \\ nil) do
    response = %{
      success: true,
      message: message
    }

    response =
      if result do
        Map.put(response, :result, result)
      else
        response
      end

    {:ok, response}
  end

  @doc """
  Returns a standardized error response.

  ## Examples

      iex> Executor.return_error("Not found")
      {:error, %{success: false, error: "Not found"}}

      iex> Executor.return_error("Invalid args", %{field: "email"})
      {:error, %{success: false, error: "Invalid args", details: %{field: "email"}}}
  """
  @spec return_error(String.t(), any()) :: {:error, map()}
  def return_error(error, details \\ nil) do
    response = %{
      success: false,
      error: error
    }

    response =
      if details do
        Map.put(response, :details, details)
      else
        response
      end

    {:error, response}
  end
end
