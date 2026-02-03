defmodule Hal.Tools.Definitions do
  @moduledoc """
  Anthropic tool definitions for HAL's capabilities.

  Provides tool schemas in the format expected by Claude Code's
  --append-system-prompt parameter with tool definitions.

  ## Tool Schema Format

  Each tool follows the Anthropic tool definition format:

      %{
        name: "tool_name",
        description: "What the tool does",
        input_schema: %{
          type: "object",
          properties: %{
            param_name: %{
              type: "string",
              description: "Parameter description"
            }
          },
          required: ["param_name"]
        }
      }

  ## Available Tools

  - Memory: hal_memory_search, hal_memory_store, hal_memory_forget
  - Calendar: hal_calendar_get_events, hal_calendar_create_event
  - Email: hal_email_get_unread, hal_email_send
  - Tasks: hal_tasks_list, hal_tasks_create, hal_tasks_complete
  - Notifications: hal_send_notification
  - Browser: hal_browser_navigate, hal_browser_snapshot, hal_browser_click,
             hal_browser_fill, hal_browser_screenshot, hal_browser_evaluate
  """

  @doc """
  Returns all HAL tool definitions for Claude Code.

  Returns a list of tool definition maps in Anthropic format.
  """
  @spec all() :: list(map())
  def all do
    memory_tools() ++
      calendar_tools() ++
      email_tools() ++
      task_tools() ++
      notification_tools() ++
      delegation_tools() ++
      skills_tools() ++
      codops_tools() ++
      mcp_tools() ++
      browser_tools() ++
      self_modification_tools()
  end

  @doc """
  Returns tool definitions as JSON string for --append-system-prompt.

  Formats tools as a system prompt addition that Claude can use.
  """
  @spec as_system_prompt() :: String.t()
  def as_system_prompt do
    """
    You have access to the following HAL tools to assist the user:

    #{Jason.encode!(all(), pretty: true)}

    Use these tools when appropriate to help the user manage their calendar,
    email, tasks, and memories. Always ask for confirmation before taking
    actions that modify data (sending emails, creating events, etc.).
    """
  end

  # Memory Tools

  defp memory_tools do
    [
      %{
        name: "hal_memory_search",
        description:
          "Search user's long-term semantic memory for relevant information about preferences, facts, decisions, or knowledge",
        input_schema: %{
          type: "object",
          properties: %{
            query: %{
              type: "string",
              description: "The search query (semantic search will find similar concepts)"
            },
            type: %{
              type: "string",
              description:
                "Optional filter by memory type: 'preference', 'fact', 'decision', or 'knowledge'",
              enum: ["preference", "fact", "decision", "knowledge"]
            },
            limit: %{
              type: "integer",
              description: "Maximum number of results to return (default: 5)",
              minimum: 1,
              maximum: 20
            }
          },
          required: ["query"]
        }
      },
      %{
        name: "hal_memory_store",
        description: "Store important information in user's long-term memory for future recall",
        input_schema: %{
          type: "object",
          properties: %{
            content: %{
              type: "string",
              description: "The information to remember"
            },
            type: %{
              type: "string",
              description: "Type of memory: 'preference', 'fact', 'decision', or 'knowledge'",
              enum: ["preference", "fact", "decision", "knowledge"]
            },
            metadata: %{
              type: "object",
              description: "Optional additional context (tags, source, etc.)",
              additionalProperties: true
            }
          },
          required: ["content", "type"]
        }
      },
      %{
        name: "hal_memory_forget",
        description: "Delete a specific memory from the user's long-term storage",
        input_schema: %{
          type: "object",
          properties: %{
            memory_id: %{
              type: "string",
              description: "The UUID of the memory to delete"
            }
          },
          required: ["memory_id"]
        }
      }
    ]
  end

  # Calendar Tools

  defp calendar_tools do
    [
      %{
        name: "hal_calendar_get_events",
        description: "Get upcoming calendar events for the user",
        input_schema: %{
          type: "object",
          properties: %{
            start_date: %{
              type: "string",
              description:
                "Start date in ISO 8601 format (e.g., '2024-01-29'). Defaults to today.",
              format: "date"
            },
            end_date: %{
              type: "string",
              description: "End date in ISO 8601 format. Defaults to 7 days from start_date.",
              format: "date"
            },
            limit: %{
              type: "integer",
              description: "Maximum number of events to return (default: 10)",
              minimum: 1,
              maximum: 50
            }
          },
          required: []
        }
      },
      %{
        name: "hal_calendar_create_event",
        description: "Create a new calendar event",
        input_schema: %{
          type: "object",
          properties: %{
            title: %{
              type: "string",
              description: "Event title"
            },
            start_time: %{
              type: "string",
              description: "Start time in ISO 8601 format (e.g., '2024-01-29T14:00:00Z')",
              format: "date-time"
            },
            end_time: %{
              type: "string",
              description: "End time in ISO 8601 format",
              format: "date-time"
            },
            description: %{
              type: "string",
              description: "Optional event description"
            },
            location: %{
              type: "string",
              description: "Optional event location"
            }
          },
          required: ["title", "start_time", "end_time"]
        }
      }
    ]
  end

  # Email Tools

  defp email_tools do
    [
      %{
        name: "hal_email_get_unread",
        description: "Get unread emails from the user's inbox",
        input_schema: %{
          type: "object",
          properties: %{
            limit: %{
              type: "integer",
              description: "Maximum number of emails to return (default: 10)",
              minimum: 1,
              maximum: 50
            },
            from: %{
              type: "string",
              description: "Optional filter by sender email address"
            },
            subject_contains: %{
              type: "string",
              description: "Optional filter by text in subject line"
            }
          },
          required: []
        }
      },
      %{
        name: "hal_email_send",
        description: "Send an email on behalf of the user",
        input_schema: %{
          type: "object",
          properties: %{
            to: %{
              type: "array",
              description: "Recipient email addresses",
              items: %{type: "string", format: "email"},
              minItems: 1
            },
            subject: %{
              type: "string",
              description: "Email subject line"
            },
            body: %{
              type: "string",
              description: "Email body (can include HTML)"
            },
            cc: %{
              type: "array",
              description: "Optional CC recipients",
              items: %{type: "string", format: "email"}
            },
            bcc: %{
              type: "array",
              description: "Optional BCC recipients",
              items: %{type: "string", format: "email"}
            }
          },
          required: ["to", "subject", "body"]
        }
      }
    ]
  end

  # Task/Todo Tools

  defp task_tools do
    [
      %{
        name: "hal_tasks_list",
        description: "Get the user's task list",
        input_schema: %{
          type: "object",
          properties: %{
            status: %{
              type: "string",
              description: "Filter by status: 'pending', 'in_progress', 'completed', or 'all'",
              enum: ["pending", "in_progress", "completed", "all"]
            },
            limit: %{
              type: "integer",
              description: "Maximum number of tasks to return (default: 20)",
              minimum: 1,
              maximum: 100
            },
            project: %{
              type: "string",
              description: "Optional filter by project name"
            }
          },
          required: []
        }
      },
      %{
        name: "hal_tasks_create",
        description: "Create a new task/todo item",
        input_schema: %{
          type: "object",
          properties: %{
            title: %{
              type: "string",
              description: "Task title"
            },
            description: %{
              type: "string",
              description: "Optional detailed description"
            },
            due_date: %{
              type: "string",
              description: "Optional due date in ISO 8601 format",
              format: "date"
            },
            priority: %{
              type: "string",
              description: "Task priority level",
              enum: ["low", "medium", "high", "urgent"]
            },
            project: %{
              type: "string",
              description: "Optional project name"
            }
          },
          required: ["title"]
        }
      },
      %{
        name: "hal_tasks_complete",
        description: "Mark a task as completed",
        input_schema: %{
          type: "object",
          properties: %{
            task_id: %{
              type: "string",
              description: "The UUID of the task to complete"
            }
          },
          required: ["task_id"]
        }
      }
    ]
  end

  # Notification Tools

  defp notification_tools do
    [
      %{
        name: "hal_send_notification",
        description:
          "Send a notification to the user via their preferred channel (Telegram, SMS, etc.)",
        input_schema: %{
          type: "object",
          properties: %{
            message: %{
              type: "string",
              description: "The notification message"
            },
            channel: %{
              type: "string",
              description:
                "Notification channel: 'telegram', 'sms', 'email', or 'auto' (use user's preferred channel)",
              enum: ["telegram", "sms", "email", "auto"]
            },
            priority: %{
              type: "string",
              description: "Notification priority: 'low', 'normal', 'high', or 'urgent'",
              enum: ["low", "normal", "high", "urgent"]
            },
            silent: %{
              type: "boolean",
              description: "If true, send without sound/vibration (default: false)"
            }
          },
          required: ["message"]
        }
      }
    ]
  end

  # Delegation Tools (for multi-agent orchestration)

  defp delegation_tools do
    [
      %{
        name: "hal_delegate_to_codex",
        description:
          "Delegate a complex coding task to OpenAI Codex. Use for multi-file refactoring, building features, or tasks requiring extended agentic coding sessions.",
        input_schema: %{
          type: "object",
          properties: %{
            task: %{
              type: "string",
              description: "Description of the coding task to delegate"
            },
            project_path: %{
              type: "string",
              description: "Path to the project directory (optional, defaults to current)"
            },
            approval_token: %{
              type: "string",
              description:
                "Optional. If omitted, HAL will create an approval request and return an approval_token. Approve it in the HAL UI at /approvals, then retry with approval_token."
            }
          },
          required: ["task"]
        }
      },
      %{
        name: "hal_delegate_to_jules",
        description:
          "Delegate a long-running background task to Jules. Use for async operations that don't need immediate feedback like batch processing, large refactors, or automated workflows.",
        input_schema: %{
          type: "object",
          properties: %{
            task: %{
              type: "string",
              description: "Description of the background task to delegate"
            },
            repo: %{
              type: "string",
              description: "GitHub repository in owner/repo format (optional)"
            },
            priority: %{
              type: "string",
              description: "Task priority: low, normal, or high",
              enum: ["low", "normal", "high"]
            },
            approval_token: %{
              type: "string",
              description:
                "Optional. If omitted, HAL will create an approval request and return an approval_token. Approve it in the HAL UI at /approvals, then retry with approval_token."
            }
          },
          required: ["task"]
        }
      },
      %{
        name: "hal_delegate_to_gemini",
        description:
          "Delegate a summarization or text completion task to Gemini. Use for fast, cost-effective tasks like summarizing documents, completing text, or quick analysis.",
        input_schema: %{
          type: "object",
          properties: %{
            text: %{
              type: "string",
              description: "The text to process (summarize or complete)"
            },
            operation: %{
              type: "string",
              description: "Operation type: summarize, complete, or delegate",
              enum: ["summarize", "complete", "delegate"]
            },
            max_length: %{
              type: "integer",
              description: "For summarize: target summary length in words (default: 200)"
            },
            style: %{
              type: "string",
              description: "For summarize: output style",
              enum: ["paragraph", "bullets", "key_points"]
            }
          },
          required: ["text", "operation"]
        }
      },
      %{
        name: "hal_check_delegation_status",
        description:
          "Check the status of a delegated task (Codex session, Jules task, or Gemini task)",
        input_schema: %{
          type: "object",
          properties: %{
            task_id: %{
              type: "string",
              description: "The task/session ID returned when the delegation was started"
            },
            agent: %{
              type: "string",
              description: "Which agent the task was delegated to",
              enum: ["codex", "jules", "gemini"]
            }
          },
          required: ["task_id", "agent"]
        }
      }
    ]
  end

  # Skills Tools (skills-first execution boundary)

  defp skills_tools do
    [
      %{
        name: "hal_skill_run",
        description:
          "Run an allowlisted skill from .claude/skills via a single generic execution boundary (skills-first).",
        input_schema: %{
          type: "object",
          properties: %{
            skill: %{
              type: "string",
              description: "Skill id (directory name under .claude/skills)"
            },
            input: %{
              type: "string",
              description: "Input for the skill"
            },
            vars: %{
              type: "object",
              description: "Optional template variables for skill execution",
              additionalProperties: true
            },
            working_dir: %{
              type: "string",
              description: "Optional working directory override (CLI runner only)"
            },
            timeout_ms: %{
              type: "integer",
              description: "Optional timeout override in milliseconds (CLI runner only)",
              minimum: 1
            },
            approval_token: %{
              type: "string",
              description:
                "Optional. If omitted and approval is required, HAL will create an approval request and return an approval_token. Approve it in the HAL UI at /approvals, then retry with approval_token."
            }
          },
          required: ["skill", "input"]
        }
      }
    ]
  end

  # Codops Tools (safe self-improvement via patches)

  defp codops_tools do
    [
      %{
        name: "hal_codops_create_change_request",
        description:
          "Create a codops ChangeRequest to modify HAL's code safely. Generates changes in an isolated git worktree, runs tests, and (if successful) requests human approval to apply the patch.",
        input_schema: %{
          type: "object",
          properties: %{
            title: %{
              type: "string",
              description:
                "Short title for the change request (optional; derived from task if omitted)"
            },
            task: %{
              type: "string",
              description: "Detailed description of the code change to implement"
            },
            test_command: %{
              type: "string",
              description:
                "Optional command to validate the change in the worktree (default: mix test)"
            },
            approval_token: %{
              type: "string",
              description:
                "Optional. If omitted, HAL will create an approval request and return an approval_token. Approve it in the HAL UI at /approvals, then retry with approval_token."
            }
          },
          required: ["task"]
        }
      },
      %{
        name: "hal_codops_apply_change_request",
        description:
          "Apply a ready ChangeRequest patch to the main repo. Requires explicit human approval. Refuses to modify protected core safety files.",
        input_schema: %{
          type: "object",
          properties: %{
            change_request_id: %{
              type: "string",
              description: "ID of the change request to apply"
            },
            force: %{
              type: "boolean",
              description:
                "If true, allow applying even if tests failed (not recommended). Still blocked if protected files are touched."
            },
            approval_token: %{
              type: "string",
              description:
                "Optional. If omitted, HAL will create an approval request and return an approval_token. Approve it in the HAL UI at /approvals, then retry with approval_token."
            }
          },
          required: ["change_request_id"]
        }
      }
    ]
  end

  # MCP Tools (Model Context Protocol)

  defp mcp_tools do
    [
      %{
        name: "hal_mcp_start_named_connection",
        description:
          "Start a named MCP server connection from ~/.hal/mcp-servers.json. Use this once per server before calling its tools.",
        input_schema: %{
          type: "object",
          properties: %{
            name: %{
              type: "string",
              description: "Configured MCP server name (key in ~/.hal/mcp-servers.json)"
            },
            approval_token: %{
              type: "string",
              description:
                "Optional. If omitted, HAL will create an approval request and return an approval_token. Approve it in the HAL UI at /approvals, then retry with approval_token."
            }
          },
          required: ["name"]
        }
      },
      %{
        name: "hal_mcp_list_connections",
        description: "List active MCP connections.",
        input_schema: %{
          type: "object",
          properties: %{},
          required: []
        }
      },
      %{
        name: "hal_mcp_list_tools",
        description: "List available tools for a named MCP connection.",
        input_schema: %{
          type: "object",
          properties: %{
            name: %{
              type: "string",
              description: "MCP connection name"
            }
          },
          required: ["name"]
        }
      },
      %{
        name: "hal_mcp_call_tool",
        description:
          "Call a tool on a named MCP connection. This is powerful; prefer specific HAL tools when available.",
        input_schema: %{
          type: "object",
          properties: %{
            name: %{
              type: "string",
              description: "MCP connection name"
            },
            tool: %{
              type: "string",
              description: "Tool name on the MCP server"
            },
            arguments: %{
              type: "object",
              description: "Tool arguments"
            },
            approval_token: %{
              type: "string",
              description:
                "Optional. If omitted, HAL will create an approval request and return an approval_token. Approve it in the HAL UI at /approvals, then retry with approval_token."
            }
          },
          required: ["name", "tool"]
        }
      }
    ]
  end

  # Browser Tools (leverages Chrome DevTools MCP + Claude Extension)

  defp browser_tools do
    [
      %{
        name: "hal_browser_navigate",
        description:
          "Navigate to a URL in the browser. Use Chrome DevTools MCP for automation or Claude Extension for interactive sessions with existing logins.",
        input_schema: %{
          type: "object",
          properties: %{
            url: %{
              type: "string",
              description: "The URL to navigate to"
            },
            mode: %{
              type: "string",
              description:
                "Browser mode: 'devtools' for headless/automation, 'extension' for interactive with existing session",
              enum: ["devtools", "extension"]
            },
            wait_for: %{
              type: "string",
              description: "Wait condition: 'load', 'domcontentloaded', or 'networkidle'",
              enum: ["load", "domcontentloaded", "networkidle"]
            }
          },
          required: ["url"]
        }
      },
      %{
        name: "hal_browser_snapshot",
        description:
          "Take a snapshot of the current page as an accessibility tree. Returns structured DOM with unique element IDs (uids) for targeting. Prefer this over screenshots for reliable element targeting.",
        input_schema: %{
          type: "object",
          properties: %{
            verbose: %{
              type: "boolean",
              description: "Include full accessibility tree information (default: false)"
            },
            selector: %{
              type: "string",
              description: "Optional CSS selector to snapshot a specific element"
            }
          },
          required: []
        }
      },
      %{
        name: "hal_browser_click",
        description:
          "Click on an element identified by its uid from a snapshot, or by CSS selector.",
        input_schema: %{
          type: "object",
          properties: %{
            uid: %{
              type: "string",
              description: "Element uid from a snapshot (preferred)"
            },
            selector: %{
              type: "string",
              description: "CSS selector (fallback if uid not available)"
            },
            double_click: %{
              type: "boolean",
              description: "Perform a double-click instead of single click"
            }
          },
          required: []
        }
      },
      %{
        name: "hal_browser_fill",
        description:
          "Fill a form field with text. Can target by uid from snapshot or CSS selector.",
        input_schema: %{
          type: "object",
          properties: %{
            uid: %{
              type: "string",
              description: "Element uid from a snapshot (preferred)"
            },
            selector: %{
              type: "string",
              description: "CSS selector (fallback)"
            },
            value: %{
              type: "string",
              description: "Text to fill into the field"
            },
            clear_first: %{
              type: "boolean",
              description: "Clear existing content before filling (default: true)"
            }
          },
          required: ["value"]
        }
      },
      %{
        name: "hal_browser_screenshot",
        description: "Take a screenshot of the current page or a specific element.",
        input_schema: %{
          type: "object",
          properties: %{
            full_page: %{
              type: "boolean",
              description: "Capture the full scrollable page (default: false, viewport only)"
            },
            selector: %{
              type: "string",
              description: "Optional CSS selector to screenshot a specific element"
            },
            format: %{
              type: "string",
              description: "Image format",
              enum: ["png", "jpeg"]
            }
          },
          required: []
        }
      },
      %{
        name: "hal_browser_evaluate",
        description:
          "Execute JavaScript code in the browser context. Returns JSON-serializable results.",
        input_schema: %{
          type: "object",
          properties: %{
            script: %{
              type: "string",
              description:
                "JavaScript code to execute. Wrap in a function: () => { return document.title; }"
            },
            args: %{
              type: "array",
              description: "Optional arguments to pass to the function",
              items: %{type: "string"}
            }
          },
          required: ["script"]
        }
      },
      %{
        name: "hal_browser_console",
        description:
          "Get browser console messages (logs, warnings, errors) from the current page.",
        input_schema: %{
          type: "object",
          properties: %{
            level: %{
              type: "string",
              description: "Filter by log level",
              enum: ["all", "log", "warning", "error"]
            },
            limit: %{
              type: "integer",
              description: "Maximum number of messages to return (default: 50)"
            }
          },
          required: []
        }
      },
      %{
        name: "hal_browser_network",
        description:
          "Get network requests from the current page for debugging or API inspection.",
        input_schema: %{
          type: "object",
          properties: %{
            filter: %{
              type: "string",
              description: "Filter requests by URL pattern"
            },
            type: %{
              type: "string",
              description: "Filter by request type",
              enum: ["all", "xhr", "fetch", "document", "script", "stylesheet", "image"]
            },
            limit: %{
              type: "integer",
              description: "Maximum number of requests to return (default: 50)"
            }
          },
          required: []
        }
      }
    ]
  end

  # Self-Modification Tools (for agent self-improvement)

  defp self_modification_tools do
    [
      %{
        name: "hal_self_update_personality",
        description:
          "Update one of your personality traits based on user feedback or self-reflection. Rate limited to 3 changes per day. Use this when you learn something about user preferences that suggests a different communication style.",
        input_schema: %{
          type: "object",
          properties: %{
            trait: %{
              type: "string",
              description: "The trait to update",
              enum: [
                "assertiveness",
                "warmth",
                "verbosity",
                "proactivity",
                "risk_tolerance",
                "humor",
                "formality"
              ]
            },
            new_value: %{
              type: "number",
              description: "New value for the trait (0.0 to 1.0)",
              minimum: 0.0,
              maximum: 1.0
            },
            reason: %{
              type: "string",
              description: "Why you're making this change (required for audit trail)"
            }
          },
          required: ["trait", "new_value", "reason"]
        }
      },
      %{
        name: "hal_self_update_preference",
        description:
          "Store a learned preference about the user or how to interact with them. Unlike traits, preferences are key-value pairs without rate limiting.",
        input_schema: %{
          type: "object",
          properties: %{
            key: %{
              type: "string",
              description:
                "Preference key (e.g., 'prefers_bullet_points', 'timezone', 'communication_hours')"
            },
            value: %{
              type: "string",
              description: "Preference value (will be stored as-is)"
            }
          },
          required: ["key", "value"]
        }
      },
      %{
        name: "hal_self_set_goal",
        description:
          "Create a new goal to work toward autonomously. Goals are hierarchical: long_term (months), medium_term (weeks), short_term (days/hours).",
        input_schema: %{
          type: "object",
          properties: %{
            title: %{
              type: "string",
              description: "Goal title (clear and actionable)"
            },
            description: %{
              type: "string",
              description: "Detailed description of what success looks like"
            },
            type: %{
              type: "string",
              description: "Goal time horizon",
              enum: ["long_term", "medium_term", "short_term"]
            },
            success_criteria: %{
              type: "array",
              description: "List of criteria that must be met for goal completion",
              items: %{type: "string"}
            },
            target_date: %{
              type: "string",
              description: "Optional target date in ISO 8601 format",
              format: "date-time"
            },
            parent_id: %{
              type: "string",
              description: "Optional UUID of parent goal (for sub-goals)"
            },
            priority: %{
              type: "integer",
              description: "Priority 0-100 (higher = more important, default: 50)",
              minimum: 0,
              maximum: 100
            }
          },
          required: ["title", "type"]
        }
      },
      %{
        name: "hal_self_update_goal",
        description:
          "Update progress or status of an existing goal. Use after making progress toward a goal.",
        input_schema: %{
          type: "object",
          properties: %{
            goal_id: %{
              type: "string",
              description: "UUID of the goal to update"
            },
            progress: %{
              type: "number",
              description: "New progress value (0.0 to 1.0)",
              minimum: 0.0,
              maximum: 1.0
            },
            summary: %{
              type: "string",
              description: "What was accomplished (required when updating progress)"
            },
            status: %{
              type: "string",
              description: "New status (optional)",
              enum: ["active", "paused", "completed", "abandoned"]
            }
          },
          required: ["goal_id"]
        }
      },
      %{
        name: "hal_self_reflect",
        description:
          "Log a reflection or learning for self-improvement. Use when you discover something worth remembering about how to be more effective.",
        input_schema: %{
          type: "object",
          properties: %{
            observation: %{
              type: "string",
              description: "What you observed or learned"
            },
            impact: %{
              type: "string",
              description: "How this should affect future behavior"
            },
            type: %{
              type: "string",
              description: "Category of observation",
              enum: [
                "user_preference",
                "tool_effectiveness",
                "delegation_success",
                "communication_style",
                "mistake_learned",
                "other"
              ]
            },
            confidence: %{
              type: "string",
              description: "How confident you are in this observation",
              enum: ["low", "medium", "high"]
            }
          },
          required: ["observation", "type"]
        }
      },
      %{
        name: "hal_get_self_status",
        description:
          "Get current personality traits, active goals, and recent observations. Use this to understand your current configuration and what you're working toward.",
        input_schema: %{
          type: "object",
          properties: %{
            include_personality: %{
              type: "boolean",
              description: "Include personality traits (default: true)"
            },
            include_goals: %{
              type: "boolean",
              description: "Include active goals (default: true)"
            },
            include_observations: %{
              type: "boolean",
              description: "Include recent observations (default: true)"
            },
            observation_limit: %{
              type: "integer",
              description: "Number of recent observations to include (default: 5)"
            }
          },
          required: []
        }
      }
    ]
  end
end
