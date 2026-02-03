# HAL Memory Architecture

**Last Updated:** 2026-01-29
**Status:** ✅ Implemented

---

## Overview

HAL implements a 4-tier memory system combining short-term conversation context with long-term semantic memory for personalized AI assistance. This architecture enables HAL to:

- Remember user preferences across sessions
- Learn from past interactions
- Provide personalized responses based on context
- Build long-term understanding of user needs

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    4-Tier Memory System                     │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Tier 1: Working Memory (GenServer State)                   │
│ ├─ Last 10-20 messages                                      │
│ ├─ Current conversation context                            │
│ ├─ Lifetime: Single conversation turn                      │
│ └─ Purpose: Immediate context for AI                       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Tier 2: Session Cache (PostgreSQL)                         │
│ ├─ Full conversation history                               │
│ ├─ Sessions and messages tables                            │
│ ├─ Lifetime: Active session (30 min)                       │
│ └─ Purpose: Conversation continuity, state recovery        │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Tier 3: Semantic Memory (pgvector)                         │
│ ├─ User preferences, learned facts                         │
│ ├─ 1536-dimensional embeddings (OpenAI ada-002)           │
│ ├─ Cosine similarity search                                │
│ ├─ Lifetime: Permanent (cross-session)                     │
│ └─ Purpose: Long-term personalization                      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Tier 4: Structured Memory (PostgreSQL)                     │
│ ├─ Relational tables (users, tasks, calendar, etc.)       │
│ ├─ Queryable by attributes                                 │
│ ├─ Lifetime: Permanent                                     │
│ └─ Purpose: Structured data (tasks, contacts, etc.)        │
└─────────────────────────────────────────────────────────────┘
```

---

## Tier 1: Working Memory (GenServer State)

### Purpose
Immediate conversation context for the current AI interaction.

### Storage
In-memory GenServer state within `HAL.Gateway.SessionServer`.

### Lifetime
Current conversation turn (cleared after AI response).

### Size
Last 10-20 messages (configurable).

### Use Cases
- Provide recent context to AI
- Track conversation flow
- Handle follow-up questions

### Implementation
```elixir
defmodule HAL.Gateway.SessionServer do
  defstruct [
    :id,
    :user_id,
    :channel,
    :messages,  # Last N messages in memory
    :last_activity
  ]
