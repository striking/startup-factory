defmodule Hal.Release do
  @moduledoc """
  Release tasks for HAL.

  This module provides functions that can be called from a release
  without having mix available, such as database migrations.

  ## Usage

  From the release:

      # Run all pending migrations
      bin/hal eval "Hal.Release.migrate()"

      # Rollback the last migration
      bin/hal eval "Hal.Release.rollback(Hal.Repo, 1)"

      # Create the database (if it doesn't exist)
      bin/hal eval "Hal.Release.create_database()"

      # Drop the database (DANGEROUS!)
      bin/hal eval "Hal.Release.drop_database()"
  """

  @app :hal

  @doc """
  Runs all pending database migrations.
  """
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Rolls back the database by the given number of steps.
  """
  def rollback(repo, step \\ 1) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, step: step))
  end

  @doc """
  Creates the database if it doesn't exist.
  """
  def create_database do
    load_app()

    for repo <- repos() do
      case repo.__adapter__().storage_up(repo.config()) do
        :ok -> :ok
        {:error, :already_up} -> :ok
        {:error, term} -> {:error, term}
      end
    end
  end

  @doc """
  Drops the database. Use with caution!
  """
  def drop_database do
    load_app()

    for repo <- repos() do
      case repo.__adapter__().storage_down(repo.config()) do
        :ok -> :ok
        {:error, :already_down} -> :ok
        {:error, term} -> {:error, term}
      end
    end
  end

  @doc """
  Seeds the database with initial data.
  """
  def seed do
    load_app()
    migrate()

    seed_file = Application.app_dir(@app, "priv/repo/seeds.exs")

    if File.exists?(seed_file) do
      Code.eval_file(seed_file)
    end
  end

  @doc """
  Returns the migration status for all repositories.
  """
  def migration_status do
    load_app()

    for repo <- repos() do
      {:ok, status, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.migrations(repo)
        end)

      {repo, status}
    end
  end

  @doc """
  Prints the current migration status.
  """
  def print_migration_status do
    for {repo, migrations} <- migration_status() do
      IO.puts("\n#{inspect(repo)} migrations:")
      IO.puts(String.duplicate("-", 60))

      for {status, version, name} <- migrations do
        status_str = if status == :up, do: "[UP]  ", else: "[DOWN]"
        IO.puts("  #{status_str} #{version} #{name}")
      end
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
