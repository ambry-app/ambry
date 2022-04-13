defmodule Ambry.FlatSchema do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      import Ecto.Query

      def paginate(offset, limit) do
        from r in __MODULE__, offset: ^offset, limit: ^limit
      end

      def filter(query, filters) do
        Enum.reduce(filters, query, fn {key, val}, query ->
          __MODULE__.filter(query, key, val)
        end)
      end

      def order(query, {field, :asc}), do: from(p in query, order_by: [asc: ^field])
      def order(query, {field, :desc}), do: from(p in query, order_by: [desc: ^field])
      def order(query, field), do: from(p in query, order_by: ^field)
    end
  end
end
