defmodule AmbryScraping.Marionette.Wire do
  @moduledoc false
  @ids 0..4_294_967_295

  defmodule Command do
    @moduledoc false
    defstruct [:message_id, :session_id, :name, {:params, %{}}]
  end

  defmodule Response do
    @moduledoc false
    defstruct [:message_id, :error, :result]
  end

  def encode!(%Command{session_id: session_id, name: name, params: params}) do
    message_id = Enum.random(@ids)
    params = Map.put(params, "sessionId", session_id)
    command_encoded = Jason.encode!([0, message_id, "WebDriver:#{name}", params])
    command_str = "#{String.length(command_encoded)}:#{command_encoded}"
    {message_id, command_str}
  end

  def decode!(response) do
    [1, message_id, error, result] = Jason.decode!(response)
    %Response{message_id: message_id, error: error, result: result}
  end
end
