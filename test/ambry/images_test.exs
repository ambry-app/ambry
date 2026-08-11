defmodule Ambry.ImagesTest do
  use ExUnit.Case, async: true

  alias Ambry.Images

  describe "browser_safe/1" do
    test "JPEG and PNG pass through untouched" do
      jpeg = encoded(".jpg")
      png = encoded(".png")

      assert {:ok, ^jpeg, "image/jpeg"} = Images.browser_safe(jpeg)
      assert {:ok, ^png, "image/png"} = Images.browser_safe(png)
    end

    # The operator's Martian: a picture stream the container calls PNG,
    # carrying a big-endian TIFF. It extracted fine and the preview 404'd,
    # leaving a broken image beside a chip offering the art.
    test "a TIFF becomes a JPEG rather than a 404" do
      tiff = encoded(".tif")

      # Either byte order is a TIFF — the operator's file is big-endian
      # ("MM"), libvips writes little-endian ("II"), and a browser shows
      # neither.
      assert binary_part(tiff, 0, 2) in ["MM", "II"]
      assert {:ok, <<0xFF, 0xD8, 0xFF, _rest::binary>>, "image/jpeg"} = Images.browser_safe(tiff)
    end

    test "bytes that are not an image at all are still an error" do
      assert {:error, :no_embedded_image} = Images.browser_safe("not an image")
    end

    defp encoded(suffix) do
      {:ok, image} = Image.new(8, 8, color: :red)
      {:ok, binary} = Image.write(image, :memory, suffix: suffix)
      binary
    end
  end
end
