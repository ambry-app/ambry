defmodule Ambry.Repo.FlatSchema do
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

      @doc """
      How many rows a list would have, under the filters it is listing with.

      Built from the same `filter/2` chain as the page itself, because a total
      that disagrees with what is on screen is worse than no total at all.

      Cheap when nothing is filtering: the flat views put their credit arrays
      in the target list as correlated subqueries, and the planner drops every
      one of them for a bare count — measured, it is a plain seq scan of the
      base table. A *searched* count does build them, because the search reads
      them, which makes it the same work the page query is already doing.
      """
      def count_query(filters \\ %{}) do
        from r in filter(__MODULE__, filters), select: count(r.id)
      end

      # Every ordering ends in `id`, and that is not a tidiness point.
      # Two rows with the same sort key have no defined order between two
      # queries, and OFFSET pagination over an undefined order silently
      # duplicates rows onto one page and skips them off another. It is
      # certain on a boolean sort — `admin` on the users list puts every
      # record into one of two buckets — and reachable on `inserted_at`
      # whenever an import stamps a batch of rows inside the same second.
      #
      # Two tuple shapes arrive here and both are real, which is why the
      # direction is matched literally rather than by position:
      # `PaginationHelpers.sort_to_order/2` builds `{field, direction}`, and
      # Ecto's own keyword shape is `{direction, field}`. Ordering the clauses
      # this way is what tells them apart; it used to be an accident of the
      # fallback clause accepting whatever was left.
      def order(query, nil), do: from(r in query, order_by: [asc: :id])

      def order(query, {field, :asc}), do: from(r in query, order_by: [asc: ^field, asc: :id])

      def order(query, {field, :desc}), do: from(r in query, order_by: [desc: ^field, asc: :id])

      def order(query, fields) when is_list(fields),
        do: from(r in query, order_by: ^(fields ++ [asc: :id]))

      def order(query, {dir, field}), do: from(r in query, order_by: ^[{dir, field}, {:asc, :id}])

      def order(query, field), do: from(r in query, order_by: ^[{:asc, field}, {:asc, :id}])
    end
  end
end
