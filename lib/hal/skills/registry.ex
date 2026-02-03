defmodule HAL.Skills.Registry do
  @moduledoc """
  Progressive disclosure skill registry for HAL.

  Skills are task-specific instructions that are loaded on-demand
  to keep system prompts token-efficient. Only metadata is loaded
  initially (~100 tokens), with full content loaded when matched.

  ## Directory Structure

      .claude/skills/
      ├── calendar-management/
      │   └── SKILL.md
      ├── email-management/
      │   └── SKILL.md
      └── code-review/
          └── SKILL.md

  ## Usage

      # List available skills (metadata only)
      Registry.list_skills()

      # Match skills to a message
      Registry.match_skills("help me schedule a meeting")

      # Build context with matched skills
      Registry.build_skill_context("schedule a meeting with John")
  """

  require Logger

  @skills_dir ".claude/skills"
  @frontmatter_regex ~r/\A---\s*\n(.*?)\n---\s*\n(.*)\z/s

  @doc """
  List all available skills with metadata only.

  Returns lightweight metadata (~100 tokens total) for progressive disclosure.
  """
  @spec list_skills() :: [map()]
  def list_skills do
    skills_path = @skills_dir

    case File.ls(skills_path) do
      {:ok, dirs} ->
        dirs
        |> Enum.filter(&File.dir?(Path.join(skills_path, &1)))
        |> Enum.map(&load_skill_metadata/1)
        |> Enum.reject(&is_nil/1)

      {:error, _} ->
        []
    end
  end

  @doc """
  Match skills to a message using keyword extraction.

  Returns list of matching skills sorted by relevance score.
  """
  @spec match_skills(String.t(), keyword()) :: [map()]
  def match_skills(message, opts \\ []) do
    limit = Keyword.get(opts, :limit, 2)
    threshold = Keyword.get(opts, :threshold, 0.3)

    message_lower = String.downcase(message)
    words = extract_words(message_lower)

    list_skills()
    |> Enum.map(fn skill ->
      score = calculate_match_score(skill, words, message_lower)
      Map.put(skill, :match_score, score)
    end)
    |> Enum.filter(&(&1.match_score >= threshold))
    |> Enum.sort_by(& &1.match_score, :desc)
    |> Enum.take(limit)
  end

  @doc """
  Read full skill content by name.
  """
  @spec read_skill(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def read_skill(skill_name) do
    skill_path = Path.join([@skills_dir, skill_name, "SKILL.md"])

    case File.read(skill_path) do
      {:ok, content} ->
        {_frontmatter, body} = split_frontmatter(content)
        {:ok, String.trim(body)}

      {:error, _} ->
        {:error, :not_found}
    end
  end

  @doc """
  Build skill context for a message.

  Matches relevant skills and includes their full content.
  """
  @spec build_skill_context(String.t(), keyword()) :: String.t()
  def build_skill_context(message, opts \\ []) do
    matched_skills = match_skills(message, opts)

    if Enum.empty?(matched_skills) do
      ""
    else
      skill_contents =
        matched_skills
        |> Enum.map(fn skill ->
          case read_skill(skill.name) do
            {:ok, content} ->
              """
              ## #{skill.title} (skill: #{skill.name})

              #{content}
              """

            {:error, _} ->
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n\n---\n\n")

      if skill_contents != "" do
        """
        # Activated Skills

        The following specialized skills have been activated based on your request:

        #{skill_contents}
        """
      else
        ""
      end
    end
  end

  @doc """
  Get skill by name.
  """
  @spec get_skill(String.t()) :: map() | nil
  def get_skill(name) do
    Enum.find(list_skills(), &(&1.name == name))
  end

  # Private functions

  defp load_skill_metadata(dir_name) do
    skill_path = Path.join([@skills_dir, dir_name, "SKILL.md"])

    case File.read(skill_path) do
      {:ok, content} ->
        parse_skill_metadata(dir_name, content)

      {:error, _} ->
        nil
    end
  end

  defp parse_skill_metadata(name, content) do
    {frontmatter, body} = split_frontmatter(content)

    title_candidate =
      get_frontmatter(frontmatter, "title") || get_frontmatter(frontmatter, "name")

    title =
      if is_binary(title_candidate) and String.trim(title_candidate) != "" do
        String.trim(title_candidate)
      else
        case Regex.run(~r/^#\s+(.+)$/m, body) do
          [_, heading] -> String.trim(heading)
          _ -> humanize_name(name)
        end
      end

    description =
      case get_frontmatter(frontmatter, "description") do
        value when is_binary(value) ->
          value |> String.trim() |> String.slice(0, 200)

        _ ->
          case Regex.run(~r/^#.+\n\n(.+?)(?:\n\n|\z)/s, body) do
            [_, desc] -> String.trim(desc) |> String.slice(0, 200)
            _ -> ""
          end
      end

    keywords_candidate = get_frontmatter(frontmatter, "keywords")

    keywords =
      cond do
        is_list(keywords_candidate) ->
          keywords_candidate
          |> Enum.map(&to_string/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        is_binary(keywords_candidate) and String.trim(keywords_candidate) != "" ->
          keywords_candidate
          |> String.split(~r/[,\s]+/)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        true ->
          extract_skill_keywords(body)
      end

    runner = get_frontmatter(frontmatter, "runner")
    requires_approval? = truthy?(get_frontmatter(frontmatter, "requires_approval"))
    command = get_frontmatter(frontmatter, "command")
    args = normalize_string_list(get_frontmatter(frontmatter, "args"))
    tool = get_frontmatter(frontmatter, "tool")
    tool_args = normalize_tool_args(get_frontmatter(frontmatter, "tool_args"))
    timeout_ms = normalize_integer(get_frontmatter(frontmatter, "timeout_ms"))

    working_dir =
      get_frontmatter(frontmatter, "working_dir") || get_frontmatter(frontmatter, "workdir")

    %{
      name: name,
      title: title,
      description: description,
      keywords: keywords,
      runner: runner,
      requires_approval: requires_approval?,
      command: command,
      args: args,
      tool: tool,
      tool_args: tool_args,
      timeout_ms: timeout_ms,
      working_dir: working_dir,
      frontmatter: frontmatter
    }
  end

  defp split_frontmatter(content) when is_binary(content) do
    case Regex.run(@frontmatter_regex, content) do
      [_, frontmatter_text, body] ->
        {parse_frontmatter(frontmatter_text), body}

      _ ->
        {%{}, content}
    end
  end

  defp parse_frontmatter(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.reduce({%{}, nil}, fn raw_line, {acc, state} ->
      line = String.trim_trailing(raw_line)
      trimmed = String.trim_leading(line)

      cond do
        line == "" ->
          {acc, state}

        String.starts_with?(trimmed, "#") ->
          {acc, state}

        Regex.match?(~r/^[A-Za-z0-9_-]+:\s*/, trimmed) ->
          [key, rest] =
            case String.split(trimmed, ":", parts: 2) do
              [k, v] -> [String.trim(k), String.trim(v)]
              [k] -> [String.trim(k), ""]
            end

          if rest == "" do
            {Map.put(acc, key, nil), {:pending, key}}
          else
            {Map.put(acc, key, parse_scalar(rest)), nil}
          end

        Regex.match?(~r/^\s*-\s+/, line) and match?({:pending, _}, state) ->
          {:pending, key} = state

          item =
            line
            |> String.trim_leading()
            |> String.replace_prefix("- ", "")
            |> String.trim()
            |> strip_quotes()

          {Map.put(acc, key, [item]), {:list, key}}

        Regex.match?(~r/^\s*-\s+/, line) and match?({:list, _}, state) ->
          {:list, key} = state

          item =
            line
            |> String.trim_leading()
            |> String.replace_prefix("- ", "")
            |> String.trim()
            |> strip_quotes()

          updated = Map.update(acc, key, [item], fn existing -> existing ++ [item] end)
          {updated, {:list, key}}

        Regex.match?(~r/^\s+[A-Za-z0-9_-]+:\s*/, line) and match?({:pending, _}, state) ->
          {:pending, key} = state
          {subkey, rest} = split_map_line(line)
          value = parse_scalar(rest)
          {Map.put(acc, key, %{subkey => value}), {:map, key}}

        Regex.match?(~r/^\s+[A-Za-z0-9_-]+:\s*/, line) and match?({:map, _}, state) ->
          {:map, key} = state
          {subkey, rest} = split_map_line(line)
          value = parse_scalar(rest)
          updated = Map.update(acc, key, %{subkey => value}, &Map.put(&1, subkey, value))
          {updated, {:map, key}}

        true ->
          # Unsupported YAML feature; ignore.
          {acc, state}
      end
    end)
    |> elem(0)
  end

  defp split_map_line(line) do
    trimmed = String.trim_leading(line)

    case String.split(trimmed, ":", parts: 2) do
      [k, v] -> {String.trim(k), String.trim(v)}
      [k] -> {String.trim(k), ""}
    end
  end

  defp parse_scalar(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "true" -> true
      trimmed == "false" -> false
      Regex.match?(~r/^-?\d+$/, trimmed) -> String.to_integer(trimmed)
      Regex.match?(~r/^\[.*\]$/, trimmed) -> parse_inline_list(trimmed)
      true -> strip_quotes(trimmed)
    end
  end

  defp parse_inline_list(value) do
    value
    |> String.trim()
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&strip_quotes/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp strip_quotes(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace(~r/\A"(.*)"\z/s, "\\1")
    |> String.replace(~r/\A'(.*)'\z/s, "\\1")
  end

  defp get_frontmatter(frontmatter, key) when is_map(frontmatter) and is_binary(key),
    do: Map.get(frontmatter, key)

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("yes"), do: true
  defp truthy?("1"), do: true
  defp truthy?(_), do: false

  defp normalize_integer(nil), do: nil
  defp normalize_integer(value) when is_integer(value), do: value

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp normalize_integer(_), do: nil

  defp normalize_string_list(nil), do: nil
  defp normalize_string_list(list) when is_list(list), do: Enum.map(list, &to_string/1)
  defp normalize_string_list(_), do: nil

  defp normalize_tool_args(nil), do: %{}
  defp normalize_tool_args(map) when is_map(map), do: map
  defp normalize_tool_args(_), do: %{}

  defp extract_skill_keywords(content) do
    # Look for explicit keywords section
    explicit_keywords =
      case Regex.run(~r/keywords?:\s*\[?([^\]\n]+)\]?/i, content) do
        [_, kw] ->
          kw
          |> String.split(~r/[,\s]+/)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        _ ->
          []
      end

    # Extract from headings and content if no explicit keywords
    if Enum.empty?(explicit_keywords) do
      content
      |> String.downcase()
      |> extract_words()
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_word, count} -> count end, :desc)
      |> Enum.take(10)
      |> Enum.map(fn {word, _} -> word end)
    else
      explicit_keywords
    end
  end

  defp calculate_match_score(skill, message_words, message_lower) do
    # Keyword matching
    keyword_matches =
      skill.keywords
      |> Enum.count(fn kw ->
        String.contains?(message_lower, String.downcase(kw))
      end)

    # Avoid penalizing skills that have richer keyword sets by capping the
    # denominator. We want 2–3 strong hits to activate a skill even if it has
    # many keywords.
    keyword_score =
      if Enum.empty?(skill.keywords) do
        0
      else
        denom = min(length(skill.keywords), 6)
        min(1.0, keyword_matches / denom)
      end

    # Title/name matching
    name_score =
      if String.contains?(message_lower, String.downcase(skill.name)) do
        0.5
      else
        0
      end

    # Word overlap
    skill_words =
      (skill.keywords ++ String.split(skill.title, ~r/\s+/))
      |> Enum.map(&String.downcase/1)
      |> MapSet.new()

    message_set = MapSet.new(message_words)
    overlap = MapSet.intersection(skill_words, message_set) |> MapSet.size()

    overlap_score =
      if MapSet.size(skill_words) > 0 do
        overlap / MapSet.size(skill_words) * 0.3
      else
        0
      end

    keyword_score * 0.5 + name_score + overlap_score
  end

  defp extract_words(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split(~r/\s+/)
    |> Enum.reject(&(String.length(&1) < 3))
    |> Enum.reject(&stopword?/1)
  end

  defp humanize_name(name) do
    name
    |> String.replace("-", " ")
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  @stopwords ~w(the a an is are was were be been being have has had do does did will would should could can may might must shall)

  defp stopword?(word), do: word in @stopwords
end
