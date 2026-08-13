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

defmodule Ambry.ImagesImportTest do
  use ExUnit.Case, async: false
  use Patch

  alias Ambry.Images
  alias Ambry.Paths

  describe "import_url/1" do
    # The download used to accept only an allowlisted `content-type` header,
    # and Hardcover labels every asset `application/octet-stream` — so a photo
    # the person picker offered failed to import, quietly.
    test "imports an image the server labels application/octet-stream" do
      png = encoded(".png")
      stub_get("application/octet-stream", png)

      assert {:ok, "/uploads/images/" <> filename} =
               Images.import_url("https://assets.hardcover.app/author/1/x.png")

      on_exit(fn -> File.rm(Paths.images_disk_path(filename)) end)

      assert Path.extname(filename) == ".png"
      assert File.read!(Paths.images_disk_path(filename)) == png
    end

    # The bytes name the file, so a mislabeled download can't land under an
    # extension that lies about its contents.
    test "the extension comes from the bytes, not the header" do
      jpeg = encoded(".jpg")
      stub_get("image/png", jpeg)

      assert {:ok, "/uploads/images/" <> filename} =
               Images.import_url("https://example.com/author.png")

      on_exit(fn -> File.rm(Paths.images_disk_path(filename)) end)

      assert Path.extname(filename) == ".jpg"
    end

    test "bytes that are not an image are still a failed download" do
      stub_get("image/png", "<html></html>")

      assert {:error, :failed_to_download_image} =
               Images.import_url("https://example.com/not-really.png")
    end

    test "a non-200 response is a failed download" do
      patch(Req, :get, fn _opts -> {:ok, %Req.Response{status: 404, body: "Not Found"}} end)

      assert {:error, :failed_to_download_image} =
               Images.import_url("https://example.com/gone.png")
    end

    defp stub_get(content_type, body) do
      patch(Req, :get, fn _opts ->
        {:ok,
         %Req.Response{status: 200, headers: %{"content-type" => [content_type]}, body: body}}
      end)
    end

    defp encoded(suffix) do
      {:ok, image} = Image.new(8, 8, color: :red)
      {:ok, binary} = Image.write(image, :memory, suffix: suffix)
      binary
    end
  end
end
