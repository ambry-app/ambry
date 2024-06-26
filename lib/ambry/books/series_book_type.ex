defmodule Ambry.Books.SeriesBookType do
  @moduledoc false

  defstruct [:name, :number]

  defmodule Type do
    @moduledoc false

    use Ecto.Type

    alias Ambry.Books.SeriesBookType

    def type, do: :series_book

    def cast(%SeriesBookType{} = series_book) do
      {:ok, series_book}
    end

    def cast(_series_book), do: :error

    def load({name, number}) do
      {:ok, struct!(SeriesBookType, name: name, number: Decimal.new(number))}
    end

    def dump(%SeriesBookType{name: name, number: number}), do: {:ok, {name, number}}
    def dump(_series_book), do: :error
  end
end
