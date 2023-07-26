defmodule AmbryScraping.GoodReads.PublishedDate do
  @moduledoc false
  defstruct [:date, :display_format]

  def new(date_string) do
    with :error <- parse_full_date(date_string),
         :error <- parse_year_month(date_string),
         :error <- parse_year(date_string) do
      nil
    end
  end

  @full_date_regex ~r/^(.*?) ([0-9]{1,2}).*? ([0-9]{4})$/
  defp parse_full_date(date_string) do
    with [_match, month, day, year] <- Regex.run(@full_date_regex, date_string),
         {:ok, month} <- parse_month(month),
         {:ok, date} <- Date.new(String.to_integer(year), month, String.to_integer(day)) do
      %__MODULE__{
        date: date,
        display_format: :full
      }
    else
      _else -> :error
    end
  end

  @year_month_regex ~r/^(.*?) ([0-9]{4})$/
  defp parse_year_month(date_string) do
    with [_match, month, year] <- Regex.run(@year_month_regex, date_string),
         {:ok, month} <- parse_month(month),
         {:ok, date} <- Date.new(String.to_integer(year), month, 1) do
      %__MODULE__{
        date: date,
        display_format: :year_month
      }
    else
      _else -> :error
    end
  end

  @year_regex ~r/^([0-9]{4})$/
  defp parse_year(date_string) do
    with [_match, year] <- Regex.run(@year_regex, date_string),
         {:ok, date} <- Date.new(String.to_integer(year), 1, 1) do
      %__MODULE__{
        date: date,
        display_format: :year
      }
    else
      _else -> :error
    end
  end

  defp parse_month("January"), do: {:ok, 1}
  defp parse_month("February"), do: {:ok, 2}
  defp parse_month("March"), do: {:ok, 3}
  defp parse_month("April"), do: {:ok, 4}
  defp parse_month("May"), do: {:ok, 5}
  defp parse_month("June"), do: {:ok, 6}
  defp parse_month("July"), do: {:ok, 7}
  defp parse_month("August"), do: {:ok, 8}
  defp parse_month("September"), do: {:ok, 9}
  defp parse_month("October"), do: {:ok, 10}
  defp parse_month("November"), do: {:ok, 11}
  defp parse_month("December"), do: {:ok, 12}
  defp parse_month(_else), do: :error
end
