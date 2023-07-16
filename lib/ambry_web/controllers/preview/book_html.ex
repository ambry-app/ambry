defmodule AmbryWeb.Preview.BookHTML do
  use AmbryWeb, :html

  embed_templates "book_html/*"

  defp format_published(%{published_format: :full, published: date}), do: Calendar.strftime(date, "%B %-d, %Y")

  defp format_published(%{published_format: :year_month, published: date}), do: Calendar.strftime(date, "%B %Y")

  defp format_published(%{published_format: :year, published: date}), do: Calendar.strftime(date, "%Y")
end
