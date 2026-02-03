# HAL Best Practices

**Version 1.0.0**
HAL Personal AI Assistant
February 2026

> **Note:**
> This document is for AI agents and LLMs to follow when maintaining,
> generating, or refactoring the HAL codebase. Guidance here is optimized
> for automation and consistency by AI-assisted workflows.

---

## Abstract

Performance and architecture guide for HAL, an Elixir/Phoenix personal AI assistant. Contains rules across 8 categories covering OTP patterns, Phoenix performance, AI integration, and HAL-specific architecture. Each rule includes explanations, code examples comparing incorrect vs. correct implementations, and impact ratings.

---

## Table of Contents

0. [No Simulation Rule](#0-no-simulation-rule) — **CRITICAL (NON-NEGOTIABLE)**
1. [Core Architecture](#1-core-architecture) — **CRITICAL**
2. [OTP Patterns](#2-otp-patterns) — **CRITICAL**
3. [Phoenix Performance](#3-phoenix-performance) — **HIGH**
4. [AI Integration](#4-ai-integration) — **HIGH**
5. [Database & Ecto](#5-database--ecto) — **MEDIUM-HIGH**
6. [Memory & State](#6-memory--state) — **MEDIUM**
7. [Testing](#7-testing) — **MEDIUM**
8. [Error Handling](#8-error-handling) — **MEDIUM**

---

## 0. No Simulation Rule

**Impact: CRITICAL (NON-NEGOTIABLE)**

Never create simulated, mocked, or placeholder implementations without explicit disclosure to the user.

### 0.1 Always Disclose Simulation Status

**Impact: CRITICAL (trust)**

If an API doesn't exist, an SDK isn't available, or a feature is stubbed - tell the user immediately.

**Incorrect: Hidden simulation**

```elixir
defmodule HAL.Agents.Jules do
  def start_task(description, opts) do
    # Looks real but returns fake data
    {:ok, %{"id" => generate_id(), "status" => "running"}}
  end
end
```

**Correct: Explicit simulation with disclosure**

```elixir
defmodule HAL.Agents.Jules do
  @moduledoc """
  SIMULATED: Jules API does not exist yet.
  This module returns placeholder responses for development.
  Real implementation pending Jules API release.
  """

  def start_task(description, opts) do
    # SIMULATED: Returns fake response - Jules API not available
    Logger.warning("Jules is SIMULATED - no real API call made")
    {:ok, %{"id" => generate_id(), "status" => "simulated"}}
  end
end
```

### 0.2 Mark Simulated Code Clearly

**Impact: CRITICAL (maintainability)**

Use consistent markers so simulated code is obvious.

**Required markers:**
- `# SIMULATED:` comment on placeholder functions
- `@moduledoc` must state simulation status
- Return values should indicate simulation (e.g., `status: "simulated"`)
- Log warnings when simulated paths are hit

### 0.3 Never Claim Simulated Features Work

**Impact: CRITICAL (honesty)**

When presenting results to the user:

- ❌ "Jules task started successfully" (when simulated)
- ❌ "Delegated to Codex" (when no Codex CLI)
- ✅ "Jules is SIMULATED - API doesn't exist yet. Task would be: X"
- ✅ "Codex delegation is stubbed - CLI not installed"

---

## 1. Core Architecture

**Impact: CRITICAL**

HAL's architecture follows one non-negotiable principle: Claude (Opus) is the brain. The brain decides everything.

### 1.1 Brain Decides, HAL Executes

**Impact: CRITICAL (architectural consistency)**

Never implement decision logic in HAL. Claude makes all decisions about what to do, when to delegate, and which tools to use.

**Incorrect: HAL makes routing decisions**

```elixir
defmodule HAL.Router do
  def route(message) do
    cond do
      String.contains?(message, "code") ->
        HAL.Agents.Codex.start_session(message)
      String.contains?(message, "summarize") ->
        HAL.Agents.Gemini.summarize(message)
      true ->
        HAL.AI.AgentSDK.prompt(message)
    end
  end
end
```

**Correct: Claude decides via tools**

```elixir
defmodule HAL.Tools.Delegation do
  @doc """
  Tool that Claude calls when it decides to delegate.
  HAL just executes - no decision logic here.
  """
  def delegate_to_codex(task, opts) do
    # Claude decided. HAL executes.
    HAL.Agents.Codex.start_session(task, opts)
  end

  def delegate_to_gemini(text, opts) do
    HAL.Agents.Gemini.summarize(text, opts)
  end
end
```

### 1.2 Tools Over Direct Calls

**Impact: HIGH (traceability, consistency)**

All AI agent interactions should go through the tool system, not direct function calls. This ensures logging, metrics, and consistent error handling.

**Incorrect: Direct agent calls**

```elixir
def handle_request(message) do
  case Hal.AI.Gemini.prompt(nil, message) do
    {:ok, response, _} -> response
    {:error, _} -> "Error"
  end
end
```

**Correct: Via tool system**

```elixir
def handle_request(message, session) do
  HAL.Tools.execute(:gemini_prompt, %{
    message: message,
    session_id: session.id
  })
end
```

### 1.3 Skills Over MCP

**Impact: MEDIUM-HIGH (token efficiency)**

Prefer Agent Skills format over MCP servers. Skills use progressive disclosure (~100 tokens until activated), MCP loads everything upfront.

**Incorrect: Heavy MCP integration**

```elixir
# Loads full tool definitions at startup
config :hal, :mcp_servers, [
  %{name: "calendar", url: "http://localhost:3001"},
  %{name: "email", url: "http://localhost:3002"},
  %{name: "tasks", url: "http://localhost:3003"}
]
```

**Correct: Skills with Elixir implementations**

```
.claude/skills/
├── calendar-management/
│   └── SKILL.md          # ~100 tokens, loads on demand
└── lib/hal/tools/
    └── calendar.ex       # Elixir implementation
```

---

## 2. OTP Patterns

**Impact: CRITICAL**

OTP patterns are the foundation of reliable Elixir applications. Misuse leads to crashes, memory leaks, and poor fault tolerance.

### 2.1 Use Supervisors for Fault Tolerance

**Impact: CRITICAL (reliability)**

Every long-running process should be supervised. Never start GenServers directly.

**Incorrect: Unsupervised process**

```elixir
defmodule HAL.Application do
  def start(_type, _args) do
    # Process dies, stays dead
    {:ok, _pid} = HAL.Agents.Codex.start_link()

    children = [HalWeb.Endpoint]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

**Correct: Supervised process tree**

```elixir
defmodule HAL.Application do
  def start(_type, _args) do
    children = [
      HAL.Agents.Supervisor,  # Supervises Codex, Jules, Gemini
      HalWeb.Endpoint
    ]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end

defmodule HAL.Agents.Supervisor do
  use Supervisor

  def init(_) do
    children = [
      HAL.Agents.Codex,
      HAL.Agents.Jules,
      HAL.Agents.Gemini
    ]
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

### 2.2 GenServer State Should Be Minimal

**Impact: HIGH (memory, crash recovery)**

Store only essential state in GenServer. Use ETS for large datasets, database for persistence.

**Incorrect: Large state in GenServer**

```elixir
defmodule HAL.Memory do
  use GenServer

  def init(_) do
    # Loads all memories into process state
    memories = Repo.all(Memory)
    {:ok, %{memories: memories}}
  end
end
```

**Correct: Minimal state, ETS for data**

```elixir
defmodule HAL.Memory do
  use GenServer

  def init(_) do
    :ets.new(:memory_cache, [:named_table, :public, read_concurrency: true])
    {:ok, %{initialized: true}}
  end

  def get(key) do
    case :ets.lookup(:memory_cache, key) do
      [{^key, value}] -> {:ok, value}
      [] -> {:error, :not_found}
    end
  end
end
```

### 2.3 Use handle_continue for Initialization

**Impact: MEDIUM (startup performance)**

Heavy initialization should happen in `handle_continue/2`, not `init/1`. This allows the supervisor to continue starting other children.

**Incorrect: Blocking init**

```elixir
def init(_) do
  # Blocks supervisor startup
  data = fetch_external_data()
  index = build_index(data)
  {:ok, %{index: index}}
end
```

**Correct: Non-blocking with continue**

```elixir
def init(_) do
  {:ok, %{status: :initializing}, {:continue, :load_data}}
end

def handle_continue(:load_data, state) do
  data = fetch_external_data()
  index = build_index(data)
  {:noreply, %{state | status: :ready, index: index}}
end
```

### 2.4 Avoid Process Bottlenecks

**Impact: HIGH (scalability)**

Don't funnel all requests through a single GenServer. Use pooling or per-request processes.

**Incorrect: Single bottleneck**

```elixir
defmodule HAL.AI.Client do
  use GenServer

  def prompt(message) do
    # All requests serialized through one process
    GenServer.call(__MODULE__, {:prompt, message}, :infinity)
  end
end
```

**Correct: Pooled or per-request**

```elixir
defmodule HAL.AI.Client do
  def prompt(message) do
    # Each request gets its own task
    Task.async(fn ->
      do_api_call(message)
    end)
    |> Task.await(:infinity)
  end
end

# Or use poolboy for connection pooling
```

---

## 3. Phoenix Performance

**Impact: HIGH**

Phoenix is fast by default, but poor patterns can introduce latency.

### 3.1 Use Async Assigns in LiveView

**Impact: HIGH (perceived performance)**

Load slow data asynchronously to render the page faster.

**Incorrect: Blocking mount**

```elixir
def mount(_params, _session, socket) do
  # User waits for all data before seeing anything
  memories = HAL.Memory.search("recent")
  tasks = HAL.Tasks.list_pending()
  emails = HAL.Email.get_unread()

  {:ok, assign(socket, memories: memories, tasks: tasks, emails: emails)}
end
```

**Correct: Async loading**

```elixir
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign(:page_title, "Dashboard")
   |> assign_async(:memories, fn -> {:ok, HAL.Memory.search("recent")} end)
   |> assign_async(:tasks, fn -> {:ok, HAL.Tasks.list_pending()} end)
   |> assign_async(:emails, fn -> {:ok, HAL.Email.get_unread()} end)}
end
```

### 3.2 Minimize LiveView Payload

**Impact: MEDIUM-HIGH (network, rendering)**

Only send data the template needs. Transform server-side.

**Incorrect: Sending full records**

```elixir
def mount(_params, _session, socket) do
  # Sends entire user records with all fields
  users = Repo.all(User) |> Repo.preload(:profile)
  {:ok, assign(socket, users: users)}
end
```

**Correct: Project only needed fields**

```elixir
def mount(_params, _session, socket) do
  users =
    from(u in User, select: %{id: u.id, name: u.name, avatar: u.avatar})
    |> Repo.all()
  {:ok, assign(socket, users: users)}
end
```

### 3.3 Use Streams for Large Lists

**Impact: HIGH (memory, performance)**

For large or frequently updating lists, use streams instead of assigns.

**Incorrect: Large list in assigns**

```elixir
def mount(_params, _session, socket) do
  messages = Chat.list_messages(limit: 1000)
  {:ok, assign(socket, messages: messages)}
end

def handle_info({:new_message, msg}, socket) do
  # Resends entire list
  {:noreply, assign(socket, messages: [msg | socket.assigns.messages])}
end
```

**Correct: Using streams**

```elixir
def mount(_params, _session, socket) do
  messages = Chat.list_messages(limit: 1000)
  {:ok, stream(socket, :messages, messages)}
end

def handle_info({:new_message, msg}, socket) do
  # Only sends the new item
  {:noreply, stream_insert(socket, :messages, msg, at: 0)}
end
```

### 3.4 Phoenix 1.8 Layout Guidelines

**Impact: MEDIUM (consistency)**

Always use `<Layouts.app>` wrapper and proper flash handling.

**Incorrect: Missing layout wrapper**

```heex
<div class="container">
  <.flash_group flash={@flash} />
  <h1>Dashboard</h1>
</div>
```

**Correct: With Layouts.app**

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <h1>Dashboard</h1>
</Layouts.app>
```

---

## 4. AI Integration

**Impact: HIGH**

AI integrations are the core of HAL. Optimize for latency, cost, and reliability.

### 4.1 Stream Responses

**Impact: HIGH (perceived latency)**

Always stream AI responses. Users see output immediately instead of waiting.

**Incorrect: Wait for complete response**

```elixir
def handle_event("send", %{"message" => msg}, socket) do
  {:ok, response, _} = HAL.AI.AgentSDK.prompt(msg)
  {:noreply, assign(socket, response: response)}
end
```

**Correct: Stream tokens**

```elixir
def handle_event("send", %{"message" => msg}, socket) do
  self_pid = self()

  Task.start(fn ->
    HAL.AI.AgentSDK.stream(msg, fn chunk ->
      send(self_pid, {:chunk, chunk})
    end)
  end)

  {:noreply, assign(socket, response: "", streaming: true)}
end

def handle_info({:chunk, chunk}, socket) do
  {:noreply, update(socket, :response, &(&1 <> chunk))}
end
```

### 4.2 Implement Timeouts and Fallbacks

**Impact: CRITICAL (reliability)**

AI APIs can be slow or fail. Always have timeouts and fallback behavior.

**Incorrect: No timeout handling**

```elixir
def prompt(message) do
  Req.post(url, json: body)
end
```

**Correct: Timeouts with fallbacks**

```elixir
def prompt(message, opts \\ []) do
  timeout = Keyword.get(opts, :timeout, 30_000)

  case Req.post(url, json: body, receive_timeout: timeout) do
    {:ok, %{status: 200, body: body}} ->
      {:ok, parse_response(body)}

    {:ok, %{status: 429}} ->
      # Rate limited - retry with backoff
      Process.sleep(1000)
      prompt(message, Keyword.put(opts, :retry, true))

    {:ok, %{status: status}} ->
      {:error, {:api_error, status}}

    {:error, %{reason: :timeout}} ->
      {:error, :timeout}

    {:error, reason} ->
      {:error, reason}
  end
end
```

### 4.3 Cache Embeddings

**Impact: HIGH (cost, latency)**

Embeddings are expensive. Cache them aggressively.

**Incorrect: Regenerate every time**

```elixir
def search(query) do
  {:ok, embedding} = generate_embedding(query)
  find_similar(embedding)
end
```

**Correct: Cache with TTL**

```elixir
def search(query) do
  cache_key = :crypto.hash(:sha256, query) |> Base.encode16()

  embedding =
    case Cachex.get(:embeddings, cache_key) do
      {:ok, nil} ->
        {:ok, emb} = generate_embedding(query)
        Cachex.put(:embeddings, cache_key, emb, ttl: :timer.hours(24))
        emb

      {:ok, cached} ->
        cached
    end

  find_similar(embedding)
end
```

### 4.4 Use Appropriate Model for Task

**Impact: HIGH (cost)**

Don't use Opus for tasks Haiku can handle. Route by complexity.

**Incorrect: Opus for everything**

```elixir
def handle_message(message) do
  HAL.AI.AgentSDK.prompt(message, model: "claude-opus-4-5")
end
```

**Correct: Route by task type**

```elixir
def handle_message(message, context) do
  model = select_model(message, context)
  HAL.AI.AgentSDK.prompt(message, model: model)
end

defp select_model(message, context) do
  cond do
    context.requires_reasoning -> "claude-opus-4-5"
    context.is_simple_query -> "claude-haiku-3-5"
    true -> "claude-sonnet-4-5"
  end
end
```

---

## 5. Database & Ecto

**Impact: MEDIUM-HIGH**

Database queries are often the bottleneck. Optimize queries and use pgvector efficiently.

### 5.1 Avoid N+1 Queries

**Impact: HIGH (latency)**

Always preload associations. Use `Repo.preload/2` or join in query.

**Incorrect: N+1 in loop**

```elixir
def list_sessions_with_messages do
  Repo.all(Session)
  |> Enum.map(fn session ->
    messages = Repo.all(from m in Message, where: m.session_id == ^session.id)
    %{session | messages: messages}
  end)
end
```

**Correct: Preload**

```elixir
def list_sessions_with_messages do
  Session
  |> Repo.all()
  |> Repo.preload(:messages)
end

# Or in query for filtering
def list_sessions_with_messages do
  from(s in Session,
    join: m in assoc(s, :messages),
    where: m.inserted_at > ago(1, "day"),
    preload: [messages: m]
  )
  |> Repo.all()
end
```

### 5.2 Use Indexes for pgvector

**Impact: CRITICAL (vector search performance)**

Without proper indexes, vector similarity search is O(n). Add HNSW or IVFFlat indexes.

**Incorrect: No index**

```elixir
# Migration without index
create table(:memories) do
  add :embedding, :vector, size: 768
end
```

**Correct: With HNSW index**

```elixir
create table(:memories) do
  add :embedding, :vector, size: 768
end

# HNSW index for approximate nearest neighbor
execute """
CREATE INDEX memories_embedding_idx
ON memories
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64)
"""
```

### 5.3 Batch Vector Operations

**Impact: HIGH (throughput)**

Don't insert embeddings one at a time. Batch for efficiency.

**Incorrect: One at a time**

```elixir
def store_memories(items) do
  Enum.each(items, fn item ->
    {:ok, embedding} = generate_embedding(item.content)
    Repo.insert!(%Memory{content: item.content, embedding: embedding})
  end)
end
```

**Correct: Batch insert**

```elixir
def store_memories(items) do
  embeddings =
    items
    |> Enum.map(& &1.content)
    |> generate_embeddings_batch()

  entries =
    Enum.zip(items, embeddings)
    |> Enum.map(fn {item, embedding} ->
      %{
        content: item.content,
        embedding: embedding,
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
    end)

  Repo.insert_all(Memory, entries)
end
```

### 5.4 Ecto Field Access

**Impact: MEDIUM (correctness)**

Never use map access syntax on structs. Use dot notation or Changeset helpers.

**Incorrect: Map access on struct**

```elixir
def get_email(changeset) do
  changeset[:email]  # Won't work - structs don't implement Access
end
```

**Correct: Dot notation or helpers**

```elixir
def get_email(changeset) do
  Ecto.Changeset.get_field(changeset, :email)
end

def get_user_email(user) do
  user.email  # Dot notation for structs
end
```

---

## 6. Memory & State

**Impact: MEDIUM**

HAL's memory system uses event sourcing and semantic search. Optimize for both.

### 6.1 Append-Only Event Log

**Impact: HIGH (data integrity)**

Never modify past events. Always append new events.

**Incorrect: Modifying events**

```elixir
def update_memory(id, new_content) do
  event = EventLog.get(id)
  EventLog.update(event, %{content: new_content})
end
```

**Correct: Append correction event**

```elixir
def update_memory(id, new_content) do
  EventLog.append(%{
    type: "memory_updated",
    original_id: id,
    new_content: new_content,
    timestamp: DateTime.utc_now()
  })
end
```

### 6.2 Use ETS for Hot Data

**Impact: HIGH (read latency)**

Frequently accessed data should be in ETS, not database.

**Incorrect: DB for every read**

```elixir
def get_user_preferences(user_id) do
  Repo.get_by(Preference, user_id: user_id)
end
```

**Correct: ETS cache with DB fallback**

```elixir
def get_user_preferences(user_id) do
  case :ets.lookup(:preferences, user_id) do
    [{^user_id, prefs}] ->
      prefs
    [] ->
      prefs = Repo.get_by(Preference, user_id: user_id)
      :ets.insert(:preferences, {user_id, prefs})
      prefs
  end
end
```

---

## 7. Testing

**Impact: MEDIUM**

Tests ensure reliability. Follow these patterns for maintainable tests.

### 7.1 Use Sandbox for Database Tests

**Impact: HIGH (test isolation)**

Always use Ecto.Adapters.SQL.Sandbox for database tests.

**Incorrect: Shared database state**

```elixir
defmodule HAL.MemoryTest do
  use ExUnit.Case

  test "stores memory" do
    # Pollutes database, affects other tests
    {:ok, memory} = HAL.Memory.store("test content")
    assert memory.id
  end
end
```

**Correct: Sandboxed**

```elixir
defmodule HAL.MemoryTest do
  use HAL.DataCase  # Sets up sandbox

  test "stores memory" do
    # Rolled back after test
    {:ok, memory} = HAL.Memory.store("test content")
    assert memory.id
  end
end
```

### 7.2 Mock External APIs

**Impact: HIGH (test reliability, speed)**

Don't call real AI APIs in tests. Use Mox or test doubles.

**Incorrect: Real API calls**

```elixir
test "generates embedding" do
  # Slow, costs money, can fail
  {:ok, embedding} = HAL.AI.Embeddings.generate("test")
  assert length(embedding) == 768
end
```

**Correct: Mocked**

```elixir
test "generates embedding" do
  HAL.AI.MockClient
  |> expect(:generate_embedding, fn "test" ->
    {:ok, List.duplicate(0.1, 768)}
  end)

  {:ok, embedding} = HAL.AI.Embeddings.generate("test")
  assert length(embedding) == 768
end
```

---

## 8. Error Handling

**Impact: MEDIUM**

Proper error handling prevents crashes and provides useful feedback.

### 8.1 Use Tagged Tuples

**Impact: HIGH (consistency)**

Return `{:ok, result}` or `{:error, reason}`. Never raise for expected failures.

**Incorrect: Raising on expected failure**

```elixir
def get_memory!(id) do
  case Repo.get(Memory, id) do
    nil -> raise "Memory not found"
    memory -> memory
  end
end
```

**Correct: Tagged tuples**

```elixir
def get_memory(id) do
  case Repo.get(Memory, id) do
    nil -> {:error, :not_found}
    memory -> {:ok, memory}
  end
end
```

### 8.2 Use with for Multi-Step Operations

**Impact: MEDIUM (readability)**

Chain operations with `with` for clean error handling.

**Incorrect: Nested case**

```elixir
def process_request(params) do
  case validate(params) do
    {:ok, validated} ->
      case fetch_data(validated) do
        {:ok, data} ->
          case transform(data) do
            {:ok, result} -> {:ok, result}
            {:error, e} -> {:error, e}
          end
        {:error, e} -> {:error, e}
      end
    {:error, e} -> {:error, e}
  end
end
```

**Correct: with chain**

```elixir
def process_request(params) do
  with {:ok, validated} <- validate(params),
       {:ok, data} <- fetch_data(validated),
       {:ok, result} <- transform(data) do
    {:ok, result}
  end
end
```

### 8.3 Log Errors with Context

**Impact: MEDIUM (debugging)**

Include relevant context in error logs.

**Incorrect: Bare error**

```elixir
Logger.error("Failed to process")
```

**Correct: With context**

```elixir
Logger.error("Failed to process message",
  session_id: session.id,
  message_length: String.length(message),
  error: inspect(reason)
)
```

---

## Elixir Quick Reference

### Elixir-Specific Gotchas

- **No list index access**: Use `Enum.at(list, i)` not `list[i]`
- **Immutable rebinding**: Bind `if`/`case` results to variables
- **No nested modules**: One module per file
- **Struct access**: Use `struct.field` not `struct[:field]`
- **Predicate naming**: `valid?` not `is_valid`

### HTTP Client

Always use `Req` (included in Phoenix). Never use HTTPoison, Tesla, or :httpc.

```elixir
# Correct
Req.post(url, json: body)

# Incorrect
HTTPoison.post(url, body, headers)
```

---

## Quick Reference

### Command Cheatsheet

```bash
mix compile              # Build
mix test                 # Run tests
mix phx.server           # Start server
mix ecto.migrate         # Run migrations
mix format               # Format code
mix credo --strict       # Lint
mix precommit            # Full check before commit
```

### Impact Ratings

| Rating | Meaning |
|--------|---------|
| CRITICAL | Breaking this causes major issues |
| HIGH | Significant performance/reliability impact |
| MEDIUM-HIGH | Notable improvement when followed |
| MEDIUM | Good practice, incremental benefit |
| LOW | Nice to have, minor improvement |

### Module Quick Reference

| Module | Purpose |
|--------|---------|
| `HAL.AI.AgentSDK` | Claude Agent SDK client |
| `HAL.Agents.*` | External agent delegation |
| `HAL.Memory` | Semantic memory (pgvector) |
| `HAL.AgentState` | Event sourcing |
| `HAL.Gateway` | Channel handling |

---

*Last updated: February 2026*
*Inspired by [Vercel React Best Practices](https://github.com/vercel-labs/agent-skills)*

Sources:
- [Vercel React Best Practices](https://vercel.com/blog/introducing-react-best-practices)
- [AI SDK Agent Documentation](https://sdk.vercel.ai/docs/foundations/agents)
- [Agent Skills Standard](https://agentskills.io)
