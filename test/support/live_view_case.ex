defmodule HalWeb.LiveViewCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require LiveView functionality.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with LiveView
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import HalWeb.LiveViewCase

      # The default endpoint for testing
      @endpoint HalWeb.Endpoint

      use HalWeb, :verified_routes
    end
  end

  setup tags do
    Hal.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
