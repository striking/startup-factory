defmodule Hal.Tools.Handlers.Memory do
  @moduledoc """
  Handler for HAL memory tool operations.

  Provides Claude Code access to the semantic memory system (vector-based).
  """

  require Logger
  alias HAL.Memory
  alias Hal.Tools.Executor

  # Map old type names to new source names
  @type_to_source %{
    "preference" => "user_input",
    "fact" => "user_input",
    "decision" => "conversation",
    "knowledge" => "document"
  }

  @doc """
  Search semantic memory.

  ## Arguments

    * `args` - Map containing:
      * `"query"` - Search query string
      * `"source"` - Optional source filter (user_input, agent_output, conversation, etc.)
      * `"limit"` - Optional result limit (default: 5)
      * `"threshold"` - Optional similarity threshold (default: 0.7)
    * `opts` - Context options (user_id available but not used for global memory)

  ## Examples

      iex> Memory.search(%{"query" => "preferences"}, user_id: "uuid")
      {:ok, %{success: true, message: "Found 2 memories", result: [...]}}
  """
  @spec search(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def search(args, _opts) do
    query = Map.get(args, "query")

    if is_nil(query) do
      Executor.return_error("Missing required argument: query")
    else
      # Build options
      recall_opts = []

      recall_opts =
        if limit = Map.get(args, "limit") do
          Keyword.put(recall_opts, :limit, limit)
        else
          Keyword.put(recall_opts, :limit, 5)
        end

      recall_opts =
        if threshold = Map.get(args, "threshold") do
          Keyword.put(recall_opts, :threshold, threshold)
        else
          recall_opts
        end

      recall_opts =
        if source = Map.get(args, "source") do
          Keyword.put(recall_opts, :source, source)
        else
          recall_opts
        end

      # Execute search using new API
      case Memory.recall(query, recall_opts) do
        {:ok, results} ->
          # Format results
          formatted_results =
            Enum.map(results, fn %{memory: memory, similarity: similarity} ->
              %{
                id: memory.id,
                content: memory.content,
                source: memory.source,
                similarity: Float.round(similarity, 3),
                metadata: memory.metadata,
                created_at: memory.inserted_at
              }
            end)

          count = length(formatted_results)
          message = "Found #{count} #{pluralize("memory", count)}"

          Executor.return_success(message, formatted_results)

        {:error, reason} ->
          Executor.return_error("Memory search failed", inspect(reason))
      end
    end
  rescue
    e ->
      Logger.error("Memory search failed: #{Exception.message(e)}")
      Executor.return_error("Memory search failed", Exception.message(e))
  end

  @doc """
  Store information in semantic memory.

  ## Arguments

    * `args` - Map containing:
      * `"content"` - The information to remember
      * `"source"` - Memory source: user_input, agent_output, conversation, document, observation, system
      * `"type"` - (Legacy) Memory type: preference, fact, decision, knowledge (mapped to source)
      * `"metadata"` - Optional additional context
    * `opts` - Context options
  """
  @spec store(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def store(args, _opts) do
    content = Map.get(args, "content")

    # Support both old "type" and new "source" parameters
    source =
      case Map.get(args, "source") do
        nil ->
          # Fall back to type mapping for backward compatibility
          case Map.get(args, "type") do
            nil -> nil
            type -> Map.get(@type_to_source, type, "observation")
          end

        source ->
          source
      end

    cond do
      is_nil(content) ->
        Executor.return_error("Missing required argument: content")

      is_nil(source) ->
        Executor.return_error(
          "Missing required argument: source (or type for legacy compatibility)"
        )

      true ->
        metadata = Map.get(args, "metadata", %{})

        case Memory.store(content, source, metadata: metadata) do
          {:ok, memory} ->
            result = %{
              id: memory.id,
              content: memory.content,
              source: memory.source,
              created_at: memory.inserted_at
            }

            Executor.return_success("Memory stored successfully", result)

          {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
            errors = format_changeset_errors(changeset)
            Executor.return_error("Failed to store memory", errors)

          {:error, reason} ->
            Executor.return_error("Failed to store memory", inspect(reason))
        end
    end
  rescue
    e ->
      Logger.error("Memory store failed: #{Exception.message(e)}")
      Executor.return_error("Memory store failed", Exception.message(e))
  end

  @doc """
  Delete a memory.

  ## Arguments

    * `args` - Map containing:
      * `"memory_id"` - UUID of memory to delete
    * `opts` - Context options
  """
  @spec forget(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def forget(args, _opts) do
    memory_id = Map.get(args, "memory_id")

    if is_nil(memory_id) do
      Executor.return_error("Missing required argument: memory_id")
    else
      case Memory.forget(memory_id) do
        {:ok, _memory} ->
          Executor.return_success("Memory deleted successfully")

        {:error, :not_found} ->
          Executor.return_error("Memory not found")

        {:error, reason} ->
          Executor.return_error("Failed to delete memory", inspect(reason))
      end
    end
  rescue
    e ->
      Logger.error("Memory forget failed: #{Exception.message(e)}")
      Executor.return_error("Memory forget failed", Exception.message(e))
  end

  @doc """
  Get memory system status.

  ## Arguments

    * `args` - Map (empty, no arguments needed)
    * `opts` - Context options
  """
  @spec status(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def status(_args, _opts) do
    status_info = Memory.status()
    Executor.return_success("Memory system status", status_info)
  rescue
    e ->
      Logger.error("Memory status failed: #{Exception.message(e)}")
      Executor.return_error("Memory status failed", Exception.message(e))
  end

  # Private helpers

  defp pluralize(word, 1), do: word
  defp pluralize(word, _), do: "#{word}s"

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
