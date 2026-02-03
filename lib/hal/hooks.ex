defmodule Hal.Hooks do
  @moduledoc """
  Event-driven hooks system (Moltbot pattern).

  Hooks execute automatically when specific events occur:
  - session-start: Load AGENTS.md, MEMORY.md when session starts
  - session-memory: Save conversation context to daily log
  - command-logger: Audit trail of commands (optional)

  ## Usage

      # Trigger hook
      Hal.Hooks.trigger(:session_start, %{
        user_id: "abc123",
        session_id: "session-1",
        channel_type: "telegram"
      })

  ## Available Hooks

  - `:boot_md` - Load workspace files on session start
  - `:session_memory` - Auto-save to daily log
  - `:command_logger` - Log commands to audit trail
  """

  require Logger

  @workspace_dir Application.compile_env(:hal, :workspace_dir, "workspace")

  @doc """
  Trigger a hook with event context.

  ## Events

  - `:session_start` - New session created
  - `:session_message` - Message received in session
  - `:session_end` - Session terminated
  - `:command` - Command executed

  ## Context

  Maps containing event-specific data (user_id, session_id, etc.)
  """
  @spec trigger(atom(), map()) :: :ok
  def trigger(event, context) do
    case event do
      :session_start -> run_boot_md(context)
      :session_message -> run_session_memory(context)
      :command -> run_command_logger(context)
      _ -> :ok
    end
  end

  ## Hook Implementations

  @doc """
  boot-md hook: Load workspace files on session start.

  Loads:
  - AGENTS.md - Boot instructions
  - SOUL.md - HAL's identity
  - USER.md - About Chris
  - MEMORY.md - Long-term memory (main sessions only)
  - memory/yesterday.md - Recent context
  - memory/today.md - Today's log

  Returns system prompt to inject into Claude Code.
  """
  @spec run_boot_md(map()) :: String.t()
  def run_boot_md(%{user_id: user_id, channel_type: channel_type} = _context) do
    is_main_session = is_main_session?(channel_type)

    files_to_load = [
      {"AGENTS.md", @workspace_dir},
      {"SOUL.md", @workspace_dir},
      {"USER.md", @workspace_dir},
      {"memory/#{yesterday_date()}.md", user_workspace_dir(user_id)},
      {"memory/#{today_date()}.md", user_workspace_dir(user_id)}
    ]

    # Only load MEMORY.md in main sessions (privacy)
    files_to_load =
      if is_main_session do
        files_to_load ++ [{"MEMORY.md", user_workspace_dir(user_id)}]
      else
        files_to_load
      end

    content =
      files_to_load
      |> Enum.map(fn {filename, base_dir} ->
        path = Path.join(base_dir, filename)
        load_file_with_header(path, filename)
      end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n---\n\n")

    if content != "" do
      Logger.info("boot-md hook: Loaded workspace files")
      content
    else
      Logger.debug("boot-md hook: No files found")
      ""
    end
  end

  @doc """
  session-memory hook: Auto-save conversation to daily log.

  Appends message to memory/YYYY-MM-DD.md with timestamp and context.
  """
  @spec run_session_memory(map()) :: :ok
  def run_session_memory(%{
        user_id: user_id,
        message: message,
        session_id: session_id,
        channel_type: channel_type
      }) do
    timestamp = DateTime.utc_now() |> DateTime.to_string()

    entry = """
    **[#{timestamp}]** (#{channel_type}/#{session_id})
    #{message}

    """

    daily_log_path = Path.join([user_workspace_dir(user_id), "memory", "#{today_date()}.md"])
    ensure_file_exists(daily_log_path, "# Daily Log - #{today_date()}\n\n")

    case File.write(daily_log_path, entry, [:append]) do
      :ok ->
        Logger.debug("session-memory hook: Saved to #{today_date()}.md")
        :ok

      {:error, reason} ->
        Logger.error("session-memory hook failed: #{inspect(reason)}")
        :ok
    end
  end

  def run_session_memory(_), do: :ok

  @doc """
  command-logger hook: Log commands to audit trail.

  Appends to workspace/logs/commands.log in JSONL format.
  """
  @spec run_command_logger(map()) :: :ok
  def run_command_logger(%{command: command, user_id: user_id} = context) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    log_entry = %{
      timestamp: timestamp,
      user_id: user_id,
      command: command,
      session_id: Map.get(context, :session_id),
      channel_type: Map.get(context, :channel_type)
    }

    log_path = Path.join(@workspace_dir, "logs/commands.log")
    ensure_file_exists(log_path, "")

    json_line = Jason.encode!(log_entry) <> "\n"

    case File.write(log_path, json_line, [:append]) do
      :ok ->
        Logger.debug("command-logger hook: Logged #{command}")
        :ok

      {:error, reason} ->
        Logger.error("command-logger hook failed: #{inspect(reason)}")
        :ok
    end
  end

  def run_command_logger(_), do: :ok

  # Private Helpers

  defp is_main_session?(channel_type) do
    # Main sessions = direct chats (telegram, terminal)
    # NOT main sessions = group chats, public channels
    channel_type in ["telegram", "terminal", "slack_dm"]
  end

  defp user_workspace_dir(user_id) do
    Path.join([@workspace_dir, "users", user_id])
  end

  defp today_date, do: Date.utc_today() |> Date.to_string()
  defp yesterday_date, do: Date.add(Date.utc_today(), -1) |> Date.to_string()

  defp load_file_with_header(path, filename) do
    case File.read(path) do
      {:ok, content} when content != "" ->
        """
        # === #{filename} ===

        #{content}
        """

      _ ->
        ""
    end
  end

  defp ensure_file_exists(path, default_content) do
    dir = Path.dirname(path)
    File.mkdir_p!(dir)

    unless File.exists?(path) do
      File.write!(path, default_content)
    end
  end
end
