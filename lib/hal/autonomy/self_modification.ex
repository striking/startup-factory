defmodule HAL.Autonomy.SelfModification do
  @moduledoc """
  Allow HAL to modify its own workspace files with appropriate safeguards.

  HAL can update memory, heartbeat, and even its identity files (with notification).
  This enables learning and self-improvement over time.

  ## Modification Categories

  1. **Free to Modify** - Memory, daily logs, heartbeat state
  2. **Modify + Notify** - SOUL.md, AGENTS.md (identity files)
  3. **Never Modify** - User files outside workspace

  ## Usage

      # Update memory (free)
      iex> SelfModification.update_file("workspace/MEMORY.md", content)
      :ok

      # Update identity (notifies user)
      iex> SelfModification.update_file("workspace/SOUL.md", content, reason: "Learned new preference")
      :ok  # Also sends notification

      # Append to daily log
      iex> SelfModification.append_to_daily_log("Completed task X")
      :ok
  """

  require Logger

  alias HAL.Autonomy.Authorization

  @workspace_dir Application.compile_env(:hal, :workspace_dir, "workspace")

  # File categories are defined in HAL.Autonomy.Authorization module:
  # - Free to modify: MEMORY.md, HEARTBEAT.md, heartbeat-state.json, TOOLS.md
  # - Notify on modify: SOUL.md, AGENTS.md, USER.md

  @doc """
  Update a workspace file with safeguards.

  ## Options
    - reason: Why the file is being updated (required for identity files)
    - notify: Override notification behavior

  ## Returns
    - :ok on success
    - {:error, :outside_workspace} if path is outside workspace
    - {:error, :notification_failed} if identity file change notification failed
  """
  @spec update_file(String.t(), String.t(), keyword()) :: :ok | {:error, atom()}
  def update_file(path, content, opts \\ []) do
    reason = Keyword.get(opts, :reason)
    force_notify = Keyword.get(opts, :notify, nil)

    # Normalize path
    full_path = normalize_path(path)
    filename = Path.basename(full_path)

    case Authorization.can_modify_file?(full_path) do
      {:no, reason} ->
        Logger.warning("Attempted to modify file outside workspace: #{path}")
        {:error, reason}

      {:notify, _type} ->
        # Modify but notify user
        result = do_write(full_path, content)

        if result == :ok do
          if force_notify != false do
            notify_identity_change(filename, reason)
          end
        end

        result

      {:yes, _type} ->
        # Free to modify
        do_write(full_path, content)
    end
  end

  @doc """
  Append content to a file (useful for logs).
  """
  @spec append_to_file(String.t(), String.t()) :: :ok | {:error, atom()}
  def append_to_file(path, content) do
    full_path = normalize_path(path)

    case Authorization.can_modify_file?(full_path) do
      {:no, reason} ->
        {:error, reason}

      _ ->
        # Read existing content
        existing =
          case File.read(full_path) do
            {:ok, data} -> data
            {:error, :enoent} -> ""
            {:error, _} -> ""
          end

        # Append new content
        do_write(full_path, existing <> "\n" <> content)
    end
  end

  @doc """
  Append an entry to today's daily log.

  Format: [HH:MM] Content
  """
  @spec append_to_daily_log(String.t()) :: :ok | {:error, atom()}
  def append_to_daily_log(content) do
    today = Date.utc_today() |> Date.to_string()
    log_path = Path.join([@workspace_dir, "memory", "#{today}.md"])

    # Ensure memory directory exists
    File.mkdir_p!(Path.dirname(log_path))

    # Format entry with timestamp
    time = DateTime.utc_now() |> Calendar.strftime("%H:%M")
    entry = "[#{time}] #{content}"

    append_to_file(log_path, entry)
  end

  @doc """
  Add a memory to MEMORY.md (long-term curated memory).

  ## Parameters
    - content: The memory to add
    - type: :preference, :fact, :decision, :knowledge

  ## Format
  Entries are added with timestamp and type:
  ```
  [2026-01-30] (preference)
  I prefer dark mode and minimal UI.
  ```
  """
  @spec add_memory(String.t(), atom()) :: :ok | {:error, atom()}
  def add_memory(content, type \\ :knowledge) do
    memory_path = Path.join(@workspace_dir, "MEMORY.md")

    # Format entry
    date = Date.utc_today() |> Date.to_string()

    entry = """

    [#{date}] (#{type})
    #{content}
    """

    append_to_file(memory_path, entry)
  end

  @doc """
  Update HEARTBEAT.md with a new checklist.
  """
  @spec update_heartbeat_checklist([String.t()]) :: :ok | {:error, atom()}
  def update_heartbeat_checklist(items) do
    heartbeat_path = Path.join(@workspace_dir, "HEARTBEAT.md")

    content = """
    # HEARTBEAT.md

    # Checklist for autonomous work
    #{Enum.map_join(items, "\n", &"- [ ] #{&1}")}

    # Keep this file minimal to save tokens.
    # Empty file = skip heartbeat API calls.
    """

    update_file(heartbeat_path, content)
  end

  @doc """
  Add an item to the heartbeat checklist.
  """
  @spec add_heartbeat_item(String.t()) :: :ok | {:error, atom()}
  def add_heartbeat_item(item) do
    heartbeat_path = Path.join(@workspace_dir, "HEARTBEAT.md")

    append_to_file(heartbeat_path, "- [ ] #{item}")
  end

  @doc """
  Update SOUL.md (identity) - requires reason and notifies user.
  """
  @spec update_soul(String.t(), String.t()) :: :ok | {:error, atom()}
  def update_soul(content, reason) do
    if reason == nil or reason == "" do
      {:error, :reason_required}
    else
      update_file("SOUL.md", content, reason: reason)
    end
  end

  @doc """
  Update AGENTS.md (operating instructions) - requires reason and notifies user.
  """
  @spec update_agents(String.t(), String.t()) :: :ok | {:error, atom()}
  def update_agents(content, reason) do
    if reason == nil or reason == "" do
      {:error, :reason_required}
    else
      update_file("AGENTS.md", content, reason: reason)
    end
  end

  @doc """
  Create a backup of a file before modifying.
  """
  @spec backup_file(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def backup_file(path) do
    full_path = normalize_path(path)

    if File.exists?(full_path) do
      timestamp = DateTime.utc_now() |> DateTime.to_unix()
      backup_path = "#{full_path}.#{timestamp}.backup"

      case File.copy(full_path, backup_path) do
        {:ok, _} ->
          Logger.debug("Created backup: #{backup_path}")
          {:ok, backup_path}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :file_not_found}
    end
  end

  @doc """
  Restore a file from backup.
  """
  @spec restore_from_backup(String.t()) :: :ok | {:error, atom()}
  def restore_from_backup(backup_path) do
    if File.exists?(backup_path) do
      # Extract original path from backup path
      original_path = String.replace(backup_path, ~r/\.\d+\.backup$/, "")

      case File.copy(backup_path, original_path) do
        {:ok, _} ->
          Logger.info("Restored from backup: #{original_path}")
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :backup_not_found}
    end
  end

  @doc """
  List available backups for a file.
  """
  @spec list_backups(String.t()) :: [String.t()]
  def list_backups(path) do
    full_path = normalize_path(path)
    dir = Path.dirname(full_path)
    base = Path.basename(full_path)

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.starts_with?(&1, "#{base}."))
        |> Enum.filter(&String.ends_with?(&1, ".backup"))
        |> Enum.map(&Path.join(dir, &1))
        |> Enum.sort(:desc)

      {:error, _} ->
        []
    end
  end

  # Private Functions

  defp normalize_path(path) do
    if Path.type(path) == :absolute do
      path
    else
      Path.join(@workspace_dir, path)
    end
  end

  defp do_write(path, content) do
    # Ensure directory exists
    File.mkdir_p!(Path.dirname(path))

    case File.write(path, content) do
      :ok ->
        Logger.debug("Updated file: #{path}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to write #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp notify_identity_change(filename, reason) do
    message = """
    I updated my #{filename}

    Reason: #{reason || "Self-improvement"}

    Please review when you have a moment.
    """

    # Try to notify via available channels
    case notify_user(message) do
      :ok ->
        Logger.info("Notified user of identity change: #{filename}")
        :ok

      {:error, _} ->
        # Log to daily log as fallback
        append_to_daily_log("NOTICE: Updated #{filename} - #{reason || "self-improvement"}")
        :ok
    end
  end

  defp notify_user(message) do
    # Try notification system if available (use apply to avoid compile-time warning)
    if Code.ensure_loaded?(Hal.Notifications) do
      try do
        apply(Hal.Notifications, :notify, [:system, message, [priority: :normal]])
        :ok
      rescue
        _ -> {:error, :notification_failed}
      end
    else
      {:error, :no_notification_system}
    end
  end
end
