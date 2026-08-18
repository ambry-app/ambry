defmodule AmbryWeb.Admin.ReturnTo do
  @moduledoc """
  How a form knows where the operator came from, and how a list puts them back.

  A form used to end with `push_navigate(to: ~p"/admin/books")` — the front of
  an unfiltered, default-sorted list, whoever you were and wherever you had
  been. The queue's form has threaded its list state through the URL since it
  was written; this is that mechanism, shared, plus the half it didn't have:
  the record you were editing, scrolled to and lit up.

  Two halves that have to agree:

    * a list writes its state into every row link (`query/2`), and
    * a form reads it back and returns there (`path/3`), naming the record it
      just saved so the list can find it again.

  The URL is the carrier because it is the only thing that survives the round
  trip. A `push_navigate` is a fresh mount with no memory of the socket it
  came from, and the browser's own back button restores a *scroll offset* —
  which is the wrong thing to remember anyway. Rename a book and its row moves;
  what the operator means by "put me back" is the record, not the pixel.
  """

  @doc """
  The list state a row link should carry.

  Only the keys a list actually reads. Anything else a hand-typed URL puts in
  here is dropped rather than echoed back out of a form, which is what keeps
  this from becoming an open redirect or a 500 on a junk param.
  """
  @list_params ~w(filter page sort status problem)

  def query(list_opts, extra \\ %{}) do
    list_opts
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.merge(Map.new(extra, fn {key, value} -> {to_string(key), value} end))
    |> Map.take(@list_params)
    |> Enum.reject(fn {_key, value} -> value in [nil, "", 1, "1"] end)
    |> Map.new(fn {key, value} -> {key, to_string(value)} end)
  end

  @doc """
  What a form should keep out of its mount params: the list state, and nothing
  else. Held in an assign so `path/3` can hand it back at the end.
  """
  def list_params(params), do: Map.take(params, @list_params)

  @doc """
  Where a form goes when it is done.

  `list_params` is what `list_params/1` kept. `focus` is the record just saved,
  so the list can scroll to it — omitted when there is nothing to point at.

  A form reached from somewhere other than a list (the "New" button, a link
  from the overview, a bookmark) simply has no list state to hand back, and
  falls through to the bare list path.
  """
  def path(list_path, list_params, focus \\ nil) do
    query =
      if focus,
        do: Map.put(list_params, "focus", to_string(focus)),
        else: list_params

    case query do
      empty when map_size(empty) == 0 -> list_path
      query -> "#{list_path}?#{URI.encode_query(query)}"
    end
  end
end
