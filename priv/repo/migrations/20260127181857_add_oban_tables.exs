defmodule Hal.Repo.Migrations.AddObanTables do
  @moduledoc """
  Migration to create Oban job queue tables.

  Oban uses PostgreSQL-specific features for reliable job processing:
  - NOTIFY/LISTEN for real-time job insertion notification
  - Advisory locks for concurrent processing
  - Partial indexes for efficient queue polling

  This migration creates:
  - oban_jobs: Main job table with state, queue, args, etc.
  - oban_peers: Cluster coordination for multi-node setups
  """

  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 12)
  end

  def down do
    Oban.Migration.down(version: 1)
  end
end
