defmodule Mix.Tasks.Hal.Doctor do
  @shortdoc "Checks local HAL deploy readiness"

  @moduledoc """
  `mix hal.doctor`

  Runs a local preflight check for running HAL:

  - Repo connectivity
  - Migration status (pending migrations)
  - Key runtime dependencies (node, codex, python)
  - Required workspace files
  - Agent SDK bridge artifacts

  This is intentionally a read-only check. It does not modify the system.
  """

  use Mix.Task

  import Ecto.Query, only: [from: 2]

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("HAL Doctor\n")

    check_executables()
    check_workspace_files()
    check_agent_sdk_artifacts()
    check_repo_and_migrations()
  end

  defp check_executables do
    Mix.shell().info("Executables")

    report_exe("node")
    report_exe("python3")
    report_exe("codex")
    report_exe("claude")

    Mix.shell().info("")
  end

  defp report_exe(name) do
    case System.find_executable(name) do
      nil -> Mix.shell().error("  - #{name}: MISSING")
      path -> Mix.shell().info("  - #{name}: #{path}")
    end
  end

  defp check_workspace_files do
    workspace_dir = Application.get_env(:hal, :workspace_dir, "workspace")

    Mix.shell().info("Workspace")
    Mix.shell().info("  - dir: #{Path.expand(workspace_dir)}")

    required = [
      Path.join(workspace_dir, "AGENTS.md"),
      Path.join(workspace_dir, "SOUL.md"),
      Path.join(workspace_dir, "HEARTBEAT.md")
    ]

    Enum.each(required, &report_file/1)
    Mix.shell().info("")
  end

  defp check_agent_sdk_artifacts do
    Mix.shell().info("Agent SDK")

    report_file(Path.join(["priv", "agent-sdk", "dist", "bridge.js"]))
    report_file(Path.join(["priv", "agent-sdk", "dist", "bridge.js.map"]))

    report_file(Path.join(["priv", "codex-sdk", "dist", "bridge.js"]))
    report_file(Path.join(["priv", "codex-sdk", "dist", "bridge.js.map"]))

    Mix.shell().info("")
  end

  defp report_file(path) do
    if File.exists?(path) do
      Mix.shell().info("  - #{path}: OK")
    else
      Mix.shell().error("  - #{path}: MISSING")
    end
  end

  defp check_repo_and_migrations do
    Mix.shell().info("Database")

    ensure_ecto_started!()

    case Hal.Repo.start_link(pool_size: 2) do
      {:ok, pid} ->
        report_repo_ok()
        report_migrations()
        report_security()
        GenServer.stop(pid)

      {:error, {:already_started, _pid}} ->
        report_repo_ok()
        report_migrations()
        report_security()

      {:error, reason} ->
        Mix.shell().error("  - repo: ERROR #{inspect(reason)}")
    end

    Mix.shell().info("")
  end

  defp ensure_ecto_started! do
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
  end

  defp report_repo_ok do
    # A tiny query to ensure DB connectivity.
    _ = Hal.Repo.one(from(u in Hal.Accounts.User, select: 1, limit: 1))
    Mix.shell().info("  - repo: OK")
  rescue
    e ->
      Mix.shell().error("  - repo: ERROR #{Exception.message(e)}")
  end

  defp report_migrations do
    migrations_path = Application.app_dir(:hal, "priv/repo/migrations")
    migrations = Ecto.Migrator.migrations(Hal.Repo, migrations_path)

    pending =
      migrations
      |> Enum.filter(fn {status, _version, _name} -> status != :up end)

    case pending do
      [] ->
        Mix.shell().info("  - migrations: OK (up to date)")

      _ ->
        Mix.shell().error("  - migrations: PENDING (run `mix ecto.migrate`)")

        Enum.each(pending, fn {_status, version, name} ->
          Mix.shell().error("    - #{version} #{name}")
        end)
    end
  end

  defp report_security do
    Mix.shell().info("Security")

    Mix.shell().info("  - dm_policy: #{inspect(Hal.Security.dm_policy())}")
    Mix.shell().info("  - group_policy: #{inspect(Hal.Security.group_policy())}")
    Mix.shell().info("  - dm_allowlist: #{MapSet.size(Hal.Security.dm_allowlist())}")
    Mix.shell().info("  - group_allowlist: #{MapSet.size(Hal.Security.group_allowlist())}")

    owner_count =
      from(u in Hal.Accounts.User, where: u.role == "owner")
      |> Hal.Repo.aggregate(:count, :id)

    if owner_count > 0 do
      Mix.shell().info("  - owners: OK (#{owner_count})")
    else
      Mix.shell().error("  - owners: MISSING (no users with role=owner)")
    end
  rescue
    e ->
      Mix.shell().error("  - security: ERROR #{Exception.message(e)}")
  end
end
