defmodule Hal.ReleaseTest do
  use ExUnit.Case, async: true

  describe "Release module" do
    test "module exists and exports expected functions" do
      # Load the module first
      Code.ensure_loaded!(Hal.Release)

      # Check that all expected functions are exported
      assert function_exported?(Hal.Release, :migrate, 0)
      # rollback/2 has a default argument, so both arities should work
      assert function_exported?(Hal.Release, :rollback, 2)
      assert function_exported?(Hal.Release, :create_database, 0)
      assert function_exported?(Hal.Release, :drop_database, 0)
      assert function_exported?(Hal.Release, :seed, 0)
      assert function_exported?(Hal.Release, :migration_status, 0)
      assert function_exported?(Hal.Release, :print_migration_status, 0)
    end

    test "module has proper documentation" do
      {:docs_v1, _, _, _, %{"en" => module_doc}, _, _} = Code.fetch_docs(Hal.Release)
      assert module_doc =~ "Release tasks for HAL"
    end
  end
end
