defmodule AmbryWeb.FileResponse do
  @moduledoc """
  Sends a file from anywhere on disk, with the byte-range support audio
  players need to seek.

  `Plug.Static` already does this, but only under one fixed root. Direct-play
  files aren't under a fixed root: today they can sit in the uploads tree or
  wherever a local import referenced them in place, and Phase 3 adds
  configurable library roots plus external collections that are read where
  they lie. So the same behavior is reimplemented here, keyed on a path the
  caller has already authorized.

  The ETag is derived from mtime and size, exactly as `Plug.Static` derives
  it. That is deliberate and load-bearing: replacing a recording's files
  overwrites them in place, and a changed mtime changes the ETag, so
  streaming clients revalidate and pick up the new bytes without any new URL
  or cleanup dance.

  ## A client that hangs up is not an error

  `sendfile(2)` does not return until every byte is on the wire, and TCP
  backpressure paces that at the rate the player drains its buffer — for a
  whole book that is the length of the listening session. Pausing, seeking,
  or moving to the next track makes the player close the connection
  mid-transfer, and the pending write fails.

  That failure has to be caught here, because the response is already half
  reported by the time it happens. `Plug.Conn.send_file/5` runs the
  `before_send` callbacks *first* (so `Plug.Telemetry` has already logged
  `Sent 206`), then calls the adapter, and only afterwards posts the
  `{:plug_conn, :sent}` message that tells the rest of Phoenix a response
  went out. When the adapter raises, that message is never posted, so
  `Phoenix.Endpoint.RenderErrors` believes nothing has been sent: it renders
  a full 500 error page onto the closed socket, which runs `before_send`
  again and logs the same request a second time as `Sent 500 in <the whole
  transfer>`. Every one of those pairs in the production log is a listener
  pressing pause.

  So the rescue below reports what actually happened — the response is over —
  by handing back a conn in the `:sent` state. Nothing escapes to be rendered
  at, logged twice, or reported to Sentry.
  """

  import Plug.Conn

  @doc """
  Responds with the file at `path`, honoring `Range` and `If-None-Match`.

  Returns the conn untouched (not halted) when the file isn't there, so the
  caller can render its own 404.
  """
  def send(conn, path, content_type) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular} = stat} ->
        try do
          send_regular_file(conn, path, content_type, stat)
        rescue
          Bandit.TransportError -> hung_up(conn)
        end

      _not_a_file ->
        conn
    end
  end

  # The socket died partway through the response. There is nobody left to
  # tell, and no second attempt worth making: say the response is finished so
  # that no later stage tries to write one.
  defp hung_up(conn), do: %{conn | state: :sent}

  defp send_regular_file(conn, path, content_type, stat) do
    etag = etag(stat)

    conn =
      conn
      |> put_resp_header("accept-ranges", "bytes")
      |> put_resp_header("etag", etag)
      |> put_resp_content_type(content_type || "application/octet-stream")

    if fresh?(conn, etag) do
      send_resp(conn, 304, "")
    else
      send_contents(conn, path, stat.size)
    end
  end

  defp send_contents(conn, path, size) do
    case requested_range(conn, size) do
      {:ok, first, last} ->
        conn
        |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
        |> send_file(206, path, first, last - first + 1)

      :unsatisfiable ->
        conn
        |> put_resp_header("content-range", "bytes */#{size}")
        |> send_resp(416, "")

      :none ->
        send_file(conn, 200, path)
    end
  end

  # A client that already has the current bytes gets told so, whether or not
  # it asked for a range.
  defp fresh?(conn, etag) do
    etag in (conn |> get_req_header("if-none-match") |> Enum.flat_map(&split_etags/1))
  end

  defp split_etags(header) do
    header |> String.split(",") |> Enum.map(&String.trim/1)
  end

  # Only a single range is honored. Serving the whole file in response to a
  # multi-range request is allowed, and multipart/byteranges buys nothing for
  # audio playback.
  defp requested_range(conn, size) do
    case get_req_header(conn, "range") do
      ["bytes=" <> spec] -> parse_range(spec, size)
      _no_range -> :none
    end
  end

  defp parse_range(spec, size) do
    case String.split(spec, "-") do
      # bytes=<first>-<last>
      [first, last] when first != "" and last != "" ->
        bounded(parse_int(first), parse_int(last), size)

      # bytes=<first>- — everything from `first` on
      [first, ""] when first != "" ->
        bounded(parse_int(first), size - 1, size)

      # bytes=-<suffix> — the last `suffix` bytes
      ["", suffix] when suffix != "" ->
        case parse_int(suffix) do
          nil -> :none
          0 -> :unsatisfiable
          suffix -> bounded(max(size - suffix, 0), size - 1, size)
        end

      _unparseable ->
        :none
    end
  end

  defp bounded(nil, _last, _size), do: :none
  defp bounded(_first, nil, _size), do: :none

  defp bounded(first, last, size) do
    last = min(last, size - 1)

    cond do
      # an empty file has no satisfiable range, and neither does a start past
      # the end
      size == 0 or first >= size -> :unsatisfiable
      first > last -> :unsatisfiable
      true -> {:ok, first, last}
    end
  end

  defp parse_int(string) do
    case Integer.parse(string) do
      {int, ""} when int >= 0 -> int
      _unparseable -> nil
    end
  end

  # byte-for-byte what Plug.Static does, so both serving paths agree
  defp etag(%File.Stat{mtime: mtime, size: size}) do
    <<?", {mtime, size} |> :erlang.phash2() |> Integer.to_string(16)::binary, ?">>
  end
end