end
```

---

## Tier 2: Session Cache (PostgreSQL)

### Purpose
Full conversation history for session continuity and recovery.

### Storage
PostgreSQL tables: `sessions` and `messages`.

### Lifetime
Active session (auto-terminates after 30 minutes of inactivity).

### Size
Full conversation history (all messages).

### Use Cases
- Recover session state after restart
- Load conversation history
- Provide context window to AI
- Track session metadata

### Schema
```sql
CREATE TABLE sessions (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  channel VARCHAR(50) NOT NULL,
  channel_user_id VARCHAR(255) NOT NULL,
  status VARCHAR(20) DEFAULT 'active',
  last_message_at TIMESTAMP,
  inserted_at TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE TABLE messages (
  id UUID PRIMARY KEY,
  session_id UUID NOT NULL REFERENCES sessions(id),
  role VARCHAR(20) NOT NULL,  -- 'user' or 'assistant'
  content TEXT NOT NULL,
  metadata JSONB,
  inserted_at TIMESTAMP
);
```

---

## Tier 3: Semantic Memory (pgvector)

### Purpose
Long-term semantic memory for user preferences, learned facts, and past decisions.

### Storage
PostgreSQL table `user_memories` with pgvector extension.

### Lifetime
Permanent (cross-session, cross-channel).

### Size
Unlimited (searchable by semantic similarity).

### Search Method
Cosine similarity on 1536-dimensional embeddings (OpenAI ada-002).

### Use Cases
- Remember user preferences ("I prefer Python over JavaScript")
- Recall past decisions ("We decided to use Tailwind CSS")
- Personalize responses based on learned context
- Build long-term user understanding

### Schema
```sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE user_memories (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  content TEXT NOT NULL,
  embedding vector(1536) NOT NULL,
  category VARCHAR(50),
  importance INTEGER DEFAULT 5,
  metadata JSONB,
  inserted_at TIMESTAMP,
  updated_at TIMESTAMP
);

-- IVFFlat index for fast similarity search
CREATE INDEX user_memories_embedding_idx
  ON user_memories
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);
```

### API Reference

#### HAL.Memory.remember/4
Store a new memory with automatic embedding generation.

```elixir
HAL.Memory.remember(
  user_id,
  "User prefers dark mode for all applications",
  category: "preference",
  importance: 8,
  metadata: %{domain: "ui", context: "settings"}
)
```

**Parameters:**
- `user_id` (UUID) - User to associate memory with
- `content` (String) - Text content to remember
- `opts` (Keyword) - Optional metadata
  - `:category` - Category tag (e.g., "preference", "decision", "fact")
  - `:importance` - 1-10 scale (default: 5)
  - `:metadata` - Additional JSON metadata

**Returns:** `{:ok, memory}` or `{:error, reason}`

#### HAL.Memory.recall/3
Semantic similarity search for relevant memories.

```elixir
HAL.Memory.recall(
  user_id,
  "What are my UI preferences?",
  limit: 5
)
```

**Parameters:**
- `user_id` (UUID) - User to search memories for
- `query` (String) - Natural language query
- `opts` (Keyword) - Search options
  - `:limit` - Max results (default: 10)
  - `:min_similarity` - Threshold 0.0-1.0 (default: 0.7)

**Returns:** `{:ok, [memory]}` - List of memories with similarity scores

#### HAL.Memory.search/4
Hybrid search combining semantic similarity with metadata filters.

```elixir
HAL.Memory.search(
  user_id,
  "coding preferences",
  filters: %{category: "preference", importance: [gte: 7]},
  limit: 5
)
```

**Parameters:**
- `user_id` (UUID) - User to search memories for
- `query` (String) - Natural language query
- `filters` (Map) - PostgreSQL WHERE conditions
- `opts` (Keyword) - Search options

**Returns:** `{:ok, [memory]}`

#### HAL.Memory.forget/1
Delete a specific memory by ID.

```elixir
HAL.Memory.forget(memory_id)
```

**Parameters:**
- `memory_id` (UUID) - ID of memory to delete

**Returns:** `{:ok, memory}` or `{:error, reason}`

#### HAL.Memory.get_recent/2
Get recent memories for context loading (no embeddings needed).

```elixir
HAL.Memory.get_recent(user_id, limit: 10)
```

**Parameters:**
- `user_id` (UUID) - User to get memories for
- `opts` (Keyword) - Options
  - `:limit` - Max results (default: 20)

**Returns:** `{:ok, [memory]}`

---

## Tier 4: Structured Memory (PostgreSQL)

### Purpose
Structured relational data queryable by attributes.

### Storage
PostgreSQL tables (users, tasks, calendar, contacts, etc.).

### Lifetime
Permanent.

### Size
Unlimited (queryable by SQL).

### Use Cases
- Task management
- Calendar events
- Contact information
- Project data
- Structured queries

### Example Tables
```sql
CREATE TABLE tasks (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  title VARCHAR(255) NOT NULL,
  description TEXT,
  status VARCHAR(20) DEFAULT 'pending',
  due_date DATE,
  priority INTEGER,
  inserted_at TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE TABLE calendar_events (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  title VARCHAR(255) NOT NULL,
  start_time TIMESTAMP NOT NULL,
  end_time TIMESTAMP NOT NULL,
  location VARCHAR(255),
  description TEXT,
  inserted_at TIMESTAMP
);
```

---

## Integration Examples

### Example 1: Load Context for AI Request

```elixir
defmodule HAL.Gateway.SessionServer do
  def handle_call({:prompt, message}, _from, state) do
    # Tier 1: Recent messages from working memory
    recent_messages = Enum.take(state.messages, -10)

    # Tier 2: Full conversation history from session cache
    {:ok, session_messages} = HAL.Sessions.get_messages(state.id)

    # Tier 3: Relevant semantic memories
    {:ok, memories} = HAL.Memory.recall(state.user_id, message, limit: 5)

    # Tier 4: Structured data (tasks due today)
    {:ok, tasks} = HAL.Tasks.list_due_today(state.user_id)

    # Build context for AI
    context = %{
      recent_messages: recent_messages,
      relevant_memories: memories,
      tasks_due_today: tasks
    }

    # Send to AI with enriched context
    {:ok, response} = HAL.AI.Router.route(message, context)

    {:reply, response, state}
  end
end
```

### Example 2: Heartbeat Uses Memory

```elixir
defmodule HAL.Heartbeat do
  def check_for_work do
    # Check if we can work autonomously (no active user sessions)
    if can_work_autonomously?() do
      # Call Claude Code with autonomous worker prompt
      # Claude will access memory to understand context
      Hal.AI.ClaudeCode.prompt(
        "heartbeat-#{timestamp}",
        """
        You are HAL's autonomous worker. Review memory, todos, and projects.

        Find valuable background work you can do:
        - Research topics for upcoming work
        - Organize information
        - Prepare summaries
        - Update documentation

        If nothing to do: Return "No work needed"
        If you find work: Do it and update memory with findings.
        """
      )

      # Claude autonomously decides the workflow
      # No structured action types needed
      :ok
    else
      # User is active, skip
      :skip
    end
  end
end
```

### Example 3: Learn from User Interaction

```elixir
defmodule HAL.Gateway.SessionServer do
  def handle_cast({:store_preference, preference}, state) do
    # Extract important facts to remember
    case extract_learnable_facts(preference) do
      {:ok, facts} ->
        Enum.each(facts, fn fact ->
          HAL.Memory.remember(
            state.user_id,
            fact.content,
            category: fact.category,
            importance: fact.importance,
            metadata: %{
              source: "conversation",
              session_id: state.id,
              timestamp: DateTime.utc_now()
            }
          )
        end)

      :no_facts ->
        :ok
    end

    {:noreply, state}
  end

  defp extract_learnable_facts(message) do
    # Use AI to extract facts worth remembering
    # e.g., "I prefer Python" -> {:ok, [%{content: "User prefers Python", ...}]}
    HAL.AI.extract_facts(message)
  end
end
```

---

## Memory Lifecycle

### 1. Memory Creation
```
User message → AI response → Extract facts → Generate embedding → Store in pgvector
```

### 2. Memory Retrieval
```
User query → Generate query embedding → Cosine similarity search → Return top K matches
```

### 3. Memory Updates
```
New information → Search for existing memory → Update or create new → Re-embed if changed
```

### 4. Memory Cleanup
```
Scheduled job → Find low-importance old memories → Archive or delete
```

---

## Performance Characteristics

### Embedding Generation
- **Latency:** ~200ms per embedding (OpenAI API)
- **Batching:** Can batch multiple texts in single API call
- **Caching:** Embeddings cached in database

### Similarity Search
- **Index:** IVFFlat index for approximate nearest neighbor
- **Latency:** < 50ms for 10K memories
- **Scalability:** Sub-linear with proper indexing

### Memory Overhead
- **Tier 1:** ~1KB per session (in-memory)
- **Tier 2:** ~10KB per session (database)
- **Tier 3:** ~6KB per memory (1536 floats)
- **Total:** Minimal impact on system resources

---

## Future Enhancements

### Planned Features
- [ ] Automatic fact extraction from conversations
- [ ] Memory consolidation (merge similar memories)
- [ ] Importance decay over time
- [ ] Memory categories (preferences, decisions, facts, relationships)
- [ ] Cross-user memory (shared knowledge)
- [ ] Memory visualization in dashboard
- [ ] Export/import memories

### Research Directions
- [ ] Hierarchical memory (parent-child relationships)
- [ ] Temporal reasoning (time-aware memory)
- [ ] Conflict resolution (contradictory memories)
- [ ] Privacy controls (memory access levels)
- [ ] Federated memory (across devices)

---

## Best Practices

### When to Remember
✅ **DO remember:**
- User preferences ("I like dark mode")
- Important decisions ("We chose PostgreSQL")
- Personal facts ("I work at Anthropic")
- Project context ("Working on HAL project")

❌ **DON'T remember:**
- Temporary information ("It's raining today")
- Transient state ("Currently debugging")
- Sensitive data (use metadata encryption)
- Redundant information (already stored elsewhere)

### Memory Categories
- `preference` - User likes/dislikes
- `decision` - Project/product decisions
- `fact` - Factual information
- `relationship` - Connections between entities
- `skill` - User capabilities
- `goal` - User objectives
- `context` - Project/domain context

### Importance Scoring
- **9-10:** Critical (identity, core preferences)
- **7-8:** High (frequent decisions, key facts)
- **5-6:** Medium (useful context)
- **3-4:** Low (nice to have)
- **1-2:** Minimal (archival)

---

## Troubleshooting

### Common Issues

#### Slow Similarity Search
**Symptom:** Queries take > 500ms
**Solution:**
1. Rebuild IVFFlat index with more lists
2. Increase `work_mem` in PostgreSQL
3. Add filters to reduce search space

#### Memory Bloat
**Symptom:** Too many low-value memories
**Solution:**
1. Run periodic cleanup job
2. Archive memories with importance < 3
3. Delete memories older than 1 year

#### Embedding API Failures
**Symptom:** Cannot store new memories
**Solution:**
1. Implement retry logic with exponential backoff
2. Queue embeddings for async processing
3. Fall back to keyword search

---

## References

- [pgvector Documentation](https://github.com/pgvector/pgvector)
- [OpenAI Embeddings API](https://platform.openai.com/docs/guides/embeddings)
- [Cosine Similarity](https://en.wikipedia.org/wiki/Cosine_similarity)
- [IVFFlat Index](https://github.com/pgvector/pgvector#ivfflat)

---

**Status:** ✅ Production-ready
**Version:** 1.0.0
**Last Updated:** 2026-01-29
