# HAL Code Generation Architecture

## The Core Question

**When HAL receives: "Build me a Next.js app for task management"**

How does the code actually get written? Three architectures:

---

## Option A: Full Claude Code CLI Delegation (Current Implementation)

### How It Works
```elixir
# User: "Build me a Next.js app"
# ↓
# HAL receives via Telegram
# ↓
HAL.Gateway.SessionServer
  ↓
HAL.AI.ClaudeCode.prompt(session_id, "Build me a Next.js app")
  ↓
System.cmd("claude", ["-p", "Build me a Next.js app", "--resume", session_id])
  ↓
Claude Code CLI:
  - Reads files (Read tool)
  - Writes files (Write tool)
  - Executes bash (Bash tool)
  - Searches web (WebSearch tool)
  - Returns final response
  ↓
HAL sends response back to Telegram
```

### What HAL Knows
```json
{
  "result": "I've created a Next.js task management app...",
  "session_id": "abc123"
}
```

### What HAL DOESN'T Know
- Which files were created
- What bash commands were run
- Tool execution sequence
- Intermediate steps
- File contents before/after

### Pros ✅
- Minimal code (just shell wrapper)
- Leverage full Claude Code capabilities
- Automatic updates (when Claude Code CLI updates)
- Session continuity works perfectly
- All tools (Read, Write, Edit, Bash, WebSearch, etc.) available

### Cons ❌
- **Black box** - Can't inspect tool calls
- **No custom tools** - Can't add HAL-specific tools
- **Limited control** - Can't intercept/modify tool execution
- **No observability** - Can't log what files changed
- **Can't add constraints** - Can't restrict file operations to certain directories
- **Requires Claude Code CLI** - Must be installed on Mac mini
- **Headless limitations** - Some Claude Code features may not work headless

