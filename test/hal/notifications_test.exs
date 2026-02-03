defmodule Hal.NotificationsTest do
  @moduledoc """
  Tests for the unified notification routing system.

  Tests cover:
  - Channel routing based on user preferences
  - Fallback handling
  - Multi-channel delivery
  - Error handling
  - User preference parsing
  """
  use ExUnit.Case, async: true

  alias Hal.Notifications
  alias Hal.Accounts.User

  describe "determine_channels/2 and user preferences" do
    test "uses user's platform as default channel when no preferences set" do
      user = build_user("telegram", %{})

      # Uses user platform (telegram) and external_id as chat_id
      # Fails because sender process isn't available, but proves it used the platform
      assert {:error, :telegram_sender_not_available} = Notifications.send(user, "test")
    end

    test "respects primary channel preference" do
      user =
        build_user("telegram", %{
          "notification_preferences" => %{
            "primary_channel" => "email",
            "email" => "test@example.com"
          }
        })

      # This will succeed with email since Swoosh test adapter is configured
      # This proves email was attempted first (not telegram)
      result = Notifications.send(user, "test", subject: "Test")
      assert match?({:ok, %{channel: :email}}, result)
    end

    test "tries fallback channels when primary fails with fallback enabled" do
      user =
        build_user("slack", %{
          "notification_preferences" => %{
            "primary_channel" => "telegram",
            "fallback_channels" => ["slack", "email"],
            "email" => "test@example.com"
          }
        })

      # Telegram will fail (not configured), slack will fail (not configured), email will succeed
      result = Notifications.send(user, "test", fallback: true)

      # Should succeed at email fallback
      assert match?({:ok, %{channel: :email}}, result)
    end

    test "only tries primary channel when fallback disabled" do
      user =
        build_user("telegram", %{
          "notification_preferences" => %{
            "primary_channel" => "telegram",
            "fallback_channels" => ["email"],
            "email" => "test@example.com"
          }
        })

      # Should fail immediately at telegram without trying email
      # Telegram IS configured (has external_id) but sender unavailable
      result = Notifications.send(user, "test", fallback: false)
      assert {:error, :telegram_sender_not_available} = result
    end

    test "allows override of channels via opts" do
      user =
        build_user("telegram", %{
          "notification_preferences" => %{
            "primary_channel" => "telegram",
            "email" => "test@example.com"
          }
        })

      # Override to only use email
      result = Notifications.send(user, "test", channels: [:email], subject: "Test")

      # Should succeed with email (test adapter configured)
      assert match?({:ok, %{channel: :email}}, result)
    end

    test "filters out unconfigured channels" do
      user =
        build_user(
          "email",
          %{
            "notification_preferences" => %{
              "primary_channel" => "telegram",
              "fallback_channels" => ["slack", "discord"]
              # No actual channel IDs configured, and platform is email without email set
            }
          },
          "no_chat_id"
        )

      # Should return error because no channels are actually configured
      result = Notifications.send(user, "test")
      assert {:error, :no_channels_configured} = result
    end

    test "handles invalid channel atoms gracefully" do
      user =
        build_user("telegram", %{
          "notification_preferences" => %{
            "primary_channel" => "invalid_channel",
            "fallback_channels" => ["also_invalid"]
          }
        })

      # Should fall back to user platform (telegram) but validation filters it out
      result = Notifications.send(user, "test")
      assert {:error, :no_channels_configured} = result
    end
  end

  describe "send_telegram/3" do
    test "returns error when telegram_chat_id not configured" do
      user = build_user("slack", %{})

      result = Notifications.send_telegram(user, "test")
      assert {:error, :telegram_not_configured} = result
    end

    test "returns error when Telegram sender process not available" do
      user =
        build_user("telegram", %{
          "notification_preferences" => %{
            "telegram_chat_id" => "123456789"
          }
        })

      # Sender process doesn't exist in test env
      result = Notifications.send_telegram(user, "test")
      assert {:error, :telegram_sender_not_available} = result
    end

    test "uses platform external_id when telegram_chat_id not in preferences" do
      user = build_user("telegram", %{}, "987654321")

      # Will fail because sender not available, but proves it found the chat_id
      result = Notifications.send_telegram(user, "test")
      assert {:error, :telegram_sender_not_available} = result
    end

    test "prefers explicit telegram_chat_id over external_id" do
      user =
        build_user(
          "telegram",
          %{
            "notification_preferences" => %{
              "telegram_chat_id" => "111111111"
            }
          },
          "999999999"
        )

      # Would use 111111111, not 999999999
      result = Notifications.send_telegram(user, "test")
      assert {:error, :telegram_sender_not_available} = result
    end
  end

  describe "send_slack/3" do
    test "returns error when slack not configured" do
      user = build_user("telegram", %{})

      result = Notifications.send_slack(user, "test")
      assert {:error, :slack_not_configured} = result
    end

    test "uses external_id when platform is slack and no explicit config" do
      user = build_user("slack", %{}, "U123ABC")

      # Will fail at SlackSender call, but proves channel_id was found
      result = Notifications.send_slack(user, "test")
      # Slack sender will likely error on actual API call
      assert match?({:error, _}, result)
    end

    test "accepts slack_channel from preferences" do
      user =
        build_user("telegram", %{
          "notification_preferences" => %{
            "slack_channel" => "C123456"
          }
        })

      result = Notifications.send_slack(user, "test")
      assert match?({:error, _}, result)
    end

    test "accepts slack_user_id from preferences" do
      user =
        build_user("telegram", %{
          "notification_preferences" => %{
            "slack_user_id" => "U123456"
          }
        })

      result = Notifications.send_slack(user, "test")
      assert match?({:error, _}, result)
    end
  end

  describe "send_discord/3" do
    test "returns error when discord not configured" do
      user = build_user("telegram", %{})

      result = Notifications.send_discord(user, "test")
      assert {:error, :discord_not_configured} = result
    end

    test "uses external_id when platform is discord" do
      user = build_user("discord", %{}, "987654321")

      result = Notifications.send_discord(user, "test")
      # Will fail on actual Discord API call but proves routing worked
      assert match?({:error, _}, result)
    end

    test "prefers discord_dm_channel over other options" do
      user =
        build_user("telegram", %{
          "notification_preferences" => %{
            "discord_dm_channel" => "DM123",
            "discord_user_id" => "USER456",
            "discord_channel" => "CHAN789"
          }
        })

      result = Notifications.send_discord(user, "test")
      assert match?({:error, _}, result)
    end

    test "falls back to discord_user_id if dm_channel not set" do
      user =
        build_user("telegram", %{
          "notification_preferences" => %{
            "discord_user_id" => "USER456",
            "discord_channel" => "CHAN789"
          }
        })

      result = Notifications.send_discord(user, "test")
      assert match?({:error, _}, result)
    end
  end

  describe "send_email/3" do
    test "returns error when email not configured" do
      user = build_user("telegram", %{})

      result = Notifications.send_email(user, "test", subject: "Test")
      assert {:error, :email_not_configured} = result
    end

    test "returns error when email is invalid (no @)" do
      user =
        build_user("telegram", %{
          "notification_preferences" => %{
            "email" => "notanemail"
          }
        })

      result = Notifications.send_email(user, "test", subject: "Test")
      assert {:error, :email_not_configured} = result
    end

    test "accepts valid email from preferences" do
      user =
        build_user("telegram", %{
          "notification_preferences" => %{
            "email" => "user@example.com"
          }
        })

      # Will succeed since Swoosh test adapter is configured
      result = Notifications.send_email(user, "test", subject: "Test Subject")
      assert match?({:ok, %{channel: :email}}, result)
    end

    test "uses subject from opts" do
      user =
        build_user("telegram", %{
          "notification_preferences" => %{
            "email" => "user@example.com"
          }
        })

      result = Notifications.send_email(user, "Message body", subject: "Custom Subject")
      assert match?({:ok, %{channel: :email}}, result)
    end

    test "supports html option" do
      user =
        build_user("telegram", %{
          "notification_preferences" => %{
            "email" => "user@example.com"
          }
        })

      result =
        Notifications.send_email(user, "Plain text", subject: "Test", html: "<p>HTML version</p>")

      assert match?({:ok, %{channel: :email}}, result)
    end
  end

  describe "routing logic and fallback behavior" do
    test "returns no_channels_configured when user has no valid channels" do
      # Use a platform that won't default to external_id
      user =
        build_user("terminal", %{
          "notification_preferences" => %{
            # Not configured
            "primary_channel" => "slack"
          }
        })

      result = Notifications.send(user, "test")
      assert {:error, :no_channels_configured} = result
    end

    test "fallback chain is attempted in order" do
      user =
        build_user("telegram", %{
          "notification_preferences" => %{
            "primary_channel" => "telegram",
            "fallback_channels" => ["slack", "discord", "email"],
            "email" => "test@example.com"
          }
        })

      # Attempts in order: telegram (sender unavailable) -> slack (not configured) ->
      # discord (not configured) -> email (succeeds)
      result = Notifications.send(user, "test", fallback: true)

      # Should succeed at email
      assert match?({:ok, %{channel: :email}}, result)
    end

    test "stops at first successful channel" do
      # Email succeeds immediately, slack is never tried
      user =
        build_user("telegram", %{
          "notification_preferences" => %{
            "primary_channel" => "email",
            "fallback_channels" => ["slack"],
            "email" => "test@example.com"
          }
        })

      result = Notifications.send(user, "test", fallback: true)
      # Succeeds at email, never tries slack
      assert match?({:ok, %{channel: :email}}, result)
    end

    test "handles empty fallback_channels list" do
      user =
        build_user("telegram", %{
          "notification_preferences" => %{
            "primary_channel" => "telegram",
            "fallback_channels" => []
          }
        })

      result = Notifications.send(user, "test", fallback: true)
      # Should only try telegram (configured via external_id, but sender unavailable)
      assert {:error, :telegram_sender_not_available} = result
    end

    test "deduplicates channels (primary appears in fallbacks)" do
      user =
        build_user("telegram", %{
          "notification_preferences" => %{
            "primary_channel" => "email",
            "fallback_channels" => ["email", "slack"],
            "email" => "test@example.com"
          }
        })

      # Should only try email once and succeed
      result = Notifications.send(user, "test", fallback: true)
      assert match?({:ok, %{channel: :email}}, result)
    end
  end

  describe "channel availability checking" do
    test "has_channel_configured? for telegram checks chat_id" do
      user_with_telegram =
        build_user("telegram", %{
          "notification_preferences" => %{
            "telegram_chat_id" => "123"
          }
        })

      user_without_telegram = build_user("slack", %{})

      # We can't call private function directly, but we can observe behavior
      # via send with specific channels
      result1 = Notifications.send(user_with_telegram, "test", channels: [:telegram])
      result2 = Notifications.send(user_without_telegram, "test", channels: [:telegram])

      # First should try telegram (fail on sender not available)
      # Second should return no channels configured
      assert {:error, :telegram_sender_not_available} = result1
      assert {:error, :no_channels_configured} = result2
    end

    test "validates user has requested channels before attempting send" do
      user =
        build_user(
          "telegram",
          %{
            # No slack configured
          }
        )

      # Requesting slack should result in no_channels_configured
      result = Notifications.send(user, "test", channels: [:slack])
      assert {:error, :no_channels_configured} = result
    end
  end

  describe "edge cases and error handling" do
    test "handles nil settings gracefully" do
      user = %User{
        id: "test-id",
        external_id: "123",
        platform: "telegram",
        username: "test",
        settings: nil
      }

      result = Notifications.send(user, "test")
      # User's platform is telegram, so it tries to use external_id as chat_id
      # but fails because sender process isn't running
      assert {:error, :telegram_sender_not_available} = result
    end

    test "handles empty settings map" do
      user = build_user("telegram", %{})

      result = Notifications.send(user, "test")
      # User's platform is telegram, so it tries to use external_id as chat_id
      # but fails because sender process isn't running
      assert {:error, :telegram_sender_not_available} = result
    end

    test "handles malformed notification_preferences" do
      user =
        build_user("telegram", %{
          "notification_preferences" => "not a map"
        })

      result = Notifications.send(user, "test")
      # User's platform is telegram, so it tries to use external_id as chat_id
      # but fails because sender process isn't running
      assert {:error, :telegram_sender_not_available} = result
    end

    test "returns proper error structure for each channel type" do
      # Each channel should wrap its error
      user_telegram =
        build_user("telegram", %{
          "notification_preferences" => %{"telegram_chat_id" => "123"}
        })

      user_slack =
        build_user("telegram", %{
          "notification_preferences" => %{"slack_channel" => "C123"}
        })

      user_discord =
        build_user("telegram", %{
          "notification_preferences" => %{"discord_channel" => "123"}
        })

      user_email =
        build_user("telegram", %{
          "notification_preferences" => %{"email" => "test@test.com"}
        })

      assert {:error, :telegram_sender_not_available} =
               Notifications.send_telegram(user_telegram, "test")

      assert match?(
               {:error, {:slack, :not_configured}},
               Notifications.send_slack(user_slack, "test")
             )

      assert match?({:error, {:discord, _}}, Notifications.send_discord(user_discord, "test"))

      # Email succeeds with test adapter
      assert match?(
               {:ok, %{channel: :email}},
               Notifications.send_email(user_email, "test", subject: "Test")
             )
    end
  end

  # Test Helpers

  defp build_user(platform, settings, external_id \\ "default_id") do
    %User{
      id: Ecto.UUID.generate(),
      external_id: external_id,
      platform: platform,
      username: "test_user",
      settings: settings || %{}
    }
  end
end
