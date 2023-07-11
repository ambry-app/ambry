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
    case Regex.run(@full_date_regex, date_string) do
      [_match, month, day, year] ->
        %__MODULE__{
          date: Date.new!(String.to_integer(year), parse_month(month), String.to_integer(day)),
          display_format: :full
        }

      _else ->
        :error
    end
  end

  @year_month_regex ~r/^(.*?) ([0-9]{4})$/
  defp parse_year_month(date_string) do
    case Regex.run(@year_month_regex, date_string) do
      [_match, month, year] ->
        %__MODULE__{
          date: Date.new!(String.to_integer(year), parse_month(month), 1),
          display_format: :year_month
        }

      _else ->
        :error
    end
  end

  @year_regex ~r/^([0-9]{4})$/
  defp parse_year(date_string) do
    case Regex.run(@year_regex, date_string) do
      [_match, year] ->
        %__MODULE__{
          date: Date.new!(String.to_integer(year), 1, 1),
          display_format: :year
        }

      _else ->
        :error
    end
  end

  defp parse_month("January"), do: 1
  defp parse_month("February"), do: 2
  defp parse_month("March"), do: 3
  defp parse_month("April"), do: 4
  defp parse_month("May"), do: 5
  defp parse_month("June"), do: 6
  defp parse_month("July"), do: 7
  defp parse_month("August"), do: 8
  defp parse_month("September"), do: 9
  defp parse_month("October"), do: 10
  defp parse_month("November"), do: 11
  defp parse_month("December"), do: 12
end
