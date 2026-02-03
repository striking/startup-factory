defmodule HAL.Memory.Truncation do
  @moduledoc """
  Smart content truncation for memory management (ClawdBot pattern).

  Implements an intelligent truncation strategy that preserves meaning by keeping:
  - 70% from the head (beginning) - context setup and initial information
  - 20% from the tail (end) - recent content and conclusions
  - 10% gap in middle - marked with "[... truncated ...]"

  This approach is superior to simple tail-only truncation because:
  - Beginning content often contains critical context, definitions, or setup
  - Ending content often contains conclusions, recent updates, or summaries
  - Middle content is often the least critical (supporting details)

  ## Usage

      # Basic truncation
      HAL.Memory.Truncation.truncate(long_content)

      # Custom options
      HAL.Memory.Truncation.truncate(content, max_chars: 10_000, head_ratio: 0.6)

      # Token-based truncation (for LLM context windows)
      HAL.Memory.Truncation.truncate_to_tokens(content, 4000)

      # Quick check
      HAL.Memory.Truncation.needs_truncation?(content)

  ## Configuration

  Default options:
  - `max_chars`: 20,000 characters
  - `head_ratio`: 0.7 (70% from beginning)
  - `tail_ratio`: 0.2 (20% from end)
  - `marker`: "[... truncated ...]"

  The remaining 10% (1.0 - head_ratio - tail_ratio) is the gap.
  """

  @default_max_chars 20_000
  @default_head_ratio 0.7
  @default_tail_ratio 0.2
  @default_marker "\n\n[... truncated ...]\n\n"
  @chars_per_token 4

  # Regex patterns for boundary detection
  @sentence_boundary ~r/[.!?]\s+/
  @word_boundary ~r/\s+/

  @typedoc "Options for truncation functions"
  @type truncation_opts :: [
          max_chars: non_neg_integer(),
          head_ratio: float(),
          tail_ratio: float(),
          marker: String.t()
        ]

  @typedoc "Direction for boundary searching"
  @type direction :: :before | :after

  @doc """
  Truncate content using the head/tail preservation strategy.

  Keeps the beginning and end of content, removing the middle portion.
  Uses smart boundary detection to avoid cutting mid-word or mid-sentence.

  ## Parameters

    - `content` - The string content to truncate
    - `opts` - Keyword list of options:
      - `:max_chars` - Maximum character limit (default: #{@default_max_chars})
      - `:head_ratio` - Fraction of content to keep from beginning (default: #{@default_head_ratio})
      - `:tail_ratio` - Fraction of content to keep from end (default: #{@default_tail_ratio})
      - `:marker` - String to insert at truncation point (default: "[... truncated ...]")

  ## Returns

    - Original content if under the character limit
    - Truncated string with marker if truncation was needed

  ## Examples

      iex> short = "Hello, world!"
      iex> HAL.Memory.Truncation.truncate(short)
      "Hello, world!"

      iex> long = String.duplicate("This is a test sentence. ", 1000)
      iex> result = HAL.Memory.Truncation.truncate(long, max_chars: 100)
      iex> String.length(result) <= 100 + String.length("[... truncated ...]")
      true

  """
  @spec truncate(String.t(), truncation_opts()) :: String.t()
  def truncate(content, opts \\ []) when is_binary(content) do
    max_chars = Keyword.get(opts, :max_chars, @default_max_chars)
    head_ratio = Keyword.get(opts, :head_ratio, @default_head_ratio)
    tail_ratio = Keyword.get(opts, :tail_ratio, @default_tail_ratio)
    marker = Keyword.get(opts, :marker, @default_marker)

    content_length = String.length(content)

    # Return original if under limit
    if content_length <= max_chars do
      content
    else
      # Calculate the available space for content (excluding marker)
      marker_length = String.length(marker)
      available_chars = max_chars - marker_length

      # Ensure we have space for both head and tail
      available_chars = max(available_chars, 100)

      # Calculate head and tail sizes
      head_chars = round(available_chars * head_ratio)
      tail_chars = round(available_chars * tail_ratio)

      # Ensure minimum sizes
      head_chars = max(head_chars, 50)
      tail_chars = max(tail_chars, 50)

      # Extract raw slices
      head_raw = String.slice(content, 0, head_chars + 50)
      tail_start = content_length - tail_chars - 50
      tail_raw = String.slice(content, max(tail_start, head_chars), content_length)

      # Find smart boundaries
      head_end = smart_boundary(head_raw, head_chars, :before)
      head_content = String.slice(head_raw, 0, head_end)

      # For tail, find boundary from the beginning of the tail section
      tail_offset = smart_boundary(tail_raw, 0, :after)
      tail_content = String.slice(tail_raw, tail_offset, String.length(tail_raw))

      # Combine with marker
      head_content <> marker <> tail_content
    end
  end

  @doc """
  Truncate content to fit within a token budget.

  Uses an approximation of ~4 characters per token (varies by tokenizer,
  but this is a reasonable average for English text with Claude/GPT tokenizers).

  ## Parameters

    - `content` - The string content to truncate
    - `max_tokens` - Maximum token budget
    - `opts` - Same options as `truncate/2`

  ## Returns

    - Truncated string fitting within the approximate token budget

  ## Examples

      iex> content = String.duplicate("word ", 10000)
      iex> result = HAL.Memory.Truncation.truncate_to_tokens(content, 1000)
      iex> String.length(result) <= 4000 + 50  # ~4 chars/token + margin
      true

  """
  @spec truncate_to_tokens(String.t(), non_neg_integer(), truncation_opts()) :: String.t()
  def truncate_to_tokens(content, max_tokens, opts \\ []) when is_binary(content) do
    max_chars = max_tokens * @chars_per_token
    opts = Keyword.put(opts, :max_chars, max_chars)
    truncate(content, opts)
  end

  @doc """
  Find the nearest sentence or word boundary.

  Searches for a clean break point near the given position, preferring
  sentence boundaries (. ! ?) over word boundaries (whitespace).

  ## Parameters

    - `text` - The text to search within
    - `position` - The approximate position to find a boundary near
    - `direction` - `:before` to find boundary before position, `:after` for after

  ## Returns

    - Position of the found boundary (integer index into string)

  ## Details

  The search window is 100 characters in the specified direction.
  If no sentence boundary is found, falls back to word boundary.
  If no word boundary is found, returns the original position.

  ## Examples

      iex> text = "Hello world. This is a test. More content here."
      iex> HAL.Memory.Truncation.smart_boundary(text, 15, :before)
      12  # Position after "Hello world."

      iex> text = "No periods just words here"
      iex> HAL.Memory.Truncation.smart_boundary(text, 10, :before)
      6  # Position after "No" (word boundary)

  """
  @spec smart_boundary(String.t(), non_neg_integer(), direction()) :: non_neg_integer()
  def smart_boundary(text, position, direction) when is_binary(text) do
    text_length = String.length(text)
    position = min(max(position, 0), text_length)

    search_window = 100

    case direction do
      :before ->
        find_boundary_before(text, position, search_window)

      :after ->
        find_boundary_after(text, position, search_window)
    end
  end

  @doc """
  Quick check if content needs truncation.

  Useful for conditional logic before calling `truncate/2`.

  ## Parameters

    - `content` - The string content to check
    - `max_chars` - Maximum character limit (default: #{@default_max_chars})

  ## Returns

    - `true` if content exceeds the limit
    - `false` if content is within the limit

  ## Examples

      iex> HAL.Memory.Truncation.needs_truncation?("short text")
      false

      iex> long = String.duplicate("x", 25000)
      iex> HAL.Memory.Truncation.needs_truncation?(long)
      true

      iex> HAL.Memory.Truncation.needs_truncation?("test", 3)
      true

  """
  @spec needs_truncation?(String.t(), non_neg_integer()) :: boolean()
  def needs_truncation?(content, max_chars \\ @default_max_chars) when is_binary(content) do
    String.length(content) > max_chars
  end

  @doc """
  Estimate token count for content.

  Uses the approximation of ~4 characters per token.

  ## Parameters

    - `content` - The string content to estimate

  ## Returns

    - Estimated token count (integer)

  ## Examples

      iex> HAL.Memory.Truncation.estimate_tokens("Hello world!")
      3

  """
  @spec estimate_tokens(String.t()) :: non_neg_integer()
  def estimate_tokens(content) when is_binary(content) do
    ceil(String.length(content) / @chars_per_token)
  end

  # Private Functions

  # Find a boundary before the given position
  defp find_boundary_before(text, position, window) do
    search_start = max(0, position - window)
    search_text = String.slice(text, search_start, position - search_start)

    # Try to find sentence boundary first
    case find_last_sentence_boundary(search_text) do
      nil ->
        # Fall back to word boundary
        case find_last_word_boundary(search_text) do
          nil -> position
          offset -> search_start + offset
        end

      offset ->
        search_start + offset
    end
  end

  # Find a boundary after the given position
  defp find_boundary_after(text, position, window) do
    text_length = String.length(text)
    search_end = min(text_length, position + window)
    search_text = String.slice(text, position, search_end - position)

    # Try to find sentence boundary first
    case find_first_sentence_boundary(search_text) do
      nil ->
        # Fall back to word boundary
        case find_first_word_boundary(search_text) do
          nil -> position
          offset -> position + offset
        end

      offset ->
        position + offset
    end
  end

  # Find the last sentence boundary in text (position after the punctuation + space)
  defp find_last_sentence_boundary(text) do
    case Regex.scan(@sentence_boundary, text, return: :index) do
      [] ->
        nil

      matches ->
        # Get the last match
        [{start, length}] = List.last(matches)
        start + length
    end
  end

  # Find the first sentence boundary in text
  defp find_first_sentence_boundary(text) do
    case Regex.run(@sentence_boundary, text, return: :index) do
      nil -> nil
      [{start, length}] -> start + length
    end
  end

  # Find the last word boundary in text
  defp find_last_word_boundary(text) do
    case Regex.scan(@word_boundary, text, return: :index) do
      [] ->
        nil

      matches ->
        [{start, length}] = List.last(matches)
        start + length
    end
  end

  # Find the first word boundary in text
  defp find_first_word_boundary(text) do
    case Regex.run(@word_boundary, text, return: :index) do
      nil -> nil
      [{start, length}] -> start + length
    end
  end
end
