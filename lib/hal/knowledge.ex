defmodule Hal.Knowledge do
  @moduledoc """
  Knowledge base system for HAL - your second brain.

  Allows uploading documents (PDF, Markdown, plain text) which are then:
  1. Parsed and text-extracted
  2. Chunked into semantic segments
  3. Embedded and stored in pgvector
  4. Searchable via semantic similarity

  ## Usage

      # Upload a document
      {:ok, doc} = Knowledge.upload(user_id, %{
        title: "My Notes",
        content: "# Chapter 1\\n\\nThis is my notes...",
        content_type: "text/markdown",
        tags: ["notes", "work"]
      })

      # Search your knowledge base
      {:ok, results} = Knowledge.search(user_id, "what are the key points?")

      # Get results with citations
      results
      |> Enum.map(fn r ->
        "\#{r.content} (Source: \#{r.source.title})"
      end)

  ## Supported Formats

  - `text/plain` - Plain text files
  - `text/markdown` - Markdown documents
  - `application/pdf` - PDF files (requires text layer)

  ## Citations

  Each search result includes source information for citations:
  - Document title
  - Page number (if applicable)
  - Character position in original document
  """

  require Logger

  alias Hal.Knowledge.{Document, DocumentChunk, Processor}
  alias HAL.Memory

  @doc """
  Uploads and processes a document.

  ## Options

    * `:title` - Document title (required)
    * `:content` - Raw text content
    * `:content_type` - MIME type (default: "text/plain")
    * `:filename` - Original filename
    * `:tags` - List of tags for organization
    * `:category` - Category for grouping
    * `:async` - Process asynchronously (default: true)

  ## Examples

      Knowledge.upload(user_id, %{
        title: "Meeting Notes",
        content: "Discussion about Q4 goals...",
        tags: ["meetings", "q4"]
      })
  """
  @spec upload(binary(), map()) :: {:ok, Document.t()} | {:error, term()}
  def upload(user_id, attrs) do
    async = Map.get(attrs, :async, true)

    with {:ok, doc} <- create_document(user_id, attrs) do
      if async do
        # Process in background
        schedule_processing(doc.id)
        {:ok, doc}
      else
        # Process synchronously
        Processor.process(doc.id)
      end
    end
  end

  @doc """
  Uploads a document from a file path.
  """
  @spec upload_file(binary(), String.t(), keyword()) :: {:ok, Document.t()} | {:error, term()}
  def upload_file(user_id, file_path, opts \\ []) do
    with {:ok, content} <- File.read(file_path) do
      filename = Path.basename(file_path)
      title = Keyword.get(opts, :title, filename)
      content_type = Keyword.get(opts, :content_type, detect_content_type(file_path))
      tags = Keyword.get(opts, :tags, [])

      upload(user_id, %{
        title: title,
        content: content,
        content_type: content_type,
        filename: filename,
        tags: tags,
        file_size: byte_size(content)
      })
    end
  end

  @doc """
  Searches the knowledge base using semantic similarity.

  Returns relevant chunks with their source documents for citation.

  ## Options

    * `:limit` - Maximum results (default: 10)
    * `:threshold` - Minimum similarity score (default: 0.5)
    * `:category` - Filter by document category
    * `:tags` - Filter by document tags (any match)
  """
  @spec search(binary(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def search(user_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    threshold = Keyword.get(opts, :threshold, 0.5)

    # Search memory system for document source
    case Memory.recall(query, limit: limit * 2, threshold: threshold, source: "document") do
      {:ok, results} ->
        # Enrich with document information
        enriched =
          results
          |> Enum.map(&enrich_with_source/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.filter(fn r -> r.source.user_id == user_id end)
          |> Enum.take(limit)

        {:ok, enriched}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets context from the knowledge base for prompt injection.

  Returns formatted text suitable for including in an AI prompt.
  """
  @spec get_context(binary(), String.t(), keyword()) :: String.t()
  def get_context(user_id, query, opts \\ []) do
    max_chars = Keyword.get(opts, :max_chars, 4000)

    case search(user_id, query, limit: 5) do
      {:ok, results} ->
        results
        |> Enum.map(fn r ->
          "[#{r.source.title}]: #{r.content}"
        end)
        |> Enum.join("\n\n---\n\n")
        |> String.slice(0, max_chars)

      {:error, _} ->
        ""
    end
  end

  @doc """
  Lists documents for a user.
  """
  @spec list_documents(binary(), keyword()) :: [Document.t()]
  def list_documents(user_id, opts \\ []) do
    Document.list_for_user(user_id, opts)
  end

  @doc """
  Gets a document by ID.
  """
  @spec get_document(binary()) :: Document.t() | nil
  def get_document(id), do: Document.get(id)

  @doc """
  Gets a document with all its chunks.
  """
  @spec get_document_with_chunks(binary()) :: Document.t() | nil
  def get_document_with_chunks(id), do: Document.get_with_chunks(id)

  @doc """
  Deletes a document and all its chunks from the knowledge base.
  """
  @spec delete_document(binary()) :: {:ok, Document.t()} | {:error, term()}
  def delete_document(document_id) do
    # First, delete all memory entries for this document's chunks
    chunks = DocumentChunk.list_for_document(document_id)

    Enum.each(chunks, fn chunk ->
      Memory.forget(chunk.memory_id)
    end)

    # Delete chunks
    DocumentChunk.delete_for_document(document_id)

    # Delete document
    Document.delete(document_id)
  end

  @doc """
  Reprocesses a document (useful after fixing extraction issues).
  """
  @spec reprocess(binary()) :: {:ok, Document.t()} | {:error, term()}
  def reprocess(document_id) do
    # Delete existing chunks
    chunks = DocumentChunk.list_for_document(document_id)

    Enum.each(chunks, fn chunk ->
      Memory.forget(chunk.memory_id)
    end)

    DocumentChunk.delete_for_document(document_id)

    # Reprocess
    Processor.process(document_id)
  end

  @doc """
  Gets statistics about a user's knowledge base.
  """
  @spec stats(binary()) :: map()
  def stats(user_id) do
    documents = Document.list_for_user(user_id, limit: 1000)

    %{
      total_documents: length(documents),
      by_status: Enum.frequencies_by(documents, & &1.status),
      by_category: Enum.frequencies_by(documents, & &1.category),
      total_chunks: Enum.reduce(documents, 0, &(&1.chunk_count + &2)),
      all_tags: documents |> Enum.flat_map(& &1.tags) |> Enum.uniq() |> Enum.sort()
    }
  end

  # Private Functions

  defp create_document(user_id, attrs) do
    Document.create(user_id, %{
      title: attrs[:title],
      content_type: attrs[:content_type] || "text/plain",
      filename: attrs[:filename],
      file_size: attrs[:file_size],
      raw_content: attrs[:content],
      tags: attrs[:tags] || [],
      category: attrs[:category]
    })
  end

  defp schedule_processing(document_id) do
    # Use Oban for background processing
    %{document_id: document_id}
    |> Hal.Knowledge.ProcessorWorker.new()
    |> Oban.insert()
  end

  defp enrich_with_source(%{memory: memory, similarity: similarity}) do
    case DocumentChunk.get_by_memory(memory.id) do
      nil ->
        nil

      chunk ->
        %{
          content: memory.content,
          similarity: similarity,
          source: %{
            document_id: chunk.document.id,
            title: chunk.document.title,
            user_id: chunk.document.user_id,
            chunk_index: chunk.chunk_index,
            page_number: chunk.page_number,
            section_title: chunk.section_title
          }
        }
    end
  end

  defp detect_content_type(path) do
    case Path.extname(path) |> String.downcase() do
      ".pdf" -> "application/pdf"
      ".md" -> "text/markdown"
      ".markdown" -> "text/markdown"
      ".txt" -> "text/plain"
      ".html" -> "text/html"
      ".htm" -> "text/html"
      _ -> "text/plain"
    end
  end
end
