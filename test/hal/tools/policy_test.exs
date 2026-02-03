defmodule Hal.Tools.PolicyTest do
  use Hal.DataCase, async: true

  alias Hal.Repo
  alias Hal.Tools.Policy

  defp create_user!(attrs \\ %{}) do
    defaults = %{
      external_id: "policy-test-user-#{System.unique_integer([:positive])}",
      platform: "terminal",
      username: "Policy Test User",
      role: "user"
    }

    %Hal.Accounts.User{}
    |> Hal.Accounts.User.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  test "unpaired non-owner is denied" do
    user = create_user!()

    assert {:deny, %{reason: :not_paired}} =
             Policy.authorize("hal_memory_search", %{"query" => "x"}, user_id: user.id)
  end

  test "paired non-owner can use memory tools" do
    user = create_user!(%{paired_at: DateTime.utc_now()})

    assert :allow =
             Policy.authorize("hal_memory_search", %{"query" => "x"}, user_id: user.id)
  end

  test "paired non-owner cannot use owner-only tools" do
    user = create_user!(%{paired_at: DateTime.utc_now()})

    assert {:deny, %{reason: :owner_only}} =
             Policy.authorize("hal_delegate_to_codex", %{"task" => "do"}, user_id: user.id)
  end

  test "owner can use owner-only tools" do
    user = create_user!(%{role: "owner"})

    assert :allow =
             Policy.authorize("hal_delegate_to_codex", %{"task" => "do"}, user_id: user.id)
  end
end
