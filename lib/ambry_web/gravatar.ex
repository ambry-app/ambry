defmodule AmbryWeb.Gravatar do
  @moduledoc """
  Generates [Gravatar](http://gravatar.com) urls.
  """

  @domain "gravatar.com"

  @doc """
  Generates a gravatar url for the given email address.

  ## Examples

      iex> gravatar_url("jdoe@example.com", secure: false)
      "http://gravatar.com/avatar/694ea0904ceaf766c6738166ed89bafb"

      iex> gravatar_url("jdoe@example.com", s: 256)
      "https://secure.gravatar.com/avatar/694ea0904ceaf766c6738166ed89bafb?s=256"

      iex> gravatar_url("jdoe@example.com")
      "https://secure.gravatar.com/avatar/694ea0904ceaf766c6738166ed89bafb"
  """
  def gravatar_url(email, opts \\ []) do
    {secure, opts} = Keyword.pop(opts, :secure, true)

    %URI{}
    |> host(secure)
    |> hash_email(email)
    |> parse_options(opts)
    |> to_string()
  end

  defp parse_options(%URI{} = uri, []), do: %{uri | query: nil}
  defp parse_options(%URI{} = uri, opts), do: %{uri | query: URI.encode_query(opts)}

  defp host(%URI{} = uri, true), do: %{uri | scheme: "https", host: "secure.#{@domain}"}
  defp host(%URI{} = uri, false), do: %{uri | scheme: "http", host: @domain}

  defp hash_email(%URI{} = uri, email) do
    hash = Base.encode16(:crypto.hash(:md5, String.downcase(email)), case: :lower)
    %{uri | path: "/avatar/#{hash}"}
  end
end
