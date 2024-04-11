defmodule AmbryScraping.HTMLToMD do
  @moduledoc """
  A very simple/naive HTML to Markdown converter

  It doesn't work great in all cases...
  """

  use Boundary

  def html_to_md(html_string) when is_binary(html_string) do
    html_string
    |> Floki.parse_document!()
    |> html_to_md()
  end

  def html_to_md(document) when is_list(document) do
    document
    |> Floki.traverse_and_update(&process_node/1)
    |> Floki.raw_html()
    |> clean_html()
  end

  def html_to_md(_term), do: nil

  defp process_node({e, [], children}) when e in ~w(b strong), do: format_children(children, "**")
  defp process_node({e, [], children}) when e in ~w(i em), do: format_children(children, "_")
  defp process_node({"p", [], children}), do: format_children(children, "\n")
  defp process_node({"br", [], []}), do: "\n"
  defp process_node({_e, _attrs, children}), do: format_children(children)

  defp format_children(children, wrapping \\ nil),
    do: children |> Enum.join("") |> String.trim() |> wrap(wrapping)

  defp wrap(string, nil), do: string
  defp wrap(string, wrapping), do: " #{wrapping}#{string}#{wrapping} "

  defp clean_html(string) do
    string
    |> String.replace("\u00a0", "")
    |> String.replace("\u201C", "\"")
    |> String.replace("\u201D", "\"")
    |> String.replace("\u2018", "'")
    |> String.replace("\u2019", "'")
    |> String.replace("&#39;", "'")
    |> String.replace("&quot;", "\"")
    |> String.trim()
  end
end
