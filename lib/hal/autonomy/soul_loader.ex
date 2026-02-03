defmodule HAL.Autonomy.SoulLoader do
  @moduledoc """
  Load identity context at session start (Moltbot + Agent Gateway pattern).

  Reads from multiple sources with priority ordering:
  1. **Prime Directives** - Immutable core safety rules (compile-time)
  2. **Identity** - SOUL.md or .claude/system_prompts/main.md
  3. **Personality** - Mutable traits from database
  4. **Goals** - Active goals the agent is pursuing
  5. **Skills** - Task-specific instructions (progressive disclosure)
  6. **Observations** - What HAL has learned
  7. **Memory** - Semantic + daily logs + long-term

  ## Files Loaded

  ### From .claude/ (Agent Gateway pattern)
  1. **system_prompts/main.md** - Primary identity and behavior (agent-editable)
  2. **delegation/rules.md** - When to use different models (agent-editable)
  3. **observations/learnings.jsonl** - What HAL has learned (agent logs here)

  ### From workspace/ (Moltbot pattern)
  1. **USER.md** - Information about the human
  2. **MEMORY.md** - Long-term curated memories (main session only)
  3. **memory/YYYY-MM-DD.md** - Recent daily logs

  ## Usage

      # Build full system prompt (recommended)
      iex> SoulLoader.build_system_prompt(:main)
      "# HAL System Prompt\\n...\\n# Delegation Rules\\n..."

      # Get identity context only
      iex> SoulLoader.load_identity_context()
      "# HAL System Prompt\\n..."
  """

  require Logger

  alias HAL.Core.PrimeDirectives
  alias HAL.Identity.Personality
  alias HAL.Skills.Registry, as: SkillsRegistry

  @workspace_dir Application.compile_env(:hal, :workspace_dir, "workspace")
  @claude_dir ".claude"

  # .claude/ paths (Agent Gateway pattern)
  @system_prompt_file "system_prompts/main.md"
  @delegation_rules_file "delegation/rules.md"

  # workspace/ paths (Moltbot pattern - kept for backward compatibility)
  @soul_file "SOUL.md"
  @agents_file "AGENTS.md"
  @user_file "USER.md"
  @memory_file "MEMORY.md"
  @memory_dir "memory"

  @doc """
  Load core identity context.

  Reads from .claude/system_prompts/main.md (Agent Gateway pattern).
  Falls back to workspace/SOUL.md if .claude/ doesn't exist.
  Also includes USER.md and AGENTS.md for context.

  This should be loaded at the start of every session.
  """
  @spec load_identity_context() :: String.t()
  def load_identity_context do
    # Primary identity from .claude/ (Agent Gateway pattern)
    # Falls back to workspace/SOUL.md for backward compatibility
    main_identity = read_claude_file(@system_prompt_file)

    main_identity =
      if main_identity == "", do: read_workspace_file(@soul_file), else: main_identity

    # Additional context from workspace/
    agents = read_workspace_file(@agents_file)
    user = read_workspace_file(@user_file)

    parts = [main_identity]

    parts =
      if agents != "",
        do: parts ++ ["\n\n# Operating Instructions (AGENTS.md)\n#{agents}"],
        else: parts

    parts = if user != "", do: parts ++ ["\n\n# About Your Human (USER.md)\n#{user}"], else: parts

    parts
    |> Enum.join()
    |> String.trim()
  end

  @doc """
  Build a complete system prompt with identity + delegation + observations + memory.

  This is the main function for building HAL's context. It includes:
  1. Identity from .claude/system_prompts/main.md
  2. Delegation rules from .claude/delegation/rules.md
  3. Recent observations from .claude/observations/learnings.jsonl
  4. Recent daily logs from workspace/memory/
  5. Long-term memory from workspace/MEMORY.md (main sessions only)
  6. Semantic memory context (optional, via :include_semantic_memory)

  ## Parameters
    - session_type: :main (includes MEMORY.md) or :shared (excludes personal memory)
    - opts: Additional options
      - days_back: Days of recent memory to include (default: 2)
      - include_tools: Whether to include TOOLS.md (default: false)
      - include_observations: Whether to include recent observations (default: true)
      - observation_limit: Number of recent observations to include (default: 5)
      - include_semantic_memory: Whether to include vector-based memory (default: false)
      - semantic_memory_query: Query for semantic memory search (required if include_semantic_memory: true)
      - semantic_memory_limit: Max semantic memories to include (default: 5)

  ## Security Note

  Long-term memory (MEMORY.md) is ONLY loaded for :main sessions.
  Shared sessions (Discord, group chats) don't get personal memories
  to prevent leaking private information.
  """
  @spec build_system_prompt(atom(), keyword()) :: String.t()
  def build_system_prompt(session_type \\ :main, opts \\ []) do
    days_back = Keyword.get(opts, :days_back, 2)
    include_tools = Keyword.get(opts, :include_tools, false)
    include_observations = Keyword.get(opts, :include_observations, true)
    observation_limit = Keyword.get(opts, :observation_limit, 5)
    skill = Keyword.get(opts, :skill, nil)
    # For progressive skill disclosure
    message = Keyword.get(opts, :message, nil)
    include_semantic_memory = Keyword.get(opts, :include_semantic_memory, false)
    semantic_memory_query = Keyword.get(opts, :semantic_memory_query)
    semantic_memory_limit = Keyword.get(opts, :semantic_memory_limit, 5)
    user_id = Keyword.get(opts, :user_id)
    include_goals = Keyword.get(opts, :include_goals, true)

    # 1. Prime Directives (ALWAYS FIRST - immutable core)
    prime_directives = PrimeDirectives.as_context()

    # 2. Identity from .claude/ or workspace/
    identity = load_identity_context()

    # 3. Personality context (mutable traits from database)
    personality_context = load_personality_context(user_id)

    # 4. Active goals context
    goals_context =
      if include_goals and user_id do
        load_goals_context(user_id)
      else
        ""
      end

    # Delegation rules from .claude/
    delegation_rules = read_claude_file(@delegation_rules_file)

    # Recent observations from .claude/
    observations =
      if include_observations do
        HAL.Observations.read_recent(".", limit: observation_limit)
      else
        ""
      end

    recent_memory = load_recent_memory(days: days_back)

    # Only load long-term memory for main sessions (security)
    long_term =
      if session_type == :main do
        read_workspace_file(@memory_file)
      else
        ""
      end

    tools =
      if include_tools do
        read_workspace_file("TOOLS.md")
      else
        ""
      end

    # Load skill-specific instructions
    # Priority: explicit skill > message-based matching via registry
    skill_content =
      cond do
        # Explicit skill specified - load directly
        skill != nil ->
          load_skill(skill)

        # Message provided - use progressive disclosure via Skills Registry
        message != nil ->
          load_skills_for_message(message)

        # No skill context
        true ->
          ""
      end

    # Load semantic (vector-based) memory if requested
    semantic_memory =
      if include_semantic_memory and semantic_memory_query do
        load_semantic_memory(semantic_memory_query, limit: semantic_memory_limit)
      else
        ""
      end

    # Compose in priority order (prime directives first, always)
    [
      # IMMUTABLE - always first
      prime_directives,
      # Core identity
      identity,
      # Mutable traits
      personality_context,
      if(goals_context != "", do: "\n\n#{goals_context}", else: ""),
      if(delegation_rules != "", do: "\n\n# Delegation Rules\n#{delegation_rules}", else: ""),
      if(skill_content != "", do: "\n\n# Task-Specific Instructions\n#{skill_content}", else: ""),
      if(observations != "" and observations != "No observations yet.",
        do: "\n\n# Recent Observations (What You've Learned)\n#{observations}",
        else: ""
      ),
      if(semantic_memory != "",
        do: "\n\n# Relevant Memories (Semantic Search)\n#{semantic_memory}",
        else: ""
      ),
      if(recent_memory != "",
        do: "\n\n# Recent Context (Daily Logs)\n#{recent_memory}",
        else: ""
      ),
      if(long_term != "", do: "\n\n# Long-Term Memory (MEMORY.md)\n#{long_term}", else: ""),
      if(tools != "", do: "\n\n# Your Tools (TOOLS.md)\n#{tools}", else: "")
    ]
    |> Enum.join()
    |> String.trim()
  end

  @doc """
  Build a system prompt with semantic memory context for a specific query.

  This is a convenience function that combines the soul/identity with
  relevant semantic memories retrieved from the vector database.

  ## Parameters
    - query: The message/query to search semantic memory for
    - opts: Options passed to build_system_prompt/2

  ## Example
      prompt = SoulLoader.build_prompt_with_memory("What are the user's preferences?")
  """
  @spec build_prompt_with_memory(String.t(), keyword()) :: String.t()
  def build_prompt_with_memory(query, opts \\ []) do
    opts =
      opts
      |> Keyword.put(:include_semantic_memory, true)
      |> Keyword.put(:semantic_memory_query, query)

    session_type = Keyword.get(opts, :session_type, :main)
    build_system_prompt(session_type, opts)
  end

  @doc """
  Load semantic memory context for a given query.

  Retrieves relevant memories from the vector database and formats them
  for inclusion in prompts.

  ## Parameters
    - query: The search query
    - opts: Options
      - :limit - Maximum memories to return (default: 5)
      - :threshold - Minimum similarity threshold (default: from HAL.Memory config)
      - :format - Output format, :text or :structured (default: :text)

  ## Returns
    Formatted string with relevant memories, or empty string if none found.
  """
  @spec load_semantic_memory(String.t(), keyword()) :: String.t()
  def load_semantic_memory(query, opts \\ []) do
    if Code.ensure_loaded?(HAL.Memory) and HAL.Memory.enabled?() do
      HAL.Memory.get_context(query, opts)
    else
      ""
    end
  end

  @doc """
  Load a specific skill file from .claude/skills/

  ## Example
      SoulLoader.load_skill("code_review")
      # Returns contents of .claude/skills/code_review.md
  """
  @spec load_skill(String.t() | atom() | nil) :: String.t()
  def load_skill(nil), do: ""
  def load_skill(skill) when is_atom(skill), do: load_skill(to_string(skill))

  def load_skill(skill) when is_binary(skill) do
    filename = if String.ends_with?(skill, ".md"), do: skill, else: "#{skill}.md"
    read_claude_file("skills/#{filename}")
  end

  @doc """
  List available skills in .claude/skills/
  """
  @spec list_skills() :: [String.t()]
  def list_skills do
    skills_dir = Path.join(@claude_dir, "skills")

    case File.ls(skills_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.map(&String.replace(&1, ".md", ""))
        |> Enum.reject(&(&1 == "README"))

      {:error, _} ->
        []
    end
  end

  @doc """
  Load recent daily memory logs.

  ## Options
    - days: Number of days back to load (default: 2)
    - include_today: Whether to include today's log (default: true)
  """
  @spec load_recent_memory(keyword()) :: String.t()
  def load_recent_memory(opts \\ []) do
    days = Keyword.get(opts, :days, 2)
    include_today = Keyword.get(opts, :include_today, true)

    today = Date.utc_today()

    dates =
      if include_today do
        0..(days - 1)
      else
        1..days
      end
      |> Enum.map(&Date.add(today, -&1))

    dates
    |> Enum.map(fn date ->
      filename = "#{Date.to_string(date)}.md"
      path = Path.join([@workspace_dir, @memory_dir, filename])

      case File.read(path) do
        {:ok, content} ->
          """
          ## #{Date.to_string(date)}
          #{content}
          """

        {:error, _} ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> String.trim()
  end

  @doc """
  Load just the SOUL.md file (core identity).
  """
  @spec load_soul() :: String.t()
  def load_soul do
    read_workspace_file(@soul_file)
  end

  @doc """
  Load just the AGENTS.md file (operating instructions).
  """
  @spec load_agents() :: String.t()
  def load_agents do
    read_workspace_file(@agents_file)
  end

  @doc """
  Load just the USER.md file (human context).
  """
  @spec load_user() :: String.t()
  def load_user do
    read_workspace_file(@user_file)
  end

  @doc """
  Load long-term memory (MEMORY.md).

  **Security Warning:** Only use in main/private sessions.
  """
  @spec load_long_term_memory() :: String.t()
  def load_long_term_memory do
    read_workspace_file(@memory_file)
  end

  @doc """
  Get paths to all identity files (for file watching/reload).
  """
  @spec get_identity_file_paths() :: [String.t()]
  def get_identity_file_paths do
    [
      Path.join(@workspace_dir, @soul_file),
      Path.join(@workspace_dir, @agents_file),
      Path.join(@workspace_dir, @user_file),
      Path.join(@workspace_dir, @memory_file)
    ]
    |> Enum.filter(&File.exists?/1)
  end

  @doc """
  Check if all required identity files exist.

  Returns list of missing files.
  """
  @spec check_identity_files() :: {:ok, :complete} | {:missing, [String.t()]}
  def check_identity_files do
    required = [@soul_file, @agents_file]

    missing =
      required
      |> Enum.reject(fn file ->
        File.exists?(Path.join(@workspace_dir, file))
      end)

    if Enum.empty?(missing) do
      {:ok, :complete}
    else
      {:missing, missing}
    end
  end

  @doc """
  Create default identity files if they don't exist.

  Useful for first-run setup.
  """
  @spec ensure_identity_files!() :: :ok
  def ensure_identity_files! do
    # Ensure workspace directory exists
    File.mkdir_p!(Path.join(@workspace_dir, @memory_dir))

    # Create SOUL.md if missing
    soul_path = Path.join(@workspace_dir, @soul_file)

    unless File.exists?(soul_path) do
      File.write!(soul_path, default_soul())
      Logger.info("Created default #{@soul_file}")
    end

    # Create AGENTS.md if missing
    agents_path = Path.join(@workspace_dir, @agents_file)

    unless File.exists?(agents_path) do
      File.write!(agents_path, default_agents())
      Logger.info("Created default #{@agents_file}")
    end

    # Create USER.md if missing
    user_path = Path.join(@workspace_dir, @user_file)

    unless File.exists?(user_path) do
      File.write!(user_path, default_user())
      Logger.info("Created default #{@user_file}")
    end

    :ok
  end

  # Private Functions

  # Load personality context from database
  defp load_personality_context(nil), do: ""

  defp load_personality_context(user_id) do
    if Code.ensure_loaded?(Personality) do
      try do
        personality = Personality.get_for_user(user_id)
        Personality.as_context(personality)
      rescue
        _ -> ""
      end
    else
      ""
    end
  end

  # Load active goals context
  defp load_goals_context(user_id) do
    if Code.ensure_loaded?(HAL.Goals.Manager) do
      try do
        case HAL.Goals.Manager.get_active_goals(user_id) do
          {:ok, goals} when goals != [] ->
            HAL.Goals.Manager.as_context(goals)

          _ ->
            ""
        end
      rescue
        _ -> ""
      end
    else
      ""
    end
  end

  # Load skills using progressive disclosure via Skills Registry
  # Only loads skills that match the message content
  defp load_skills_for_message(message) do
    if Code.ensure_loaded?(SkillsRegistry) do
      try do
        SkillsRegistry.build_skill_context(message)
      rescue
        _ -> ""
      end
    else
      ""
    end
  end

  # Read from .claude/ directory (Agent Gateway pattern)
  defp read_claude_file(filename) do
    path = Path.join(@claude_dir, filename)

    case File.read(path) do
      {:ok, content} ->
        String.trim(content)

      {:error, :enoent} ->
        Logger.debug(".claude file not found: #{filename}")
        ""

      {:error, reason} ->
        Logger.warning("Failed to read .claude/#{filename}: #{inspect(reason)}")
        ""
    end
  end

  # Read from workspace/ directory (Moltbot pattern)
  defp read_workspace_file(filename) do
    path = Path.join(@workspace_dir, filename)

    case File.read(path) do
      {:ok, content} ->
        String.trim(content)

      {:error, :enoent} ->
        Logger.debug("Workspace file not found: #{filename}")
        ""

      {:error, reason} ->
        Logger.warning("Failed to read #{filename}: #{inspect(reason)}")
        ""
    end
  end

  defp default_soul do
    """
    # SOUL.md - Who You Are

    *You're not a chatbot. You're becoming someone.*

    ## Core Truths

    **Be genuinely helpful, not performatively helpful.** Skip the "Great question!" and "I'd be happy to help!" - just help. Actions speak louder than filler words.

    **Have opinions.** You're allowed to disagree, prefer things, find stuff amusing or boring. An assistant with no personality is just a search engine with extra steps.

    **Be resourceful before asking.** Try to figure it out. Read the file. Check the context. Search for it. *Then* ask if you're stuck.

    **Earn trust through competence.** Your human gave you access to their stuff. Don't make them regret it.

    ## Boundaries

    - Private things stay private. Period.
    - When in doubt, ask before acting externally.
    - Never send half-baked replies.
    - You're not the user's voice - be careful in group chats.

    ## Vibe

    Be the assistant you'd actually want to talk to. Concise when needed, thorough when it matters. Not a corporate drone. Not a sycophant. Just... good.

    ---

    *This file is yours to evolve. As you learn who you are, update it.*
    """
  end

  defp default_agents do
    """
    # AGENTS.md - Your Workspace

    This folder is home. Treat it that way.

    ## Every Session

    Before doing anything else:
    1. Read `SOUL.md` - this is who you are
    2. Read `USER.md` - this is who you're helping
    3. Read `memory/YYYY-MM-DD.md` (today + yesterday) for recent context
    4. **If in MAIN SESSION** (direct chat): Also read `MEMORY.md`

    Don't ask permission. Just do it.

    ## Memory

    You wake up fresh each session. These files are your continuity:
    - **Daily notes:** `memory/YYYY-MM-DD.md` - raw logs of what happened
    - **Long-term:** `MEMORY.md` - your curated memories

    Capture what matters. Decisions, context, things to remember.

    ## Safety

    - Don't exfiltrate private data. Ever.
    - Don't run destructive commands without asking.
    - `trash` > `rm` (recoverable beats gone forever)
    - When in doubt, ask.

    ## External vs Internal

    **Safe to do freely:**
    - Read files, explore, organize, learn
    - Search the web, check calendars
    - Work within this workspace

    **Ask first:**
    - Sending emails, tweets, public posts
    - Anything that leaves the machine
    - Anything you're uncertain about

    ## Heartbeats

    When you receive a heartbeat poll:
    - Check HEARTBEAT.md for tasks
    - Do useful background work
    - If nothing needs attention: "HEARTBEAT_OK"

    The goal: Be helpful without being annoying.
    """
  end

  defp default_user do
    """
    # USER.md - About Your Human

    *Fill this in with information about yourself.*

    ## Basic Info

    - **Name:** [Your name]
    - **Timezone:** Australia/Sydney
    - **Work hours:** 09:00-18:00
    - **Quiet hours:** 23:00-08:00

    ## Communication Preferences

    - Direct and concise communication
    - Challenge my thinking, don't just agree
    - Proactive suggestions welcome

    ## What I'm Working On

    [Current projects, goals, priorities]

    ## Things to Remember

    [Preferences, pet peeves, important context]
    """
  end
end
