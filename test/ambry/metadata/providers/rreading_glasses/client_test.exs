defmodule Ambry.Metadata.Providers.RreadingGlasses.ClientTest do
  use ExUnit.Case, async: false
  use Patch

  alias Ambry.Metadata.Providers.RreadingGlasses.Client

  test "returns bodies Req already decoded" do
    patch(Req, :get, fn _opts -> {:ok, %Req.Response{status: 200, body: [%{"bookId" => 1}]}} end)

    assert {:ok, [%{"bookId" => 1}]} = Client.get_json("https://rg.test", "/search", q: "x")
  end

  test "disables Req's automatic retry (429 Retry-After waits hang interactive imports)" do
    patch(Req, :get, fn opts ->
      assert Keyword.get(opts, :retry) == false
      {:ok, %Req.Response{status: 200, body: []}}
    end)

    assert {:ok, []} = Client.get_json("https://rg.test", "/search", q: "x")
  end

  test "decodes JSON served as text/plain (public instance behind Cloudflare)" do
    patch(Req, :get, fn _opts ->
      {:ok, %Req.Response{status: 200, body: ~s([{"bookId": 211721806, "workId": 76027608}])}}
    end)

    assert {:ok, [%{"bookId" => 211_721_806}]} =
             Client.get_json("https://rg.test", "/search", q: "x")
  end

  test "a 200 HTML page (unknown route) is an error, not a result" do
    patch(Req, :get, fn _opts ->
      {:ok, %Req.Response{status: 200, body: "<!DOCTYPE html>\n<html>..."}}
    end)

    assert {:error, :unexpected_response_payload} = Client.get_json("https://rg.test", "/nope")
  end

  test "404 maps to not_found" do
    patch(Req, :get, fn _opts -> {:ok, %Req.Response{status: 404, body: "HTTP 404"}} end)

    assert {:error, :not_found} = Client.get_json("https://rg.test", "/author/0")
  end

  test "transport errors pass through" do
    patch(Req, :get, fn _opts -> {:error, %Mint.TransportError{reason: :nxdomain}} end)

    assert {:error, %Mint.TransportError{reason: :nxdomain}} =
             Client.get_json("https://rg.test", "/search", q: "x")
  end
end
