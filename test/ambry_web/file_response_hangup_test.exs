defmodule AmbryWeb.FileResponseHangupTest do
  @moduledoc """
  The one behavior that only a real socket can show.

  `Plug.Test`'s adapter buffers the response in memory, so it can never fail
  the way a client hanging up mid-transfer does. This boots Bandit on a real
  port, starts a file large enough that `sendfile` blocks on the socket
  buffer, and closes the connection underneath it.
  """

  use ExUnit.Case, async: true

  # Comfortably past any socket buffer, so `sendfile` is still writing when
  # the client goes away.
  @size 32 * 1024 * 1024

  defmodule TestPlug do
    @moduledoc false
    @behaviour Plug

    @impl Plug
    def init(opts), do: opts

    @impl Plug
    def call(conn, %{path: path, test: test}) do
      conn = AmbryWeb.FileResponse.send(conn, path, "audio/mpeg")
      send(test, {:file_response_returned, conn.state})
      conn
    end
  end

  setup do
    path = Path.join(System.tmp_dir!(), "hangup-#{System.unique_integer([:positive])}.mp3")
    File.write!(path, :binary.copy("a", @size))
    on_exit(fn -> File.rm(path) end)

    {:ok, server} =
      Bandit.start_link(
        plug: {TestPlug, %{path: path, test: self()}},
        scheme: :http,
        port: 0,
        startup_log: false
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    %{port: port}
  end

  test "returns a sent conn when the client hangs up mid-transfer", %{port: port} do
    {:ok, socket} =
      :gen_tcp.connect(~c"localhost", port, [:binary, active: false, packet: :raw])

    :ok = :gen_tcp.send(socket, "GET /files/track HTTP/1.1\r\nHost: localhost\r\n\r\n")

    # Take just enough to know the transfer is under way, then leave. The
    # unread bytes still in flight make this a hard close, which is what a
    # player does when it stops caring about the rest of the file.
    {:ok, _some_bytes} = :gen_tcp.recv(socket, 0, 5000)
    :ok = :gen_tcp.close(socket)

    # `:sent`, not a raise: the plug ran to completion, so nothing is left to
    # render a 500 page at, log a second time, or report to Sentry.
    assert_receive {:file_response_returned, :sent}, 5000
  end

  test "serves the file normally when the client stays", %{port: port} do
    {:ok, socket} =
      :gen_tcp.connect(~c"localhost", port, [:binary, active: false, packet: :raw])

    :ok = :gen_tcp.send(socket, "GET /files/track HTTP/1.1\r\nHost: localhost\r\n\r\n")

    assert drain(socket, 0) >= @size

    assert_receive {:file_response_returned, :file}, 5000
  end

  defp drain(socket, count) do
    case :gen_tcp.recv(socket, 0, 5000) do
      {:ok, bytes} -> drain(socket, count + byte_size(bytes))
      {:error, :closed} -> count
      {:error, :timeout} -> count
    end
  end
end
