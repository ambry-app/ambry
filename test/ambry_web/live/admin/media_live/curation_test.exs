defmodule AmbryWeb.Admin.MediaLive.CurationTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Media

  setup :register_and_log_in_admin_user

  defp martian do
    book =
      insert(:book,
        title: "The Martian",
        book_authors: [
          build(:book_author, author: build(:author, name: "Andy Weir", person: build(:person)))
        ]
      )

    insert(:media, book: book)
  end

  # `image_path` is validated against the disk, so a preview test needs real
  # bytes behind the paths.
  defp on_disk(filename) do
    path = Ambry.Paths.images_disk_path(filename)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "not really an image, but it exists")
    on_exit(fn -> File.rm(path) end)
    Ambry.Images.web_path(filename)
  end

  describe "the re-search form" do
    # A bare title is how "The Martian" comes back as study guides and
    # conversation starters — Audible takes `author` as a real parameter, and
    # the scorer needs it to tell a content farm's companion work from the
    # book. The form rendered the input and left it empty.
    test "arrives carrying the book's author", %{conn: conn} do
      media = martian()

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

      assert has_element?(view, "form#research-recording input[name='author'][value='Andy Weir']")

      assert has_element?(
               view,
               "form#research-recording input[name='title'][value='The Martian']"
             )
    end
  end

  describe "the cover preview" do
    # The publisher's embedded art is whatever they embedded: one Martian
    # import wrote 753KB of TIFF into a file named `.jpg`, so the form showed
    # a broken image while reporting five thumbnails generated. libvips reads
    # by content, so the thumbnails were fine all along — only the original,
    # which is what the form rendered, was a lie.
    test "renders the derived size and zooms to the original", %{conn: conn} do
      media = martian()

      original = on_disk("curation-original.jpg")
      large = on_disk("curation-derived-lg.webp")

      {:ok, media} =
        Media.update_media(media, %{
          image_path: original,
          thumbnails: %{
            extra_small: "/uploads/images/curation-derived-xs.webp",
            small: "/uploads/images/curation-derived-sm.webp",
            medium: "/uploads/images/curation-derived-md.webp",
            large: large,
            extra_large: "/uploads/images/curation-derived-xl.webp",
            original: original,
            thumbhash: "CPgBBQCorJNo",
            blurhash: "L5D9Co01Bo"
          }
        })

      {:ok, _view, html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
      doc = Floki.parse_document!(html)

      assert [^large] = doc |> Floki.find("#image-#{media.id}-preview") |> Floki.attribute("src")
      assert original in (doc |> Floki.find("[data-zoomable]") |> Floki.attribute("data-full"))
    end

    # A freshly chosen image has no thumbnails yet, and the saved record's
    # describe the picture it is replacing.
    test "falls back to the raw path when the thumbnails are of another image",
         %{conn: conn} do
      media = martian()
      raw = on_disk("curation-no-thumbs.jpg")
      {:ok, media} = Media.update_media(media, %{image_path: raw})

      {:ok, _view, html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

      assert [^raw] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#image-#{media.id}-preview")
               |> Floki.attribute("src")
    end
  end
end
