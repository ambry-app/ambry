defmodule AmbryWeb.Admin.HTMLToMD do
  @moduledoc """
  A very simple/naive HTML to Markdown converter.

  It only handles <p>, <b>, and <i> tags, and doesn't work great in all cases.
  """

  def html_to_md(html_string) do
    case html_string |> clean_string() |> Floki.parse_document() do
      {:ok, document} ->
        {:ok,
         document
         |> Floki.traverse_and_update(&translate/1)
         |> Floki.text()
         |> String.trim("\n")}

      _else ->
        :error
    end
  end

  defp translate(node) do
    case node do
      {"p", [], children} -> {"p", [], ["\n"] ++ children ++ ["\n"]}
      {"b", [], children} -> {"b", [], ["**"] ++ children ++ ["**"]}
      {"i", [], children} -> {"i", [], ["_"] ++ children ++ ["_"]}
      other -> other
    end
  end

  defp clean_string(string) do
    string
    |> String.replace("\n", "")
    |> String.replace("\u00a0", "")
    |> String.replace("\u201C", "\"")
    |> String.replace("\u201D", "\"")
    |> String.replace("\u2018", "'")
    |> String.replace("\u2019", "'")
    |> String.trim()
  end
end
