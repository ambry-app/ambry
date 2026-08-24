defmodule AmbryWeb.Admin.ReturnTo do
  @moduledoc """
  How a form knows where the operator came from, and how a list puts them
  back.

  A form that ends with `push_navigate(to: ~p"/admin/books")` lands on the
  front of an unfiltered, default-sorted list. This threads the list state
  through the URL instead, and carries the record you were editing with it,
  scrolled to and lit up.

  Two halves that have to agree:

    * a list writes its state into every row link (`query/2`), and
    * a form reads it back and returns there (`path/3`), naming the record it
      just saved so the list can find it again.

  The URL is the carrier because it is the only thing that survives the round
  trip: a `push_navigate` is a fresh mount with no memory of the socket it
  came from, and the browser's back button restores a *scroll offset*, which
  is the wrong thing to remember. Rename a book and its row moves.

  ## `focus` is spent where it is read

  Being in the URL is also what puts it in the browser's history, so an entry
  that keeps it lights the row up again on every back and forward through it.
  The hook that reads it takes it back out of the address bar itself
  (`assets/js/hooks/focus-row.js`), and this side is never told.

  Nothing on the server needs telling, and telling it costs something: the
  only way back is a `push_patch`, which replaces the socket's flash with
  whatever that event put there, so the patch would clear the "Saved." the
  operator is still reading.

  Mounted on the `:admin` live session rather than repeated in every index
  module. A page with no `focus` in its params assigns nil.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4]

  @doc false
  def on_mount(:default, _params, _session, socket) do
    {:cont, attach_hook(socket, :focus_arrives, :handle_params, &arrives/3)}
  end

  defp arrives(params, _uri, socket) do
    {:cont, assign(socket, focus: params["focus"])}
  end

  @doc """
  The list state a row link should carry.

  Only the keys a list actually reads. Anything else a hand-typed URL puts in
  here is dropped rather than echoed back out of a form.
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

  `list_params` is what `list_params/1` kept; `focus` is the record just
  saved, omitted when there is nothing to point at.

  A form reached from somewhere other than a list has no list state to hand
  back and falls through to the bare list path.
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
