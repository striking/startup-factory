defmodule Hal.Gateway.GatewayTest do
  @moduledoc """
  Tests for the Gateway supervisor module.
  """
  use Hal.DataCase, async: false

  alias Hal.Gateway

  describe "start_link/1" do
    test "starts the gateway supervisor successfully" do
      # Generate unique names for this test
      test_id = System.unique_integer([:positive])
      registry_name = :"TestRegistry#{test_id}"
      supervisor_name = :"TestDynamicSupervisor#{test_id}"
      session_manager_name = :"TestSessionManager#{test_id}"
      session_cleaner_name = :"TestSessionCleaner#{test_id}"
      router_name = :"TestRouter#{test_id}"
      gateway_name = :"TestGateway#{test_id}"

      opts = [
        name: gateway_name,
        registry_name: registry_name,
        dynamic_supervisor_name: supervisor_name,
        session_manager_name: session_manager_name,
        session_cleaner_name: session_cleaner_name,
        router_name: router_name
      ]

      assert {:ok, pid} = Gateway.start_link(opts)
      assert Process.alive?(pid)

      # Allow the SessionManager to access the DB sandbox
      Ecto.Adapters.SQL.Sandbox.allow(Hal.Repo, self(), Process.whereis(session_manager_name))

      # Give SessionManager time to load sessions
      Process.sleep(50)

      # Verify all children are started
      assert Process.whereis(registry_name) != nil
      assert Process.whereis(supervisor_name) != nil
      assert Process.whereis(session_manager_name) != nil
      assert Process.whereis(session_cleaner_name) != nil
      assert Process.whereis(router_name) != nil

      # Clean up
      Supervisor.stop(pid)
    end

    test "children restart on failure" do
      test_id = System.unique_integer([:positive])
      registry_name = :"TestRegistry#{test_id}"
      supervisor_name = :"TestDynamicSupervisor#{test_id}"
      session_manager_name = :"TestSessionManager#{test_id}"
      session_cleaner_name = :"TestSessionCleaner#{test_id}"
      router_name = :"TestRouter#{test_id}"
      gateway_name = :"TestGateway#{test_id}"

      opts = [
        name: gateway_name,
        registry_name: registry_name,
        dynamic_supervisor_name: supervisor_name,
        session_manager_name: session_manager_name,
        session_cleaner_name: session_cleaner_name,
        router_name: router_name
      ]

      {:ok, gateway_pid} = Gateway.start_link(opts)

      # Allow the SessionManager to access the DB sandbox
      Ecto.Adapters.SQL.Sandbox.allow(Hal.Repo, self(), Process.whereis(session_manager_name))

      # Give SessionManager time to load sessions
      Process.sleep(50)

      # Get the router PID
      router_pid = Process.whereis(router_name)
      assert router_pid != nil

      # Monitor the router to know when it dies
      ref = Process.monitor(router_pid)

      # Kill the router
      Process.exit(router_pid, :kill)

      # Wait for the router to actually die
      assert_receive {:DOWN, ^ref, :process, ^router_pid, :killed}, 1000

      # Give supervisor time to restart (poll for the new process)
      new_router_pid =
        Enum.reduce_while(1..20, nil, fn _, _acc ->
          Process.sleep(10)

          case Process.whereis(router_name) do
            nil -> {:cont, nil}
            pid when pid != router_pid -> {:halt, pid}
            _ -> {:cont, nil}
          end
        end)

      # Router should be restarted with same name
      assert new_router_pid != nil
      assert new_router_pid != router_pid

      Supervisor.stop(gateway_pid)
    end
  end

  describe "child_spec/1" do
    test "returns valid child spec" do
      spec = Gateway.child_spec([])

      assert spec.id == Gateway
      assert spec.start == {Gateway, :start_link, [[]]}
      assert spec.type == :supervisor
    end
  end
end
