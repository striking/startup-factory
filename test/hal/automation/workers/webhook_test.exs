defmodule HAL.Automation.Workers.WebhookTest do
  use ExUnit.Case, async: true

  alias HAL.Automation.Workers.Webhook

  describe "new/2" do
    test "creates a job with correct defaults" do
      args = %{
        "source" => "github",
        "event_type" => "push",
        "payload" => %{}
      }

      changeset = Webhook.new(args)

      assert changeset.valid?
      # Queue can be atom or string
      assert changeset.changes.queue in [:webhooks, "webhooks"]
      assert changeset.changes.max_attempts == 5
      assert changeset.changes.priority == 0
    end
  end

  describe "perform/1 - GitHub webhooks" do
    test "handles pull_request.opened event" do
      job = %Oban.Job{
        args: %{
          "source" => "github",
          "event_type" => "pull_request.opened",
          "payload" => %{
            "repository" => %{"full_name" => "user/repo"},
            "pull_request" => %{
              "number" => 42,
              "title" => "Add new feature",
              "html_url" => "https://github.com/user/repo/pull/42"
            }
          }
        }
      }

      # Should complete without error
      assert :ok = Webhook.perform(job)
    end

    test "handles pull_request.merged event" do
      job = %Oban.Job{
        args: %{
          "source" => "github",
          "event_type" => "pull_request.merged",
          "payload" => %{
            "repository" => %{"full_name" => "user/repo"},
            "pull_request" => %{
              "number" => 42,
              "title" => "Add new feature"
            }
          }
        }
      }

      assert :ok = Webhook.perform(job)
    end

    test "handles issues.opened event" do
      job = %Oban.Job{
        args: %{
          "source" => "github",
          "event_type" => "issues.opened",
          "payload" => %{
            "repository" => %{"full_name" => "user/repo"},
            "issue" => %{
              "number" => 123,
              "title" => "Bug report",
              "body" => "Something is broken"
            }
          }
        }
      }

      assert :ok = Webhook.perform(job)
    end

    test "handles check_run.completed with failure" do
      job = %Oban.Job{
        args: %{
          "source" => "github",
          "event_type" => "check_run.completed",
          "payload" => %{
            "conclusion" => "failure",
            "repository" => %{"full_name" => "user/repo"},
            "check_run" => %{
              "name" => "CI",
              "html_url" => "https://github.com/user/repo/actions/runs/123"
            }
          }
        }
      }

      assert :ok = Webhook.perform(job)
    end

    test "handles push event" do
      job = %Oban.Job{
        args: %{
          "source" => "github",
          "event_type" => "push",
          "payload" => %{
            "repository" => %{"full_name" => "user/repo"},
            "ref" => "refs/heads/main",
            "commits" => [
              %{"message" => "Commit 1"},
              %{"message" => "Commit 2"}
            ]
          }
        }
      }

      assert :ok = Webhook.perform(job)
    end

    test "handles unknown GitHub event" do
      job = %Oban.Job{
        args: %{
          "source" => "github",
          "event_type" => "unknown_event",
          "payload" => %{}
        }
      }

      assert :ok = Webhook.perform(job)
    end
  end

  describe "perform/1 - Stripe webhooks" do
    test "handles payment_intent.succeeded event" do
      job = %Oban.Job{
        args: %{
          "source" => "stripe",
          "event_type" => "payment_intent.succeeded",
          "payload" => %{
            "data" => %{
              "object" => %{
                "amount" => 2500,
                "currency" => "usd"
              }
            }
          }
        }
      }

      assert :ok = Webhook.perform(job)
    end

    test "handles customer.subscription.created event" do
      job = %Oban.Job{
        args: %{
          "source" => "stripe",
          "event_type" => "customer.subscription.created",
          "payload" => %{}
        }
      }

      assert :ok = Webhook.perform(job)
    end

    test "handles customer.subscription.deleted event" do
      job = %Oban.Job{
        args: %{
          "source" => "stripe",
          "event_type" => "customer.subscription.deleted",
          "payload" => %{}
        }
      }

      assert :ok = Webhook.perform(job)
    end
  end

  describe "perform/1 - n8n webhooks" do
    test "handles n8n webhook with message" do
      job = %Oban.Job{
        args: %{
          "source" => "n8n",
          "event_type" => "workflow_trigger",
          "payload" => %{
            "message" => "Workflow completed successfully"
          }
        }
      }

      assert :ok = Webhook.perform(job)
    end

    # Tests with session_id require database access
    # Those are covered in integration tests
  end

  describe "perform/1 - custom webhooks" do
    test "handles custom webhook with message" do
      job = %Oban.Job{
        args: %{
          "source" => "custom",
          "event_type" => "custom_event",
          "payload" => %{
            "message" => "Custom notification"
          }
        }
      }

      assert :ok = Webhook.perform(job)
    end

    test "handles custom webhook without actionable content" do
      job = %Oban.Job{
        args: %{
          "source" => "custom",
          "event_type" => "custom_event",
          "payload" => %{}
        }
      }

      assert :ok = Webhook.perform(job)
    end
  end

  describe "perform/1 - unknown source" do
    test "handles unknown webhook source" do
      job = %Oban.Job{
        args: %{
          "source" => "unknown_source",
          "event_type" => "some_event",
          "payload" => %{}
        }
      }

      assert :ok = Webhook.perform(job)
    end
  end

  # Note: Job insertion tests require Oban to be started with a database
  # Those are covered in integration tests
end
