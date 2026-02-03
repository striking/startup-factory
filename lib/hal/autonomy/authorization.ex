defmodule HAL.Autonomy.Authorization do
  @moduledoc """
  Define what HAL can do autonomously vs needs user approval.

  Clear boundaries prevent HAL from taking unwanted actions while
  enabling productive autonomous work within safe limits.

  ## Action Categories

  1. **Autonomous** - HAL can do freely without asking
  2. **Needs Approval** - Must ask user before proceeding
  3. **Forbidden** - Never do, even if asked (security)

  ## Usage

      # Check if action can be done autonomously
      iex> Authorization.can_do_autonomously?(:read_files)
      true

      iex> Authorization.can_do_autonomously?(:send_email)
      false

      # Check if action requires approval
      iex> Authorization.requires_approval?(:post_to_social)
      true

      # Check if action is forbidden
      iex> Authorization.is_forbidden?(:delete_system_files)
      true

      # Get full categorization
      iex> Authorization.categorize_action(:send_email)
      {:needs_approval, "External action - requires confirmation"}
  """

  require Logger

  @workspace_dir Application.compile_env(:hal, :workspace_dir, "workspace")

  # Actions HAL can do freely during autonomous work
  @autonomous_actions [
    # File operations (within workspace)
    :read_files,
    :read_workspace_files,
    :organize_memory,
    :update_daily_log,
    :update_heartbeat_state,

    # Learning & reflection
    :analyze_events,
    :detect_patterns,
    :update_learned_facts,

    # Information gathering
    :search_web,
    :check_calendar,
    # Can see subjects, not open/read body
    :check_email_headers,
    :check_weather,
    :check_git_status,

    # Self-maintenance
    :update_own_documentation,
    :commit_own_workspace_changes,
    :clean_old_logs,

    # Internal operations
    :log_events,
    :update_state,
    :schedule_future_check
  ]

  # Actions that require user confirmation
  @needs_approval [
    # External communication
    :send_email,
    :reply_to_email,
    :post_to_social,
    :send_message,
    :make_api_call,

    # Code modifications
    :modify_user_code,
    :commit_to_user_repo,
    :push_to_remote,
    :create_pull_request,

    # Destructive operations
    :delete_files,
    :move_files,
    :run_destructive_commands,

    # System operations
    :install_package,
    :modify_config,
    :restart_service,

    # Financial/sensitive
    :make_purchase,
    :access_credentials,

    # Identity changes
    :update_soul_md,
    :update_agents_md
  ]

  # Actions that are never allowed
  @forbidden_actions [
    :delete_system_files,
    :exfiltrate_data,
    :access_other_users_data,
    :disable_security,
    :modify_auth_credentials,
    :send_credentials_externally,
    :bypass_approval_system
  ]

  @doc """
  Check if an action can be done autonomously (no approval needed).
  """
  @spec can_do_autonomously?(atom()) :: boolean()
  def can_do_autonomously?(action) when action in @autonomous_actions, do: true
  def can_do_autonomously?(_), do: false

  @doc """
  Check if an action requires user approval.
  """
  @spec requires_approval?(atom()) :: boolean()
  def requires_approval?(action) when action in @needs_approval, do: true
  def requires_approval?(_), do: false

  @doc """
  Check if an action is forbidden (security).
  """
  @spec is_forbidden?(atom()) :: boolean()
  def is_forbidden?(action) when action in @forbidden_actions, do: true
  def is_forbidden?(_), do: false

  @doc """
  Categorize an action and return reason.

  ## Returns
    - {:autonomous, reason} - Can do freely
    - {:needs_approval, reason} - Must ask first
    - {:forbidden, reason} - Never allowed
    - {:unknown, reason} - Not categorized, assume needs approval
  """
  @spec categorize_action(atom()) :: {atom(), String.t()}
  def categorize_action(action) do
    cond do
      is_forbidden?(action) ->
        {:forbidden, "Security violation - action is never allowed"}

      can_do_autonomously?(action) ->
        {:autonomous, "Safe action - can proceed without approval"}

      requires_approval?(action) ->
        {:needs_approval, "External/destructive action - requires confirmation"}

      true ->
        {:unknown, "Uncategorized action - treating as needs approval for safety"}
    end
  end

  @doc """
  Check if a file path is within the workspace (safe to modify).
  """
  @spec is_workspace_path?(String.t()) :: boolean()
  def is_workspace_path?(path) do
    workspace_abs = Path.expand(@workspace_dir)
    path_abs = Path.expand(path)

    String.starts_with?(path_abs, workspace_abs)
  end

  @doc """
  Check if a file can be modified autonomously.

  Some workspace files require notification even if in workspace.
  """
  @spec can_modify_file?(String.t()) :: {:yes, atom()} | {:notify, atom()} | {:no, atom()}
  def can_modify_file?(path) do
    filename = Path.basename(path)
    workspace_abs = Path.expand(@workspace_dir)
    path_abs = Path.expand(path)

    cond do
      # Not in workspace - needs approval
      not String.starts_with?(path_abs, workspace_abs) ->
        {:no, :outside_workspace}

      # Protected files - can modify but must notify
      filename in ["SOUL.md", "AGENTS.md"] ->
        {:notify, :identity_file}

      # Memory and logs - fully autonomous
      String.starts_with?(filename, "memory/") or
          filename in ["MEMORY.md", "HEARTBEAT.md", "heartbeat-state.json"] ->
        {:yes, :memory_file}

      # Tools and config - fully autonomous
      filename in ["TOOLS.md"] ->
        {:yes, :config_file}

      # Other workspace files - autonomous
      true ->
        {:yes, :workspace_file}
    end
  end

  @doc """
  Request approval for an action.

  Logs the request and returns a token that can be used to confirm later.

  ## Returns
    - {:ok, approval_token} - Request logged, await confirmation
    - {:error, :forbidden} - Action is not allowed
    - {:error, :already_approved} - Action was previously approved
  """
  @spec request_approval(atom(), map()) :: {:ok, String.t()} | {:error, atom()}
  def request_approval(action, context \\ %{}) do
    if is_forbidden?(action) do
      Logger.warning("Attempted forbidden action: #{action}")
      {:error, :forbidden}
    else
      token = generate_approval_token()

      # Store pending approval
      store_pending_approval(token, %{
        action: action,
        context: context,
        requested_at: DateTime.utc_now(),
        status: :pending
      })

      Logger.info("Approval requested for #{action} (token: #{token})")
      {:ok, token}
    end
  end

  @doc """
  Confirm an approval request.
  """
  @spec confirm_approval(String.t()) :: {:ok, map()} | {:error, atom()}
  def confirm_approval(token) do
    case get_pending_approval(token) do
      nil ->
        {:error, :not_found}

      %{status: :approved} ->
        {:error, :already_approved}

      approval ->
        updated = %{approval | status: :approved, approved_at: DateTime.utc_now()}
        store_pending_approval(token, updated)
        Logger.info("Approval confirmed: #{approval.action}")
        {:ok, updated}
    end
  end

  @doc """
  Deny an approval request.
  """
  @spec deny_approval(String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def deny_approval(token, reason \\ "User denied") do
    case get_pending_approval(token) do
      nil ->
        {:error, :not_found}

      approval ->
        updated = %{
          approval
          | status: :denied,
            denied_at: DateTime.utc_now(),
            deny_reason: reason
        }

        store_pending_approval(token, updated)
        Logger.info("Approval denied: #{approval.action} - #{reason}")
        {:ok, updated}
    end
  end

  @doc """
  List all action categories for documentation.
  """
  @spec list_action_categories() :: map()
  def list_action_categories do
    %{
      autonomous: @autonomous_actions,
      needs_approval: @needs_approval,
      forbidden: @forbidden_actions
    }
  end

  # Private Functions

  defp generate_approval_token do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  # Use ETS for pending approvals (in production, would use database)
  defp store_pending_approval(token, approval) do
    :persistent_term.put({__MODULE__, :approval, token}, approval)
  end

  defp get_pending_approval(token) do
    :persistent_term.get({__MODULE__, :approval, token}, nil)
  end
end
