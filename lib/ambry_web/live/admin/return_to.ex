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

  ## `focus` is spent the moment it is used

  Being in the URL is what makes it survive the round trip, and being in the
  URL is also what put it in the browser's history: every back and forward
  through that entry lit the row up again, on a list the operator was merely
  passing through (operator, 2026-08-21).

  So the list says when it has flashed, and the entry is **replaced** with the
  same list minus `focus` — the history that remains is the one the operator
  would have made themselves, and there is no entry left to come back to. It
  is `push_patch(replace: true)`, which is `history.replaceState` with
  LiveView's own bookkeeping kept straight; doing it in the hook by hand
  changes the URL behind LiveView's back and leaves its idea of where it is
  disagreeing with the address bar.

  **After the flash, not on arrival.** Dropping the param as soon as it is
  read would race the render that carries it to the client, and the whole
  point of the param is a thing that happens in the browser.

  ## One hook, every admin list

  Mounted on the `:admin` live session rather than added to six index modules,
  which is what the six identical `assign(focus: params["focus"])` lines were.
  A page with no `focus` in its params assigns nil and nothing else happens.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView

  @doc false
  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> attach_hook(:focus_arrives, :handle_params, &arrives/3)
     |> attach_hook(:focus_flashed, :handle_event, &flashed/3)}
  end

  defp arrives(params, uri, socket) do
    {:cont, assign(socket, focus: params["focus"], focus_spent: spent_path(params, uri))}
  end

  # Raised by `assets/js/hooks/focus-row.js` once the row has been found and
  # lit up. A list that never had a focus never sends it, and a stale page
  # that sends it anyway has nothing to replace.
  defp flashed("focus-flashed", _params, socket) do
    case socket.assigns[:focus_spent] do
      nil ->
        {:halt, socket}

      path ->
        {:halt,
         socket
         |> assign(focus: nil, focus_spent: nil)
         |> push_patch(to: path, replace: true)}
    end
  end

  defp flashed(_event, _params, socket), do: {:cont, socket}

  # The same address without the part that has now been used. Built from the
  # URI the router gave us rather than from anything the client said, so the
  # only thing a page can ask for is its own address.
  defp spent_path(%{"focus" => _focus}, uri) do
    parsed = URI.parse(uri)

    query =
      (parsed.query || "")
      |> URI.decode_query()
      |> Map.delete("focus")
      |> then(&(map_size(&1) > 0 && URI.encode_query(&1)))

    %URI{path: parsed.path, query: query || nil} |> URI.to_string()
  end

  defp spent_path(_params, _uri), do: nil

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
