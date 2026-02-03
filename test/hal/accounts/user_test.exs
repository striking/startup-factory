defmodule Hal.Accounts.UserTest do
  use Hal.DataCase, async: true

  alias Hal.Accounts.User

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        external_id: "12345",
        platform: "telegram"
      }

      changeset = User.changeset(%User{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :external_id) == "12345"
      assert get_change(changeset, :platform) == "telegram"
    end

    test "valid changeset with all fields" do
      attrs = %{
        external_id: "12345",
        platform: "telegram",
        username: "testuser",
        settings: %{"theme" => "dark", "notifications" => true}
      }

      changeset = User.changeset(%User{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :username) == "testuser"
      assert get_change(changeset, :settings) == %{"theme" => "dark", "notifications" => true}
    end

    test "invalid changeset without external_id" do
      attrs = %{platform: "telegram"}

      changeset = User.changeset(%User{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).external_id
    end

    test "invalid changeset without platform" do
      attrs = %{external_id: "12345"}

      changeset = User.changeset(%User{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).platform
    end

    test "invalid changeset with invalid platform" do
      attrs = %{
        external_id: "12345",
        platform: "whatsapp"
      }

      changeset = User.changeset(%User{}, attrs)

      refute changeset.valid?

      assert "must be one of: telegram, slack, discord, email, terminal" in errors_on(changeset).platform
    end

    test "validates external_id max length" do
      attrs = %{
        external_id: String.duplicate("a", 256),
        platform: "telegram"
      }

      changeset = User.changeset(%User{}, attrs)

      refute changeset.valid?
      assert "should be at most 255 character(s)" in errors_on(changeset).external_id
    end

    test "validates username max length" do
      attrs = %{
        external_id: "12345",
        platform: "telegram",
        username: String.duplicate("a", 256)
      }

      changeset = User.changeset(%User{}, attrs)

      refute changeset.valid?
      assert "should be at most 255 character(s)" in errors_on(changeset).username
    end

    test "accepts all valid platforms" do
      for platform <- User.valid_platforms() do
        attrs = %{external_id: "12345", platform: platform}
        changeset = User.changeset(%User{}, attrs)
        assert changeset.valid?, "Expected #{platform} to be valid"
      end
    end
  end

  describe "database operations" do
    test "can insert a user" do
      attrs = %{
        external_id: "telegram_123",
        platform: "telegram",
        username: "testuser"
      }

      {:ok, user} = %User{} |> User.changeset(attrs) |> Repo.insert()

      assert user.id
      assert user.external_id == "telegram_123"
      assert user.platform == "telegram"
      assert user.username == "testuser"
      assert user.settings == %{}
      assert user.inserted_at
      assert user.updated_at
    end

    test "enforces unique constraint on platform + external_id" do
      attrs = %{
        external_id: "unique_test_123",
        platform: "telegram"
      }

      {:ok, _user1} = %User{} |> User.changeset(attrs) |> Repo.insert()

      {:error, changeset} = %User{} |> User.changeset(attrs) |> Repo.insert()

      refute changeset.valid?
      assert "user already exists for this platform" in errors_on(changeset).platform
    end

    test "allows same external_id on different platforms" do
      external_id = "cross_platform_user"

      {:ok, telegram_user} =
        %User{}
        |> User.changeset(%{external_id: external_id, platform: "telegram"})
        |> Repo.insert()

      {:ok, slack_user} =
        %User{}
        |> User.changeset(%{external_id: external_id, platform: "slack"})
        |> Repo.insert()

      assert telegram_user.id != slack_user.id
      assert telegram_user.external_id == slack_user.external_id
    end

    test "can query users by platform" do
      {:ok, _} =
        %User{} |> User.changeset(%{external_id: "t1", platform: "telegram"}) |> Repo.insert()

      {:ok, _} =
        %User{} |> User.changeset(%{external_id: "t2", platform: "telegram"}) |> Repo.insert()

      {:ok, _} =
        %User{} |> User.changeset(%{external_id: "s1", platform: "slack"}) |> Repo.insert()

      telegram_users = User |> where(platform: "telegram") |> Repo.all()
      slack_users = User |> where(platform: "slack") |> Repo.all()

      assert length(telegram_users) == 2
      assert length(slack_users) == 1
    end
  end

  describe "valid_platforms/0" do
    test "returns expected platforms" do
      platforms = User.valid_platforms()

      assert "telegram" in platforms
      assert "slack" in platforms
      assert "discord" in platforms
      assert "email" in platforms
      assert "terminal" in platforms
      assert length(platforms) == 5
    end
  end
end
