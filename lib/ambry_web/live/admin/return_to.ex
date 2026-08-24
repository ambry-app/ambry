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

  ## `focus` is spent the moment it is used

  Being in the URL is also what puts it in the browser's history, so left
  there every back and forward through that entry lights the row up again.

  So the list says when it has flashed, and the entry is replaced with the
  same list minus `focus`. It is `push_patch(replace: true)`, which keeps
  LiveView's bookkeeping straight; doing it in the hook by hand changes the
  URL behind LiveView's back.

  After the flash, not on arrival: dropping the param as soon as it is read
  would race the render that carries it to the client.

  Mounted on the `:admin` live session rather than repeated in every index
  module. A page with no `focus` in its params assigns nil.
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
  # lit up.
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
  # URI the router gave us, so a page can only ask for its own address.
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
