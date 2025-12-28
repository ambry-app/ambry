defmodule AmbryWeb.Helpers.IdHelpers do
  @moduledoc """
  Helpers for parsing IDs that may be either integer IDs or Relay global IDs.
  """

  import Absinthe.Relay.Node, only: [from_global_id: 2]

  @doc """
  Parses an ID that may be either an integer string or a Relay global ID.
  Returns {:ok, integer_id} or {:error, reason}.

  ## Examples

      iex> parse_id("123")
      {:ok, 123}

      iex> parse_id("TWVkaWE6MTIz")  # base64 for "Media:123"
      {:ok, 123}

      iex> parse_id("TWVkaWE6MTIz", :media)
      {:ok, 123}

      iex> parse_id("TWVkaWE6MTIz", :book)
      {:error, :type_mismatch}

  """
  def parse_id(id_string, expected_type \\ nil) do
    # First try as plain integer
    case Integer.parse(id_string) do
      {int_id, ""} ->
        {:ok, int_id}

      _ ->
        # Try as Relay global ID
        case from_global_id(id_string, AmbrySchema) do
          {:ok, %{id: id_str, type: type}} ->
            if expected_type && type != expected_type do
              {:error, :type_mismatch}
            else
              {:ok, String.to_integer(id_str)}
            end

          _ ->
            {:error, :invalid_id}
        end
    end
  end
end
