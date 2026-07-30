defmodule AmbryWeb.Markdown do
  @moduledoc """
  Renders user-supplied markdown (book, media and person descriptions).

  Descriptions are stored as markdown: the Audible and GoodReads scrapers
  convert scraped HTML to markdown before persisting it, and admins can edit
  it by hand.

  Raw HTML is escaped rather than rendered, so a stray tag in a description
  cannot inject markup into the page.
  """

  @opts [
    extension: [table: true, strikethrough: true, autolink: true],
    render: [escape: true]
  ]

  @doc """
  Renders a markdown string to HTML.
  """
  def to_html!(markdown), do: MDEx.to_html!(markdown, @opts)

  @doc """
  Renders a markdown string to plain text, with all markup stripped.
  """
  def to_text!(markdown) do
    markdown
    |> to_html!()
    |> Floki.parse_document!()
    |> Floki.text()
  end
end
