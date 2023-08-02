defmodule AmbryScraping.Marionette.Connection do
  @moduledoc """
  TCP socket connection for Marionette.

  List of WebDriver commands: https://searchfox.org/mozilla-central/source/remote/marionette/driver.sys.mjs#3288
  """

  @behaviour :gen_statem

  alias AmbryScraping.Marionette.Wire
  alias AmbryScraping.Marionette.Wire.Command
  alias AmbryScraping.Marionette.Wire.Response

  require Logger

  @buffer %{data: nil, expected: 0, current: 0}
  @timeout 60_000
  @initial_backoff 500
  @max_backoff 60_000

  defstruct [:host, :port, :socket, :session_id, buffer: @buffer, requests: %{}, backoff: @initial_backoff]

  # Public API

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def start_link(opts) do
    host = Keyword.fetch!(opts, :host)
    port = Keyword.fetch!(opts, :port)
    :gen_statem.start_link({:local, __MODULE__}, __MODULE__, {String.to_charlist(host), port}, [])
  end

  def order(command, params \\ %{}) do
    command = %Command{name: command, params: params}
    :gen_statem.call(__MODULE__, {:order, command}, @timeout)
  end

  # :gen_statem callbacks

  @impl :gen_statem
  def callback_mode, do: [:state_functions, :state_enter]

  @impl :gen_statem
  def init({host, port}) do
    data = %__MODULE__{host: host, port: port}
    actions = [{:next_event, :internal, :connect}]
    {:ok, :disconnected, data, actions}
  end

  # Disconnected state

  def disconnected(:enter, :disconnected, _data), do: :keep_state_and_data

  def disconnected(:enter, :connected, data) do
    Logger.error("[Marionette] Connection closed")

    Enum.each(data.requests, fn {_id, from} ->
      :gen_statem.reply(from, {:error, :disconnected})
    end)

    data = %{data | socket: nil, session_id: nil, buffer: @buffer, requests: %{}, backoff: @initial_backoff}

    actions = [{{:timeout, :reconnect}, data.backoff, nil}]
    {:keep_state, data, actions}
  end

  def disconnected(:internal, :connect, data) do
    Logger.debug("[Marionette] Connecting to tcp://#{data.host}:#{data.port}")
    socket_opts = [:binary, active: false]

    with {:ok, socket} <- :gen_tcp.connect(data.host, data.port, socket_opts),
         {_, new_session} = Wire.encode!(%Command{name: "NewSession"}),
         :ok <- :gen_tcp.send(socket, new_session),
         {:ok, _version_packet} <- :gen_tcp.recv(socket, 0),
         {:ok, packet} <- :gen_tcp.recv(socket, 0) do
      {response_data, bytes, bytes} = parse_packet(packet)
      %Response{result: %{"sessionId" => session_id}} = Wire.decode!(response_data)

      :inet.setopts(socket, active: true)

      Logger.info(fn -> "[Marionette] Connection established at tcp://#{data.host}:#{data.port}" end)

      {:next_state, :connected, %{data | socket: socket, session_id: session_id}}
    else
      {:error, error} ->
        Logger.error("[Marionette] Connection failed: #{:inet.format_error(error)}")

        backoff = Enum.min([data.backoff * 2, @max_backoff])
        Logger.debug("[Marionette] Reconnecting in #{backoff}ms")
        data = %{data | backoff: backoff}

        actions = [{{:timeout, :reconnect}, data.backoff, nil}]
        {:keep_state, data, actions}
    end
  end

  def disconnected({:timeout, :reconnect}, _, data) do
    actions = [{:next_event, :internal, :connect}]
    {:keep_state, data, actions}
  end

  def disconnected({:call, from}, {:order, _command}, _data) do
    actions = [{:reply, from, {:error, :disconnected}}]
    {:keep_state_and_data, actions}
  end

  # Connected state

  def connected(:enter, _old_state, _data), do: :keep_state_and_data

  def connected(:info, {:tcp_closed, socket}, %{socket: socket} = data) do
    {:next_state, :disconnected, data}
  end

  def connected({:call, from}, {:order, command}, %{socket: socket} = data) do
    {message_id, command} = Wire.encode!(%{command | session_id: data.session_id})

    case :gen_tcp.send(socket, command) do
      :ok ->
        data = %{data | requests: Map.put(data.requests, message_id, from)}
        {:keep_state, data}

      {:error, _reason} ->
        :ok = :gen_tcp.close(socket)
        {:next_state, :disconnected, data}
    end
  end

  def connected(:info, {:tcp, socket, packet}, %{socket: socket, buffer: %{data: nil}} = data) do
    {response_data, expected, current} = parse_packet(packet)

    data =
      if current < expected do
        %{
          data
          | buffer: %{
              data: response_data,
              expected: expected,
              current: current
            }
        }
      else
        reply(response_data, data)
      end

    {:keep_state, data}
  end

  def connected(
        :info,
        {:tcp, socket, packet},
        %{socket: socket, buffer: %{expected: expected, current: current} = buffer} = data
      ) do
    current = current + byte_size(packet)

    data =
      if current < expected do
        %{
          data
          | buffer: %{
              data: [buffer.data, packet],
              expected: expected,
              current: current
            }
        }
      else
        reply([buffer.data, packet], data)
      end

    {:keep_state, data}
  end

  # Helpers

  defp reply(response_data, %{requests: requests} = data) do
    %{message_id: message_id} = response = Wire.decode!(response_data)

    {from, requests} = Map.pop(requests, message_id)

    :gen_statem.reply(from, {:ok, response})

    %{data | requests: requests, buffer: @buffer}
  end

  defp parse_packet(packet) do
    [expected, data] = String.split(packet, ":", parts: 2)
    expected = String.to_integer(expected)

    {data, expected, byte_size(data)}
  end
end
