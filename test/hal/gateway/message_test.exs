defmodule Hal.Gateway.MessageTest do
  use Hal.DataCase, async: true

  alias Hal.Accounts.User
  alias Hal.Gateway.Message
  alias Hal.Gateway.Session

  # Helper to create a test user
  defp create_user do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        external_id: "test_user_#{System.unique_integer([:positive])}",
        platform: "telegram"
      })
      |> Repo.insert()

    user
  end

  # Helper to create a test session
  defp create_session(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, session} =
      %Session{}
      |> Session.changeset(%{
        channel_type: "telegram",
        channel_id: "chat_#{System.unique_integer([:positive])}",
        user_id: user.id,
        last_activity: now
      })
      |> Repo.insert()

    session
  end

  describe "changeset/2" do
    test "valid changeset with required fields" do
      user = create_user()
      session = create_session(user)

      attrs = %{
        session_id: session.id,
        role: "user",
        content: "Hello, HAL!"
      }

      changeset = Message.changeset(%Message{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :role) == "user"
      assert get_change(changeset, :content) == "Hello, HAL!"
    end

    test "valid changeset with all fields" do
      user = create_user()
      session = create_session(user)

      attrs = %{
        session_id: session.id,
        role: "assistant",
        content: "Hello! How can I help you today?",
        attachments: [
          %{"type" => "image", "url" => "https://example.com/image.png"},
          %{"type" => "file", "name" => "document.pdf"}
        ],
        metadata: %{
          "model" => "claude-3-opus",
          "tokens" => 150,
          "tool_calls" => ["bash", "read"]
        }
      }

      changeset = Message.changeset(%Message{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :attachments) == attrs.attachments
      assert get_change(changeset, :metadata) == attrs.metadata
    end

    test "invalid changeset without session_id" do
      attrs = %{
        role: "user",
        content: "Hello!"
      }

      changeset = Message.changeset(%Message{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).session_id
    end

    test "invalid changeset without role" do
      user = create_user()
      session = create_session(user)

      attrs = %{
        session_id: session.id,
        content: "Hello!"
      }

      changeset = Message.changeset(%Message{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).role
    end

    test "invalid changeset without content" do
      user = create_user()
      session = create_session(user)

      attrs = %{
        session_id: session.id,
        role: "user"
      }

      changeset = Message.changeset(%Message{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).content
    end

    test "invalid changeset with empty content" do
      user = create_user()
      session = create_session(user)

      attrs = %{
        session_id: session.id,
        role: "user",
        content: ""
      }

      changeset = Message.changeset(%Message{}, attrs)

      refute changeset.valid?
      # Empty string fails validate_required, not validate_length
      assert "can't be blank" in errors_on(changeset).content
    end

    test "invalid changeset with invalid role" do
      user = create_user()
      session = create_session(user)

      attrs = %{
        session_id: session.id,
        role: "admin",
        content: "Hello!"
      }

      changeset = Message.changeset(%Message{}, attrs)

      refute changeset.valid?
      assert "must be one of: user, assistant, system" in errors_on(changeset).role
    end

    test "accepts all valid roles" do
      user = create_user()
      session = create_session(user)

      for role <- Message.valid_roles() do
        attrs = %{
          session_id: session.id,
          role: role,
          content: "Test message"
        }

        changeset = Message.changeset(%Message{}, attrs)
        assert changeset.valid?, "Expected role #{role} to be valid"
      end
    end

    test "validates attachments must be a list of maps" do
      user = create_user()
      session = create_session(user)

      # Valid: list of maps
      valid_attrs = %{
        session_id: session.id,
        role: "user",
        content: "Hello!",
        attachments: [%{"type" => "image"}]
      }

      changeset = Message.changeset(%Message{}, valid_attrs)
      assert changeset.valid?

      # Invalid: list with non-map elements
      # Ecto's {:array, :map} type validates during cast, so invalid elements
      # cause "is invalid" error from the cast, not our custom validation
      invalid_attrs = %{
        session_id: session.id,
        role: "user",
        content: "Hello!",
        attachments: ["not a map", %{"type" => "image"}]
      }

      invalid_changeset = Message.changeset(%Message{}, invalid_attrs)
      refute invalid_changeset.valid?
      assert "is invalid" in errors_on(invalid_changeset).attachments
    end
  end

  describe "database operations" do
    test "can insert a message" do
      user = create_user()
      session = create_session(user)

      attrs = %{
        session_id: session.id,
        role: "user",
        content: "Hello, HAL!"
      }

      {:ok, message} = %Message{} |> Message.changeset(attrs) |> Repo.insert()

      assert message.id
      assert message.session_id == session.id
      assert message.role == "user"
      assert message.content == "Hello, HAL!"
      assert message.attachments == []
      assert message.metadata == %{}
      assert message.inserted_at
    end

    test "messages do not have updated_at" do
      user = create_user()
      session = create_session(user)

      {:ok, message} =
        %Message{}
        |> Message.changeset(%{
          session_id: session.id,
          role: "user",
          content: "Test"
        })
        |> Repo.insert()

      # Message schema has updated_at: false in timestamps
      refute Map.has_key?(message, :updated_at)
    end

    test "enforces foreign key constraint on session_id" do
      fake_session_id = Ecto.UUID.generate()

      attrs = %{
        session_id: fake_session_id,
        role: "user",
        content: "Hello!"
      }

      {:error, changeset} = %Message{} |> Message.changeset(attrs) |> Repo.insert()

      assert "does not exist" in errors_on(changeset).session_id
    end

    test "cascades delete when session is deleted" do
      user = create_user()
      session = create_session(user)

      {:ok, message} =
        %Message{}
        |> Message.changeset(%{
          session_id: session.id,
          role: "user",
          content: "Test message"
        })
        |> Repo.insert()

      # Delete the session
      Repo.delete!(session)

      # Message should be deleted too
      assert Repo.get(Message, message.id) == nil
    end

    test "can preload session association" do
      user = create_user()
      session = create_session(user)

      {:ok, message} =
        %Message{}
        |> Message.changeset(%{
          session_id: session.id,
          role: "user",
          content: "Test message"
        })
        |> Repo.insert()

      message_with_session = Message |> Repo.get!(message.id) |> Repo.preload(:session)

      assert message_with_session.session.id == session.id
      assert message_with_session.session.channel_type == "telegram"
    end

    test "can query messages by session in chronological order" do
      user = create_user()
      session = create_session(user)

      # Insert messages with slight delays to ensure order
      {:ok, msg1} =
        %Message{}
        |> Message.changeset(%{session_id: session.id, role: "user", content: "First"})
        |> Repo.insert()

      # Small delay to ensure different timestamps
      Process.sleep(10)

      {:ok, msg2} =
        %Message{}
        |> Message.changeset(%{session_id: session.id, role: "assistant", content: "Second"})
        |> Repo.insert()

      Process.sleep(10)

      {:ok, msg3} =
        %Message{}
        |> Message.changeset(%{session_id: session.id, role: "user", content: "Third"})
        |> Repo.insert()

      messages =
        Message
        |> where(session_id: ^session.id)
        |> order_by(asc: :inserted_at)
        |> Repo.all()

      assert length(messages) == 3
      assert Enum.map(messages, & &1.id) == [msg1.id, msg2.id, msg3.id]
      assert Enum.map(messages, & &1.content) == ["First", "Second", "Third"]
    end

    test "preserves JSONB data in attachments" do
      user = create_user()
      session = create_session(user)

      attachments = [
        %{
          "type" => "image",
          "url" => "https://example.com/image.png",
          "size" => 12_345,
          "dimensions" => %{"width" => 800, "height" => 600}
        },
        %{
          "type" => "voice",
          "file_id" => "telegram_file_id_123",
          "duration" => 15
        }
      ]

      {:ok, message} =
        %Message{}
        |> Message.changeset(%{
          session_id: session.id,
          role: "user",
          content: "Here are my files",
          attachments: attachments
        })
        |> Repo.insert()

      reloaded = Repo.get!(Message, message.id)

      assert length(reloaded.attachments) == 2
      assert Enum.at(reloaded.attachments, 0)["type"] == "image"
      assert Enum.at(reloaded.attachments, 0)["dimensions"]["width"] == 800
      assert Enum.at(reloaded.attachments, 1)["type"] == "voice"
      assert Enum.at(reloaded.attachments, 1)["duration"] == 15
    end

    test "preserves JSONB data in metadata" do
      user = create_user()
      session = create_session(user)

      metadata = %{
        "model" => "claude-3-opus",
        "input_tokens" => 100,
        "output_tokens" => 250,
        "tool_calls" => [
          %{"tool" => "bash", "duration_ms" => 500},
          %{"tool" => "read", "duration_ms" => 50}
        ],
        "cost_usd" => 0.0125
      }

      {:ok, message} =
        %Message{}
        |> Message.changeset(%{
          session_id: session.id,
          role: "assistant",
          content: "Done!",
          metadata: metadata
        })
        |> Repo.insert()

      reloaded = Repo.get!(Message, message.id)

      assert reloaded.metadata["model"] == "claude-3-opus"
      assert reloaded.metadata["input_tokens"] == 100
      assert length(reloaded.metadata["tool_calls"]) == 2
      assert reloaded.metadata["cost_usd"] == 0.0125
    end
  end

  describe "valid_roles/0" do
    test "returns expected roles" do
      roles = Message.valid_roles()

      assert "user" in roles
      assert "assistant" in roles
      assert "system" in roles
      assert length(roles) == 3
    end
  end
end
