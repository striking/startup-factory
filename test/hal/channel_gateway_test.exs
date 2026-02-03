defmodule Hal.ChannelGatewayTest do
  use Hal.DataCase, async: true

  alias Hal.ChannelGateway
  alias Hal.Accounts.User
  alias Hal.Repo

  import Ecto.Query

  describe "normalize_message/2 - telegram" do
    test "normalizes a basic telegram text message" do
      telegram_msg = %{
        from: %{id: 123_456, username: "testuser", first_name: "Test", last_name: "User"},
        chat: %{id: 789_012, type: "private"},
        text: "Hello HAL",
        date: 1_609_459_200,
        message_id: 1
      }

      assert {:ok, normalized} = ChannelGateway.normalize_message(:telegram, telegram_msg)

      assert normalized.text == "Hello HAL"
      assert normalized.channel_type == :telegram
      assert normalized.channel_id == "789012"
      assert normalized.is_dm == true
      assert normalized.timestamp == DateTime.from_unix!(1_609_459_200)
      assert is_binary(normalized.user_id)
      assert normalized.metadata.message_id == 1
      assert normalized.metadata.telegram_user_id == 123_456
      assert normalized.attachments == []
    end

    test "normalizes telegram group message" do
      telegram_msg = %{
        from: %{id: 123_456, username: "testuser", first_name: "Test"},
        chat: %{id: 789_012, type: "group"},
        text: "@hal help me",
        date: 1_609_459_200,
        message_id: 2,
        mentions_bot: true
      }

      assert {:ok, normalized} = ChannelGateway.normalize_message(:telegram, telegram_msg)

      assert normalized.is_dm == false
      assert normalized.mentions_bot == true
      assert normalized.metadata.chat_type == "group"
    end

    test "extracts telegram photo attachments" do
      telegram_msg = %{
        from: %{id: 123_456, username: "testuser", first_name: "Test"},
        chat: %{id: 789_012, type: "private"},
        caption: "Check this out",
        date: 1_609_459_200,
        message_id: 3,
        photo: [
          %{file_id: "small", file_size: 1000},
          %{file_id: "large", file_size: 5000}
        ]
      }

      assert {:ok, normalized} = ChannelGateway.normalize_message(:telegram, telegram_msg)

      assert normalized.text == "Check this out"
      assert length(normalized.attachments) == 1
      assert hd(normalized.attachments).type == "photo"
      assert hd(normalized.attachments).file_id == "large"
    end

    test "extracts telegram document attachments" do
      telegram_msg = %{
        from: %{id: 123_456, username: "testuser", first_name: "Test"},
        chat: %{id: 789_012, type: "private"},
        text: "",
        date: 1_609_459_200,
        message_id: 4,
        document: %{
          file_id: "doc123",
          file_name: "report.pdf",
          mime_type: "application/pdf",
          file_size: 50_000
        }
      }

      assert {:ok, normalized} = ChannelGateway.normalize_message(:telegram, telegram_msg)

      assert length(normalized.attachments) == 1
      attachment = hd(normalized.attachments)
      assert attachment.type == "document"
      assert attachment.file_name == "report.pdf"
      assert attachment.mime_type == "application/pdf"
    end

    test "extracts telegram voice attachments" do
      telegram_msg = %{
        from: %{id: 123_456, username: "testuser", first_name: "Test"},
        chat: %{id: 789_012, type: "private"},
        text: "",
        date: 1_609_459_200,
        message_id: 5,
        voice: %{
          file_id: "voice123",
          duration: 30,
          mime_type: "audio/ogg"
        }
      }

      assert {:ok, normalized} = ChannelGateway.normalize_message(:telegram, telegram_msg)

      assert length(normalized.attachments) == 1
      attachment = hd(normalized.attachments)
      assert attachment.type == "voice"
      assert attachment.duration == 30
    end

    test "creates user on first telegram message" do
      telegram_msg = %{
        from: %{id: 999_999, username: "newuser", first_name: "New", last_name: "User"},
        chat: %{id: 789_012, type: "private"},
        text: "First message",
        date: 1_609_459_200,
        message_id: 6
      }

      # Verify no user exists
      refute Repo.one(
               from u in User, where: u.external_id == "999999" and u.platform == "telegram"
             )

      assert {:ok, normalized} = ChannelGateway.normalize_message(:telegram, telegram_msg)

      # Verify user was created
      user =
        Repo.one(from u in User, where: u.external_id == "999999" and u.platform == "telegram")

      assert user
      assert user.username == "newuser"
      assert user.settings["first_name"] == "New"
      assert user.settings["last_name"] == "User"
      assert normalized.user_id == user.id
    end

    test "reuses existing telegram user" do
      # Create user first
      {:ok, existing_user} =
        %User{}
        |> User.changeset(%{
          external_id: "888888",
          platform: "telegram",
          username: "existing"
        })
        |> Repo.insert()

      telegram_msg = %{
        from: %{id: 888_888, username: "existing", first_name: "Existing"},
        chat: %{id: 789_012, type: "private"},
        text: "Another message",
        date: 1_609_459_200,
        message_id: 7
      }

      assert {:ok, normalized} = ChannelGateway.normalize_message(:telegram, telegram_msg)

      # Should use existing user
      assert normalized.user_id == existing_user.id

      # Verify only one user exists
      count = Repo.aggregate(from(u in User, where: u.external_id == "888888"), :count)
      assert count == 1
    end
  end

  describe "normalize_message/2 - slack" do
    test "normalizes a basic slack message" do
      slack_msg = %{
        "user" => "U123456",
        "channel" => "C789012",
        "text" => "Hello HAL",
        "ts" => "1609459200.123456"
      }

      assert {:ok, normalized} = ChannelGateway.normalize_message(:slack, slack_msg)

      assert normalized.text == "Hello HAL"
      assert normalized.channel_type == :slack
      assert normalized.channel_id == "C789012"
      assert normalized.is_dm == false
      assert normalized.timestamp == DateTime.from_unix!(1_609_459_200)
      assert is_binary(normalized.user_id)
      assert normalized.metadata.ts == "1609459200.123456"
    end

    test "identifies slack DMs" do
      slack_msg = %{
        "user" => "U123456",
        "channel" => "D789012",
        "text" => "Private message",
        "ts" => "1609459200.123456"
      }

      assert {:ok, normalized} = ChannelGateway.normalize_message(:slack, slack_msg)

      assert normalized.is_dm == true
    end

    test "handles slack threads" do
      slack_msg = %{
        "user" => "U123456",
        "channel" => "C789012",
        "text" => "Reply in thread",
        "ts" => "1609459200.123456",
        "thread_ts" => "1609459100.000000"
      }

      assert {:ok, normalized} = ChannelGateway.normalize_message(:slack, slack_msg)

      assert normalized.metadata.thread_ts == "1609459100.000000"
    end

    test "extracts slack file attachments" do
      slack_msg = %{
        "user" => "U123456",
        "channel" => "C789012",
        "text" => "Check this file",
        "ts" => "1609459200.123456",
        "files" => [
          %{
            "id" => "F123",
            "name" => "report.pdf",
            "title" => "Report",
            "mimetype" => "application/pdf",
            "filetype" => "pdf",
            "url_private" => "https://files.slack.com/...",
            "size" => 50_000
          }
        ]
      }

      assert {:ok, normalized} = ChannelGateway.normalize_message(:slack, slack_msg)

      assert length(normalized.attachments) == 1
      attachment = hd(normalized.attachments)
      assert attachment.type == "file"
      assert attachment.name == "report.pdf"
    end

    test "creates user on first slack message" do
      slack_msg = %{
        "user" => "U999999",
        "channel" => "C789012",
        "text" => "First message",
        "ts" => "1609459200.123456"
      }

      # Verify no user exists
      refute Repo.one(from u in User, where: u.external_id == "U999999" and u.platform == "slack")

      assert {:ok, normalized} = ChannelGateway.normalize_message(:slack, slack_msg)

      # Verify user was created
      user = Repo.one(from u in User, where: u.external_id == "U999999" and u.platform == "slack")
      assert user
      assert normalized.user_id == user.id
    end
  end

  describe "normalize_message/2 - discord" do
    test "normalizes a basic discord message" do
      discord_msg = %{
        author: %{id: 123_456, username: "testuser"},
        channel_id: 789_012,
        content: "Hello HAL",
        id: "msg123",
        timestamp: ~U[2021-01-01 00:00:00Z],
        guild_id: "guild123"
      }

      assert {:ok, normalized} = ChannelGateway.normalize_message(:discord, discord_msg)

      assert normalized.text == "Hello HAL"
      assert normalized.channel_type == :discord
      assert normalized.channel_id == "789012"
      assert normalized.is_dm == false
      assert normalized.timestamp == ~U[2021-01-01 00:00:00Z]
      assert is_binary(normalized.user_id)
      assert normalized.metadata.message_id == "msg123"
      assert normalized.metadata.guild_id == "guild123"
    end

    test "identifies discord DMs" do
      discord_msg = %{
        author: %{id: 123_456, username: "testuser"},
        channel_id: 789_012,
        content: "DM message",
        id: "msg124",
        timestamp: ~U[2021-01-01 00:00:00Z],
        guild_id: nil
      }

      assert {:ok, normalized} = ChannelGateway.normalize_message(:discord, discord_msg)

      assert normalized.is_dm == true
    end

    test "extracts discord attachments" do
      discord_msg = %{
        author: %{id: 123_456, username: "testuser"},
        channel_id: 789_012,
        content: "Image",
        id: "msg125",
        timestamp: ~U[2021-01-01 00:00:00Z],
        guild_id: "guild123",
        attachments: [
          %{
            id: "att123",
            filename: "screenshot.png",
            url: "https://cdn.discordapp.com/...",
            size: 10_000,
            content_type: "image/png"
          }
        ]
      }

      assert {:ok, normalized} = ChannelGateway.normalize_message(:discord, discord_msg)

      assert length(normalized.attachments) == 1
      attachment = hd(normalized.attachments)
      assert attachment.type == "attachment"
      assert attachment.filename == "screenshot.png"
    end

    test "creates user on first discord message" do
      discord_msg = %{
        author: %{id: 999_999, username: "newuser"},
        channel_id: 789_012,
        content: "First message",
        id: "msg126",
        timestamp: ~U[2021-01-01 00:00:00Z],
        guild_id: "guild123"
      }

      # Verify no user exists
      refute Repo.one(
               from u in User, where: u.external_id == "999999" and u.platform == "discord"
             )

      assert {:ok, normalized} = ChannelGateway.normalize_message(:discord, discord_msg)

      # Verify user was created
      user =
        Repo.one(from u in User, where: u.external_id == "999999" and u.platform == "discord")

      assert user
      assert normalized.user_id == user.id
    end
  end

  describe "normalize_message/2 - email" do
    test "normalizes a basic email message" do
      email_msg = %{
        from_email: "user@example.com",
        subject: "Question about HAL",
        body: "How do I use HAL?",
        message_id: "email123",
        timestamp: ~U[2021-01-01 00:00:00Z],
        attachments: []
      }

      assert {:ok, normalized} = ChannelGateway.normalize_message(:email, email_msg)

      assert normalized.text == "How do I use HAL?"
      assert normalized.channel_type == :email
      assert normalized.channel_id == "user@example.com"
      assert normalized.is_dm == true
      assert normalized.mentions_bot == true
      assert normalized.metadata.subject == "Question about HAL"
    end

    test "creates user on first email" do
      email_msg = %{
        from_email: "newuser@example.com",
        subject: "Hello",
        body: "First email",
        message_id: "email124"
      }

      # Verify no user exists
      refute Repo.one(
               from u in User,
                 where: u.external_id == "newuser@example.com" and u.platform == "email"
             )

      assert {:ok, normalized} = ChannelGateway.normalize_message(:email, email_msg)

      # Verify user was created
      user =
        Repo.one(
          from u in User,
            where: u.external_id == "newuser@example.com" and u.platform == "email"
        )

      assert user
      assert normalized.user_id == user.id
    end
  end

  describe "normalize_message/2 - terminal" do
    test "normalizes a basic terminal message" do
      terminal_msg = %{
        user_id: "terminal_user",
        text: "help",
        session_id: "term_session_1"
      }

      assert {:ok, normalized} = ChannelGateway.normalize_message(:terminal, terminal_msg)

      assert normalized.text == "help"
      assert normalized.channel_type == :terminal
      assert normalized.channel_id == "term_session_1"
      assert normalized.is_dm == true
      assert normalized.mentions_bot == true
    end

    test "handles terminal input field" do
      terminal_msg = %{
        input: "status",
        session_id: "term_session_2"
      }

      assert {:ok, normalized} = ChannelGateway.normalize_message(:terminal, terminal_msg)

      assert normalized.text == "status"
    end
  end

  describe "normalize_message/2 - unsupported channel" do
    test "returns error for unsupported channel type" do
      assert {:error, :unsupported_channel} =
               ChannelGateway.normalize_message(:whatsapp, %{})
    end
  end

  describe "route_message/3" do
    setup do
      # This test requires a running Router
      # For now, we'll skip integration tests
      # In a real scenario, you'd start the full Gateway supervision tree
      :ok
    end

    @tag :skip
    test "routes telegram message through Router" do
      # TODO: Implement integration test with Router mock
      assert true
    end

    @tag :skip
    test "routes slack message through Router" do
      # TODO: Implement integration test with Router mock
      assert true
    end
  end

  describe "user creation edge cases" do
    test "handles user with only first name" do
      telegram_msg = %{
        from: %{id: 111_111, first_name: "John"},
        chat: %{id: 789_012, type: "private"},
        text: "Hello",
        date: 1_609_459_200,
        message_id: 100
      }

      assert {:ok, normalized} = ChannelGateway.normalize_message(:telegram, telegram_msg)

      user = Repo.get!(User, normalized.user_id)
      assert user.settings["first_name"] == "John"
    end

    test "handles user with first and last name" do
      telegram_msg = %{
        from: %{id: 222_222, first_name: "John", last_name: "Doe"},
        chat: %{id: 789_012, type: "private"},
        text: "Hello",
        date: 1_609_459_200,
        message_id: 101
      }

      assert {:ok, normalized} = ChannelGateway.normalize_message(:telegram, telegram_msg)

      user = Repo.get!(User, normalized.user_id)
      assert user.username == "John Doe"
      assert user.settings["first_name"] == "John"
      assert user.settings["last_name"] == "Doe"
    end

    test "handles integer external_id conversion" do
      telegram_msg = %{
        from: %{id: 333_333, username: "testuser", first_name: "Test"},
        chat: %{id: 789_012, type: "private"},
        text: "Hello",
        date: 1_609_459_200,
        message_id: 102
      }

      assert {:ok, normalized} = ChannelGateway.normalize_message(:telegram, telegram_msg)

      user = Repo.get!(User, normalized.user_id)
      assert user.external_id == "333333"
    end
  end
end
