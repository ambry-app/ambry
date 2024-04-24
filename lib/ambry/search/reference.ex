defmodule Ambry.Search.Reference do
  @moduledoc false

  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.Media.Media
  alias Ambry.People.Author
  alias Ambry.People.Narrator
  alias Ambry.People.Person

  defstruct [:type, :id]

  def new(%Author{id: id}), do: %__MODULE__{type: :author, id: id}
  def new(%Book{id: id}), do: %__MODULE__{type: :book, id: id}
  def new(%Media{id: id}), do: %__MODULE__{type: :media, id: id}
  def new(%Narrator{id: id}), do: %__MODULE__{type: :narrator, id: id}
  def new(%Person{id: id}), do: %__MODULE__{type: :person, id: id}
  def new(%Series{id: id}), do: %__MODULE__{type: :series, id: id}

  defmodule Type do
    @moduledoc false

    use Ecto.Type

    alias Ambry.Search.Reference

    def type, do: :reference

    def cast(%Reference{} = reference) do
      {:ok, reference}
    end

    def cast(_reference), do: :error

    def load({type, id}) do
      {:ok, struct!(Reference, type: load_type(type), id: id)}
    end

    def dump(%Reference{type: type, id: id}), do: {:ok, {to_string(type), id}}
    def dump(_reference), do: :error

    defp load_type("author"), do: :author
    defp load_type("book"), do: :book
    defp load_type("media"), do: :media
    defp load_type("narrator"), do: :narrator
    defp load_type("person"), do: :person
    defp load_type("series"), do: :series
  end
end
