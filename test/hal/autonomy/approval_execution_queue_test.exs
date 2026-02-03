defmodule HAL.Autonomy.ApprovalExecutionQueueTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Hal.Repo

  alias Ecto.Adapters.SQL.Sandbox
  alias HAL.Autonomy.{ApprovalExecutionWorker, Approvals}
  alias Hal.Repo

  defp create_user!(attrs \\ %{}) do
    defaults = %{
      external_id: "approvals-queue-test-user",
      platform: "terminal",
      username: "Approvals Queue Test User",
      role: "owner"
    }

    %Hal.Accounts.User{}
    |> Hal.Accounts.User.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  setup do
    :ok = Sandbox.checkout(Hal.Repo)
    Sandbox.mode(Hal.Repo, {:shared, self()})

    on_exit(fn ->
      Sandbox.checkin(Hal.Repo)
    end)

    # Ensure an Oban supervisor exists for this test. We rely on `Oban.insert/1`
    # from the approvals module.
    if is_nil(Oban.Registry.whereis(Oban)) do
      oban_config =
        :hal
        |> Application.fetch_env!(Oban)
        |> Keyword.put(:testing, :manual)

      case start_supervised({Oban, oban_config}) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
    end

    original = Application.get_env(:hal, HAL.Autonomy.Approvals, [])
    Application.put_env(:hal, HAL.Autonomy.Approvals, Keyword.put(original, :auto_execute, true))

    on_exit(fn ->
      Application.put_env(:hal, HAL.Autonomy.Approvals, original)
    end)

    :ok
  end

  test "approve/1 enqueues ApprovalExecutionWorker when auto_execute enabled" do
    user = create_user!()
    {:ok, req} = Approvals.request(user.id, "hal_delegate_to_codex", %{"task" => "Do the thing"})

    assert is_pid(Oban.Registry.whereis(Oban))

    Oban.Testing.with_testing_mode(:manual, fn ->
      # Avoid inheriting inline mode through `$callers`.
      previous_callers = Process.get(:"$callers")
      Process.put(:"$callers", [])

      assert {:ok, approved} = Approvals.approve(req.token)
      assert approved.execution_status == "queued"

      assert_enqueued(worker: ApprovalExecutionWorker, args: %{"token" => req.token})

      if is_nil(previous_callers) do
        Process.delete(:"$callers")
      else
        Process.put(:"$callers", previous_callers)
      end
    end)
  end
end
