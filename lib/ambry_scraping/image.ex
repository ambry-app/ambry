defmodule AmbryScraping.Image do
  @moduledoc false

  use Boundary

  defstruct [:src, :data_url]

  def fetch_from_source(src) do
    %__MODULE__{
      src: src,
      data_url: build_data_url(src)
    }
  end

  defp build_data_url(src) do
    case Req.get(src) do
      {:ok, %Req.Response{status: 200} = response} ->
        mime = Req.Response.get_header(response, "content-type")
        data = Base.encode64(response.body)
        "data:#{mime};base64,#{data}"

      _else ->
        nil
    end
  end
end
