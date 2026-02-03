defmodule HalWeb.Helpers.Markdown do
  @moduledoc """
  Markdown rendering helper for chat messages.
  Converts markdown to safe HTML using Earmark.
  """

  @doc """
  Renders markdown content as safe HTML.
  Returns a Phoenix.HTML.safe tuple for use in templates.
  """
  def render(nil), do: ""
  def render(""), do: ""

  def render(content) when is_binary(content) do
    content
    |> Earmark.as_html!(
      code_class_prefix: "language-",
      smartypants: false,
      breaks: true
    )
    |> Phoenix.HTML.raw()
  end

  @doc """
  Renders markdown with custom options.
  """
  def render(content, opts) when is_binary(content) do
    earmark_opts = Keyword.get(opts, :earmark, [])

    content
    |> Earmark.as_html!(earmark_opts)
    |> Phoenix.HTML.raw()
  end
end
