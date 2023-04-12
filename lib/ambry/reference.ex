defmodule Ambry.Reference do
  @moduledoc false

  alias Ambry.Books.Book
  alias Ambry.Authors.Author
  alias Ambry.Media.Media
  alias Ambry.Narrators.Narrator
  alias Ambry.People.Person
  alias Ambry.Series.Series

  defstruct [:type, :id]

  def new(%Author{id: id}), do: %__MODULE__{type: :author, id: id}
  def new(%Book{id: id}), do: %__MODULE__{type: :book, id: id}
  def new(%Media{id: id}), do: %__MODULE__{type: :media, id: id}
  def new(%Narrator{id: id}), do: %__MODULE__{type: :narrator, id: id}
  def new(%Person{id: id}), do: %__MODULE__{type: :person, id: id}
  def new(%Series{id: id}), do: %__MODULE__{type: :series, id: id}
end