### Use Cases
- ✅ Personal assistant (you trust it completely)
- ✅ Simple delegated coding tasks
- ❌ Multi-tenant (can't isolate users)
- ❌ Audit trails (can't log file changes)
- ❌ Custom workflows (can't inject HAL-specific tools)

---

## Option B: HAL Implements Tools Natively (Pi Agent Pattern)

### How It Works
```elixir
# User: "Build me a Next.js app"
# ↓
HAL.Gateway.SessionServer
  ↓
HAL.Agent.run_loop(%{
  messages: [...],
  tools: [
    HAL.Tools.Read,
    HAL.Tools.Write,
    HAL.Tools.Bash,
    HAL.Tools.WebSearch
  ]
})
  ↓
HAL.LLM.Provider.Anthropic.stream(%{
  model: "claude-3-5-sonnet",
  messages: [...],
  tools: [...]  # Tool schemas
})
  ↓
Stream events:
  {:toolcall_delta, %{name: "write_file", args: %{path: "app/page.tsx", content: "..."}}}
  ↓
HAL.ToolRunner.execute("write_file", args)
  ↓
File.write!("app/page.tsx", content)
  ↓
Emit: {:tool_result, %{success: true, path: "app/page.tsx"}}
  ↓
Continue streaming...
```

### Implementation Example
```elixir
defmodule HAL.Tools.Write do
  def schema do
    %{
      name: "write_file",
      description: "Write content to a file",
      parameters: %{
        type: "object",
        properties: %{
          path: %{type: "string", description: "File path"},
          content: %{type: "string", description: "File content"}
        },
        required: ["path", "content"]
      }
    }
  end

  def execute(%{"path" => path, "content" => content}) do
    # HAL can add custom logic here
    abs_path = Path.expand(path)

    # Validate: only write to allowed directories
    if String.starts_with?(abs_path, "/Users/you/projects/") do
      File.write!(abs_path, content)

      # Log the change
      :telemetry.execute([:hal, :tools, :write_file], %{size: byte_size(content)}, %{path: path})

      {:ok, "File written: #{path}"}
    else
      {:error, "Access denied: #{path} outside allowed directory"}
    end
  end
end

defmodule HAL.Tools.Bash do
  def schema do
    %{
      name: "bash",
      description: "Execute bash command",
      parameters: %{
        type: "object",
        properties: %{
          command: %{type: "string", description: "Command to execute"}
        },
        required: ["command"]
      }
    }
  end

  def execute(%{"command" => command}) do
    # HAL controls execution environment
    {output, exit_code} = System.cmd("bash", ["-c", command],
      stderr_to_stdout: true,
      env: [{"PATH", System.get_env("PATH")}],
      cd: "/Users/you/projects"  # Control working directory
    )

    # Log execution
    :telemetry.execute([:hal, :tools, :bash], %{duration: 0}, %{command: command, exit_code: exit_code})

    {:ok, output}
  end
end
```

### What HAL Knows
- Every tool call (name, arguments, result)
- File changes (before/after contents)
- Bash commands executed
- Web searches performed
- Tool execution order
- Success/failure of each tool

### Pros ✅
- **Full observability** - See every tool call
- **Custom tools** - Add HAL-specific tools (Telegram send, database query, etc.)
- **Fine-grained control** - Validate/restrict tool execution
- **Audit trails** - Log all file changes
- **Multi-tenant ready** - Isolate users to different directories
- **No external dependencies** - Just Elixir + LLM API
- **Better error handling** - Catch and recover from tool failures

### Cons ❌
- **More code to maintain** - Must implement all tools
- **Need to reimplement** - Claude Code tools already exist
- **API costs** - Pay-per-token vs Claude Code subscription
- **Need to keep up** - When Anthropic adds new tools, must implement
- **Session management** - Must build our own session continuity

### Use Cases
- ✅ Multi-tenant SaaS
- ✅ Audit requirements
- ✅ Custom workflows
- ✅ Integration with HAL-specific features
- ❌ Quick MVP (more upfront work)

---

## Option C: Hybrid Architecture (Best of Both)

### How It Works
```elixir
# HAL has TWO execution modes:

# Mode 1: Simple file operations (HAL tools)
User: "Create a file hello.txt with 'Hello World'"
  ↓
HAL.Agent (using HAL.Tools.Write)
  ↓
File written directly, full observability

# Mode 2: Complex coding tasks (delegate to Claude Code)
User: "Build a complete Next.js app with auth and database"
  ↓
HAL.AI.ClaudeCode.prompt(...)
  ↓
Claude Code CLI handles everything
  ↓
Black box execution, but leverages full Claude Code power
```

### Routing Logic
```elixir
defmodule HAL.AI.Router do
  def route(message, opts) do
    cond do
      simple_task?(message) ->
        # Use HAL's native tools
        HAL.Agent.run(message, tools: HAL.Tools.all())

      coding_task?(message) ->
        # Delegate to Claude Code CLI
        HAL.AI.ClaudeCode.prompt(opts[:session_id], message)

      quick_question?(message) ->
        # Use Gemini (fast, cheap)
        HAL.AI.Gemini.prompt(message)
    end
  end

  defp simple_task?(message) do
    message =~ ~r/create (a )?file|read file|list files|run command/i
  end

  defp coding_task?(message) do
    message =~ ~r/build|implement|refactor|debug|add feature/i
  end

  defp quick_question?(message) do
    message =~ ~r/what is|how do|explain|translate/i
  end
end
```

### HAL Tools (Native Implementation)
```elixir
defmodule HAL.Tools do
  def all do
    [
      HAL.Tools.Read,       # Read files
      HAL.Tools.Write,      # Write files
      HAL.Tools.Bash,       # Execute commands
      HAL.Tools.ListFiles,  # List directory
      HAL.Tools.Search,     # Search codebase
      HAL.Tools.Telegram,   # Send Telegram message (custom!)
      HAL.Tools.Database,   # Query HAL database (custom!)
      HAL.Tools.Schedule    # Schedule task (custom!)
    ]
  end
end
```

### Custom Tools Example
```elixir
defmodule HAL.Tools.Telegram do
  def schema do
    %{
      name: "send_telegram",
      description: "Send a message to a Telegram chat",
      parameters: %{
        type: "object",
        properties: %{
          chat_id: %{type: "string"},
          message: %{type: "string"}
        },
        required: ["chat_id", "message"]
      }
    }
  end

  def execute(%{"chat_id" => chat_id, "message" => message}) do
    HAL.Channels.Telegram.send_message(chat_id, message)
    {:ok, "Message sent"}
  end
end

# NOW the AI can:
# - Read a file with scheduled tasks
# - Send reminder via Telegram
# - All in one agentic loop!
```

### Pros ✅
- **Best of both worlds** - Observability + Claude Code power
- **Flexibility** - Choose right tool for the job
- **Progressive enhancement** - Start with Claude Code, add HAL tools as needed
- **Custom capabilities** - HAL-specific tools (Telegram, scheduling, etc.)
- **Cost optimization** - Use Claude Code subscription for heavy lifting

### Cons ❌
- **Complexity** - Two execution paths
- **Routing logic** - Must decide when to use which
- **Maintenance** - Both systems to maintain
- **Consistency** - Different tool sets in different modes

### Use Cases
- ✅ Personal AI assistant (your use case!)
- ✅ Want observability for simple tasks
- ✅ Want Claude Code power for complex tasks
- ✅ Want custom HAL-specific tools
- ✅ Cost-conscious (use subscription when available)

---

## Recommended Architecture for HAL

### **Start with Option C (Hybrid), bias toward Claude Code**

**Phase 1: Current State (Mostly Option A)**
```elixir
# All coding tasks → Claude Code CLI
HAL.AI.ClaudeCode.prompt(session_id, message)
```

**Phase 2: Add HAL Tools for Simple Operations** (2-3 days)
```elixir
defmodule HAL.Agent do
  def run(message, tools: tools) do
    # Use Anthropic API with tool calling
    HAL.LLM.Provider.Anthropic.stream(%{
      model: "claude-3-5-sonnet",
      messages: [%{role: "user", content: message}],
      tools: Enum.map(tools, & &1.schema())
    })
    |> process_tool_calls(tools)
  end
end

# Simple tasks
HAL.Agent.run("Create a file hello.txt", tools: [HAL.Tools.Write])

# Complex tasks still delegate
HAL.AI.ClaudeCode.prompt(session_id, "Build Next.js app")
```

**Phase 3: Add Custom HAL Tools** (1 week)
```elixir
HAL.Tools.Telegram    # Send messages
HAL.Tools.Schedule    # Schedule tasks
HAL.Tools.Database    # Query HAL data
HAL.Tools.Memory      # Access conversation history
```

**Phase 4: Smart Routing** (1 week)
```elixir
HAL.AI.Router.route(message, session_id: id)
  ↓
Simple file ops → HAL.Agent (with HAL tools)
Complex coding → ClaudeCode.prompt
Quick questions → Gemini.prompt
```

---

## Tool Comparison Table

| Tool | Option A (Claude Code CLI) | Option B (Native Tools) | Option C (Hybrid) |
|------|---------------------------|------------------------|-------------------|
| **Read File** | ✅ Claude Code | ✅ HAL.Tools.Read | ✅ Both |
| **Write File** | ✅ Claude Code | ✅ HAL.Tools.Write | ✅ Both |
| **Bash** | ✅ Claude Code | ✅ HAL.Tools.Bash | ✅ Both |
| **WebSearch** | ✅ Claude Code | 🔶 Need to implement | ✅ Claude Code |
| **Edit File** | ✅ Claude Code | 🔶 Need to implement | ✅ Both |
| **Send Telegram** | ❌ Not available | ✅ HAL.Tools.Telegram | ✅ HAL only |
| **Schedule Task** | ❌ Not available | ✅ HAL.Tools.Schedule | ✅ HAL only |
| **Query Database** | ❌ Not available | ✅ HAL.Tools.Database | ✅ HAL only |
| **Observability** | ❌ Black box | ✅ Full logs | ✅ Partial |
| **Cost** | ✅ Subscription | ❌ Pay per token | ✅ Mix |

---

## Implementation Example: Hybrid Mode

```elixir
# lib/hal/ai/router.ex
defmodule HAL.AI.Router do
  require Logger

  def route(message, opts) do
    session_id = opts[:session_id]

    case determine_execution_mode(message) do
      :hal_agent ->
        Logger.info("Using HAL native tools for: #{message}")
        execute_with_hal_agent(session_id, message)

      :claude_code ->
        Logger.info("Delegating to Claude Code for: #{message}")
        HAL.AI.ClaudeCode.prompt(session_id, message, opts)

      :gemini ->
        Logger.info("Using Gemini for quick answer: #{message}")
        HAL.AI.Gemini.prompt(message)
    end
  end

  defp determine_execution_mode(message) do
    cond do
      # Complex coding → Claude Code
      Regex.match?(~r/build|create app|implement|refactor|debug/i, message) ->
        :claude_code

      # Simple file ops → HAL tools
      Regex.match?(~r/create file|read file|list files|send message/i, message) ->
        :hal_agent

      # Quick questions → Gemini
      Regex.match?(~r/what is|how do|explain|translate/i, message) ->
        :gemini

      # Default → Claude Code (safest)
      true ->
        :claude_code
    end
  end

  defp execute_with_hal_agent(session_id, message) do
    HAL.Agent.run(message,
      session_id: session_id,
      tools: [
        HAL.Tools.Read,
        HAL.Tools.Write,
        HAL.Tools.Bash,
        HAL.Tools.ListFiles,
        HAL.Tools.Telegram,  # Custom!
        HAL.Tools.Schedule   # Custom!
      ]
    )
  end
end
```

---

## Answer to Your Question

### "Would it call Claude Code in print mode, or would it be able to run the CLI?"

**Current implementation:** HAL calls Claude Code CLI in **headless mode** via `System.cmd("claude", ["-p", prompt])`. The `-p` flag is "prompt mode" which:
- Accepts prompt from command line
- Executes tools (Bash, Read, Write, Edit, etc.)
- Returns JSON output
- Supports `--resume` for session continuity

**Not using:** Interactive mode (no TUI), just programmatic execution.

### "Or does it need to write code itself using its own tools?"

**Best approach:** Hybrid
- **Complex coding** → Delegate to Claude Code CLI (leverage your subscription)
- **Simple operations** → Use HAL native tools (observability + custom capabilities)
- **Custom workflows** → HAL tools let you add Telegram, scheduling, database access, etc.

This gives you:
1. ✅ Full Claude Code power for coding tasks (subscription value)
2. ✅ Observability for simple operations (know what's happening)
3. ✅ Custom tools Claude Code doesn't have (Telegram, scheduling, etc.)
4. ✅ Cost optimization (subscription vs API costs)

---

## Next Steps

**Recommended implementation order:**

1. **Keep current Claude Code delegation** (already works)
2. **Add HAL.Agent with basic tools** (Read, Write, Bash)
3. **Add custom HAL tools** (Telegram, Schedule, Database)
4. **Implement smart routing** (simple → HAL, complex → Claude Code)

This gives you a personal AI assistant that:
- Can code full applications (via Claude Code)
- Can do simple tasks with full observability (via HAL tools)
- Has unique capabilities Claude Code doesn't (Telegram, scheduling, etc.)

Want me to implement HAL.Agent with native tool support?
