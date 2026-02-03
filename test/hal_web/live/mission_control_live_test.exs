defmodule HalWeb.MissionControlLiveTest do
  use HalWeb.LiveViewCase, async: true

  alias HAL.Autonomy.Approvals
  alias Hal.Repo
  alias Hal.Tasks.AutoTask

  defp create_owner!(attrs \\ %{}) do
    defaults = %{
      external_id: "mission-control-test-user",
      platform: "terminal",
      username: "Mission Control Test User",
      role: "owner"
    }

    %Hal.Accounts.User{}
    |> Hal.Accounts.User.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp create_task!(user, attrs \\ %{}) do
    defaults = %{
      user_id: user.id,
      title: "Test Task",
      original_request: "Do the thing",
      status: "pending",
      steps: [%{name: "step1", prompt: "do", status: "pending"}]
    }

    %AutoTask{}
    |> AutoTask.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  test "renders snapshot (tasks + approvals)", %{conn: conn} do
    user = create_owner!()
    task = create_task!(user, %{title: "Write docs"})

    {:ok, req} =
      Approvals.request(user.id, "hal_delegate_to_codex", %{"task" => "Create foo.txt"})

    {:ok, _view, html} = live(conn, ~p"/mission-control")

    assert html =~ "Mission Control"
    assert html =~ task.title
    assert html =~ req.token
  end
end
