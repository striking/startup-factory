defmodule Hal.Commands do
  @moduledoc """
  Natural language command detection and execution.

  Uses Claude to understand user intent and execute appropriate actions:
  - "Create a habit for morning meditation" → Habits.create
  - "Upload this document" → Knowledge.upload
  - "Show my tasks" → Tasks.list
  - "Search my notes for project ideas" → Knowledge.search
  - "Complete my exercise habit" → Habits.complete
  - "What habits do I have?" → Habits.list

  ## How It Works

  1. Message comes in
  2. We ask Claude if this is a command (not just conversation)
  3. If command detected, extract intent + parameters
  4. Execute the appropriate function
  5. Return formatted response

  ## Usage

      case Commands.maybe_execute(user_id, "create a daily habit for reading") do
        {:executed, response} -> send_response(response)
        {:not_command, _} -> route_to_ai(message)
      end
  """

  require Logger

  alias Hal.AI.Gemini
  alias Hal.Habits
  alias Hal.Tasks
  alias Hal.Knowledge

  @doc """
  Attempts to execute a command from natural language.

  Returns:
  - `{:executed, response}` - Command was detected and executed
  - `{:not_command, message}` - Not a command, pass to AI
  """
  @spec maybe_execute(binary(), String.t()) ::
          {:executed, String.t()} | {:not_command, String.t()}
  def maybe_execute(user_id, message) do
    case detect_intent(message) do
      {:ok, %{is_command: true, intent: intent, params: params}} ->
        result = execute_command(user_id, intent, params, message)
        {:executed, result}

      {:ok, %{is_command: false}} ->
        {:not_command, message}

      {:error, _reason} ->
        # On detection failure, treat as not a command
        {:not_command, message}
    end
  end

  @doc """
  Uses AI to detect if message is a command and extract intent.
  """
  @spec detect_intent(String.t()) :: {:ok, map()} | {:error, term()}
  def detect_intent(message) do
    prompt = """
    Analyze if this message is a COMMAND (action request) or just CONVERSATION.

    Commands are requests to DO something specific:
    - Create/add/start something (habit, task, document)
    - Complete/finish/done something
    - Show/list/search something
    - Delete/remove/cancel something

    Conversation is chat, questions, discussion that needs AI response.

    Message: "#{String.slice(message, 0, 500)}"

    Respond with JSON only:
    {
      "is_command": true/false,
      "intent": "create_habit|complete_habit|list_habits|create_task|list_tasks|upload_document|search_knowledge|show_stats|none",
      "params": {
        "name": "extracted name if any",
        "query": "search query if any",
        "frequency": "daily/weekly/custom if habit",
        "category": "category if specified"
      },
      "confidence": "high/medium/low"
    }
    """

    case Gemini.prompt(nil, prompt, stream: false, max_tokens: 200) do
      {:ok, response, _session_id} ->
        parse_intent_response(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_intent_response(response) do
    case Regex.run(~r/\{[\s\S]*\}/s, response) do
      [json | _] ->
        case Jason.decode(json) do
          {:ok, data} ->
            {:ok,
             %{
               is_command: data["is_command"] == true,
               intent: String.to_atom(data["intent"] || "none"),
               params: data["params"] || %{},
               confidence: data["confidence"] || "low"
             }}

          {:error, _} ->
            {:error, :parse_failed}
        end

      nil ->
        {:error, :no_json}
    end
  end

  # Command Execution

  defp execute_command(user_id, intent, params, original_message) do
    case intent do
      :create_habit -> create_habit(user_id, params)
      :complete_habit -> complete_habit(user_id, params, original_message)
      :list_habits -> list_habits(user_id)
      :create_task -> create_task(user_id, params, original_message)
      :list_tasks -> list_tasks(user_id)
      :search_knowledge -> search_knowledge(user_id, params)
      :show_stats -> show_stats(user_id)
      :upload_document -> upload_document_hint()
      _ -> "I understood that as a command but I'm not sure how to help. Try being more specific?"
    end
  end

  # Habit Commands

  defp create_habit(user_id, params) do
    name = params["name"]

    if is_nil(name) or name == "" do
      "I'd love to help you create a habit! What should I call it? For example: 'Create a habit called Morning Meditation'"
    else
      attrs = %{
        name: name,
        frequency: params["frequency"] || "daily",
        category: params["category"]
      }

      case Habits.create(user_id, attrs) do
        {:ok, habit} ->
          freq = habit.frequency

          "✅ Created habit: **#{habit.name}** (#{freq})\n\nI'll help you track this. Say 'done with #{habit.name}' when you complete it!"

        {:error, changeset} ->
          "Couldn't create that habit: #{inspect(changeset.errors)}"
      end
    end
  end

  defp complete_habit(user_id, params, message) do
    name = params["name"]

    # Find habit by name (fuzzy match)
    habits = Habits.list(user_id)

    habit =
      if name do
        Enum.find(habits, fn h ->
          String.contains?(String.downcase(h.name), String.downcase(name))
        end)
      else
        # Try to find from message
        Enum.find(habits, fn h ->
          String.contains?(String.downcase(message), String.downcase(h.name))
        end)
      end

    cond do
      is_nil(habit) and length(habits) == 0 ->
        "You don't have any habits yet. Create one first!"

      is_nil(habit) ->
        habit_names = Enum.map(habits, & &1.name) |> Enum.join(", ")
        "Which habit did you complete? Your habits: #{habit_names}"

      Habits.completed_today?(habit.id) ->
        "You already completed **#{habit.name}** today! 🎉"

      true ->
        case Habits.complete(habit.id) do
          {:ok, _completion} ->
            # Refresh for updated streak
            habit = Habits.get(habit.id)

            streak_msg =
              if habit.current_streak > 1, do: " #{habit.current_streak} day streak! 🔥", else: ""

            "✅ Completed **#{habit.name}**!#{streak_msg}"

          {:error, _} ->
            "Something went wrong completing that habit."
        end
    end
  end

  defp list_habits(user_id) do
    progress = Habits.today_progress(user_id)

    if progress.total_due == 0 do
      # All habits
      habits = Habits.list(user_id, status: nil)

      if length(habits) == 0 do
        "You don't have any habits yet. Create one with 'create a habit for [name]'"
      else
        "No habits due today. You have #{length(habits)} habit(s) total."
      end
    else
      lines =
        Enum.map(progress.habits, fn h ->
          status = if h.completed, do: "✅", else: "⬜"
          streak = if h.current_streak > 0, do: " (#{h.current_streak}🔥)", else: ""
          "#{status} #{h.name}#{streak}"
        end)

      header = "**Today's Habits** (#{progress.completed}/#{progress.total_due})\n"
      header <> Enum.join(lines, "\n")
    end
  end

  # Task Commands

  defp create_task(user_id, params, original_message) do
    # Extract the actual task request from the message
    request = params["name"] || original_message

    case Tasks.create(user_id, request) do
      {:ok, task} ->
        steps = length(task.steps)

        "✅ Created task: **#{task.title}**\n\nBroken into #{steps} steps. I'll work on it and update you on progress."

      {:error, reason} ->
        "Couldn't create that task: #{inspect(reason)}"
    end
  end

  defp list_tasks(user_id) do
    running = Tasks.list(user_id, status: "running")
    pending = Tasks.list(user_id, status: "pending")
    completed = Tasks.list(user_id, status: "completed") |> Enum.take(3)

    lines = []

    lines =
      if length(running) > 0 do
        running_items =
          Enum.map(running, fn t ->
            progress = Tasks.AutoTask.progress(t)
            "  🔄 #{t.title} (#{progress}%)"
          end)

        lines ++ ["**Running:**"] ++ running_items
      else
        lines
      end

    lines =
      if length(pending) > 0 do
        pending_items = Enum.map(pending, fn t -> "  ⏳ #{t.title}" end)
        lines ++ ["**Pending:**"] ++ pending_items
      else
        lines
      end

    lines =
      if length(completed) > 0 do
        completed_items = Enum.map(completed, fn t -> "  ✅ #{t.title}" end)
        lines ++ ["**Recently Completed:**"] ++ completed_items
      else
        lines
      end

    if length(lines) == 0 do
      "No active tasks. Create one with 'run a task to [do something]'"
    else
      Enum.join(lines, "\n")
    end
  end

  # Knowledge Commands

  defp search_knowledge(user_id, params) do
    query = params["query"]

    if is_nil(query) or query == "" do
      "What would you like to search for in your knowledge base?"
    else
      case Knowledge.search(user_id, query, limit: 5) do
        {:ok, []} ->
          "No results found for '#{query}'. Your knowledge base might be empty or the query didn't match."

        {:ok, results} ->
          formatted =
            Enum.map(results, fn r ->
              source = r.source.title
              snippet = String.slice(r.content, 0, 150) <> "..."
              "**#{source}**\n#{snippet}"
            end)
            |> Enum.join("\n\n---\n\n")

          "Found #{length(results)} result(s) for '#{query}':\n\n#{formatted}"

        {:error, reason} ->
          "Search failed: #{inspect(reason)}"
      end
    end
  end

  defp upload_document_hint do
    """
    To upload a document, use the Knowledge API:

    ```elixir
    Knowledge.upload_file(user_id, "/path/to/file.pdf")
    ```

    Or via the web interface (coming soon!).

    I can help you search and query documents once they're uploaded.
    """
  end

  # Stats Command

  defp show_stats(user_id) do
    habit_count = length(Habits.list(user_id))
    habit_progress = Habits.today_progress(user_id)
    knowledge_stats = Knowledge.stats(user_id)
    task_count = length(Tasks.list(user_id))

    """
    **Your HAL Stats**

    📊 **Habits**
    - #{habit_count} total habits
    - Today: #{habit_progress.completed}/#{habit_progress.total_due} completed

    📚 **Knowledge Base**
    - #{knowledge_stats.total_documents} documents
    - #{knowledge_stats.total_chunks} searchable chunks

    ⚡ **Tasks**
    - #{task_count} autonomous task(s)

    Keep building! 🚀
    """
  end
end
