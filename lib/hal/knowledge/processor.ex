defmodule Hal.Knowledge.Processor do
  @moduledoc """
  Processes documents into chunks and stores them in the memory system.

  Handles:
  - Text extraction from various formats (PDF, MD, TXT)
  - Intelligent chunking with overlap
  - Embedding generation for each chunk
  - Storage in pgvector via Memory system
  """

  require Logger

  alias Hal.Knowledge.{Document, DocumentChunk}
  alias HAL.Memory

  # Chunking configuration
  # characters
  @default_chunk_size 1000
  # characters
  @default_chunk_overlap 200
  @max_chunk_size 2000

  @doc """
  Processes a document from raw content.

  Extracts text, chunks it, generates embeddings, and stores in memory.
  """
  @spec process(binary(), keyword()) :: {:ok, Document.t()} | {:error, term()}
  def process(document_id, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    chunk_overlap = Keyword.get(opts, :chunk_overlap, @default_chunk_overlap)

    with {:ok, doc} <- get_document(document_id),
         {:ok, doc} <- mark_processing(doc),
         {:ok, text} <- extract_text(doc),
         {:ok, chunks} <- chunk_text(text, chunk_size, chunk_overlap),
         {:ok, doc} <- store_chunks(doc, chunks) do
      mark_completed(doc, length(chunks))
    else
      {:error, reason} = error ->
        mark_failed(document_id, reason)
        error
    end
  end

  @doc """
  Extracts text from a document based on its content type.
  """
  @spec extract_text(Document.t()) :: {:ok, String.t()} | {:error, term()}
  def extract_text(%Document{raw_content: content}) when is_binary(content) and content != "" do
    {:ok, content}
  end

  def extract_text(%Document{content_type: "application/pdf"} = doc) do
    # PDF extraction - would use a library like pdf_text or external tool
    # For now, we expect raw_content to be populated by the upload handler
    case doc.raw_content do
      nil -> {:error, :no_content}
      content -> {:ok, content}
    end
  end

  def extract_text(%Document{content_type: type})
      when type in ["text/plain", "text/markdown", "text/html"] do
    # Plain text types - raw_content should be populated
    {:error, :no_content}
  end

  def extract_text(_doc) do
    {:error, :unsupported_format}
  end

  @doc """
  Chunks text into overlapping segments for better semantic search.

  Uses a sliding window approach with configurable chunk size and overlap.
  Attempts to break at sentence boundaries when possible.
  """
  @spec chunk_text(String.t(), integer(), integer()) :: {:ok, [map()]} | {:error, term()}
  def chunk_text(text, chunk_size, overlap) when chunk_size > overlap do
    text = String.trim(text)

    if String.length(text) == 0 do
      {:error, :empty_content}
    else
      chunks = do_chunk(text, chunk_size, overlap, 0, [])
      {:ok, Enum.reverse(chunks)}
    end
  end

  def chunk_text(_, _, _), do: {:error, :invalid_chunk_params}

  # Private chunking implementation

  defp do_chunk(text, chunk_size, overlap, start_pos, acc) do
    remaining = String.slice(text, start_pos, String.length(text))

    if String.length(remaining) <= chunk_size do
      # Last chunk
      if String.length(String.trim(remaining)) > 0 do
        chunk = %{
          content: String.trim(remaining),
          start_char: start_pos,
          end_char: start_pos + String.length(remaining),
          index: length(acc)
        }

        [chunk | acc]
      else
        acc
      end
    else
      # Find a good break point (sentence boundary)
      chunk_text_raw = String.slice(text, start_pos, min(chunk_size + 100, @max_chunk_size))
      break_point = find_break_point(chunk_text_raw, chunk_size)

      chunk_content = String.slice(text, start_pos, break_point) |> String.trim()

      chunk = %{
        content: chunk_content,
        start_char: start_pos,
        end_char: start_pos + break_point,
        index: length(acc)
      }

      # Move forward by chunk_size - overlap
      next_pos = start_pos + max(break_point - overlap, 1)
      do_chunk(text, chunk_size, overlap, next_pos, [chunk | acc])
    end
  end

  defp find_break_point(text, target_size) do
    # Try to find a sentence boundary near the target size
    candidates = [
      # Look for sentence endings
      find_last_pattern(text, ~r/[.!?]\s+/, target_size),
      # Look for paragraph breaks
      find_last_pattern(text, ~r/\n\n/, target_size),
      # Look for line breaks
      find_last_pattern(text, ~r/\n/, target_size),
      # Fall back to target size
      target_size
    ]

    # Pick the closest to target that's not nil
    candidates
    |> Enum.reject(&is_nil/1)
    # At least 70% of target
    |> Enum.filter(&(&1 > target_size * 0.7))
    |> Enum.min_by(&abs(&1 - target_size), fn -> target_size end)
  end

  defp find_last_pattern(text, pattern, max_pos) do
    search_text = String.slice(text, 0, max_pos + 50)

    case Regex.scan(pattern, search_text, return: :index) do
      [] ->
        nil

      matches ->
        matches
        |> List.flatten()
        |> Enum.map(fn {pos, len} -> pos + len end)
        |> Enum.filter(&(&1 <= max_pos + 50))
        |> Enum.max(fn -> nil end)
    end
  end

  # Document processing helpers

  defp get_document(document_id) do
    case Document.get(document_id) do
      nil -> {:error, :not_found}
      doc -> {:ok, doc}
    end
  end

  defp mark_processing(doc) do
    Document.update_status(doc.id, "processing")
  end

  defp mark_completed(doc, chunk_count) do
    Document.update_status(doc.id, "completed", chunk_count: chunk_count)
  end

  defp mark_failed(document_id, reason) do
    Document.update_status(document_id, "failed", error: inspect(reason))
  end

  defp store_chunks(doc, chunks) do
    Logger.info("Storing #{length(chunks)} chunks for document #{doc.id}")

    results =
      chunks
      |> Enum.map(fn chunk ->
        store_single_chunk(doc, chunk)
      end)

    failures = Enum.filter(results, &match?({:error, _}, &1))

    if length(failures) > 0 do
      Logger.warning("#{length(failures)} chunks failed to store")
    end

    {:ok, doc}
  end

  defp store_single_chunk(doc, chunk) do
    # Build metadata for citation
    metadata = %{
      document_id: doc.id,
      document_title: doc.title,
      chunk_index: chunk.index,
      start_char: chunk.start_char,
      end_char: chunk.end_char
    }

    # Store in memory system (handles embedding generation)
    case Memory.store(chunk.content, "document", metadata: metadata) do
      {:ok, memory} ->
        # Create chunk record linking document to memory
        DocumentChunk.create(%{
          document_id: doc.id,
          memory_id: memory.id,
          chunk_index: chunk.index,
          start_char: chunk.start_char,
          end_char: chunk.end_char
        })

      {:error, reason} ->
        Logger.error("Failed to store chunk #{chunk.index}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
