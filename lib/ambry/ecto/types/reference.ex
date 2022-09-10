defmodule Ambry.Ecto.Types.Reference do
  @moduledoc false

  use Ecto.Type

  alias Ambry.Reference

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
