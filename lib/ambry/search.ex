defmodule Ambry.Search do
  @moduledoc """
  A context for aggregate search across books, authors, narrators and series.
  """

  alias Ambry.{Authors, Books, Narrators, Series}

  def search(query) do
    authors = Authors.search(query, 10)
    books = Books.search(query, 10)
    narrators = Narrators.search(query, 10)
    series = Series.search(query, 10)

    [
      {:authors, authors},
      {:books, books},
      {:narrators, narrators},
      {:series, series}
    ]
    |> Enum.reject(&(elem(&1, 1) == []))
    |> Enum.sort_by(
      fn {_label, items} ->
        items
        |> Enum.map(&elem(&1, 0))
        |> average()
      end,
      :desc
    )
  end

  defp average(floats) do
    Enum.sum(floats) / length(floats)
  end
end
