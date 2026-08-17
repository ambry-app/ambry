defmodule AmbryWeb.Admin.MediaLive.EvidenceTest do
  @moduledoc """
  The audiobook form's evidence panel: provider records the operator ticks,
  and the recording's own file, which is evidence nobody has to search for.
  """
  use AmbryWeb.ConnCase, async: false
  use Patch

  import Phoenix.ConnTest, except: [patch: 3]
  import Phoenix.LiveViewTest

  alias Ambry.Media
  alias Ambry.Metadata.Provider

  setup :register_and_log_in_admin_user

  defp result_book(opts \\ []) do
    %Provider.Book{
      provider: "audible",
      id: "B0983R6VP1",
      title: "The Martian",
      publisher: Keyword.get(opts, :publisher),
      cover_url: Keyword.get(opts, :cover_url, "https://example.test/covers/martian.jpg"),
      published: %Provider.PublishedDate{date: ~D[2013-02-11], display_format: :full},
      authors: [%Provider.Contributor{id: "1", name: "Andy Weir", role: "author"}]
    }
  end

  defp patch_search(book \\ nil) do
    book = book || result_book()

    patch(Ambry.Metadata.Providers, :search_books, fn _provider, _query, _opts ->
      {:ok, [book]}
    end)
  end

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

  # `image_path` is validated against the disk, so anything that saves one
  # needs real bytes behind it.
  defp on_disk(filename) do
    path = Ambry.Paths.images_disk_path(filename)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "not really an image, but it exists")
    on_exit(fn -> File.rm(path) end)
    Ambry.Images.web_path(filename)
  end

  defp search(view, fields) do
    view |> form("#research-recording", fields) |> render_submit()
    render_async(view)
  end

  defp tick_first_record(view) do
    view
    |> element(~s{[data-role="record"] input[type="checkbox"]})
    |> render_click()
  end

  describe "accepting a cover proposal" do
    # The chip marked itself chosen and wrote a provenance hint, and then the
    # save posted nothing: the URL input that carries the choice is only
    # rendered for a recording with no cover, so the operator had to delete
    # the old one first and make the same decision twice.
    test "replaces the cover that is already there", %{conn: conn} do
      media = martian()
      old_cover = on_disk("evidence-old-cover.jpg")
      new_cover = on_disk("evidence-new-cover.jpg")
      {:ok, media} = Media.update_media(media, %{image_path: old_cover})

      patch_search()
      patch(Ambry.Images, :import_url, fn _url -> {:ok, new_cover} end)

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
      search(view, %{"title" => "The Martian", "author" => "Andy Weir"})
      tick_first_record(view)

      view |> element(~s{#proposals-image button}) |> render_click()
      view |> form("#media-form", %{"media" => %{}}) |> render_submit()

      assert Media.get_media!(media.id).image_path == new_cover
    end

    # Three ways the chip says it is the one in use — border, tint and a
    # check — and the edit forms showed none of them, because the values that
    # decide it are form params and the check was asking the changeset.
    test "marks the chip chosen, so the click is answered", %{conn: conn} do
      media = martian()
      {:ok, media} = Media.update_media(media, %{image_path: on_disk("evidence-cover-c.jpg")})

      patch_search()

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
      search(view, %{"title" => "The Martian", "author" => "Andy Weir"})
      tick_first_record(view)

      refute has_element?(view, "#proposals-image button .fa-check")

      view |> element(~s{#proposals-image button}) |> render_click()

      assert has_element?(view, "#proposals-image button .fa-check")
    end

    test "records the provider as the source of the new cover", %{conn: conn} do
      media = martian()
      new_cover = on_disk("evidence-cover-b.jpg")
      {:ok, media} = Media.update_media(media, %{image_path: on_disk("evidence-cover-a.jpg")})

      patch_search()
      patch(Ambry.Images, :import_url, fn _url -> {:ok, new_cover} end)

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
      search(view, %{"title" => "The Martian", "author" => "Andy Weir"})
      tick_first_record(view)

      view |> element(~s{#proposals-image button}) |> render_click()
      view |> form("#media-form", %{"media" => %{}}) |> render_submit()

      assert %{"source" => "provider:audible", "locked" => false} =
               Ambry.Provenance.entry(Media.get_media!(media.id), :image_path)
    end
  end

  describe "the recording's own file tags" do
    # Searching is when the operator asks what else this recording could say
    # about itself, so it is when the file is read — not on every page load,
    # which would cost an ffprobe against a NAS to render a form nobody came
    # to curate.
    test "are read when the operator searches, not before", %{conn: conn} do
      media = tagged_media()
      patch_search()

      {:ok, view, html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

      refute html =~ "the file&#39;s tags"

      html = search(view, %{"title" => "The Martian", "author" => "Andy Weir"})

      assert html =~ "the file&#39;s tags"
    end

    # The import form does not offer the file as something to tick, and two
    # vocabularies for one fact is the thing to avoid.
    test "are a source of proposals, never a record in the list", %{conn: conn} do
      media = tagged_media()
      patch_search()

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
      html = search(view, %{"title" => "The Martian", "author" => "Andy Weir"})

      # the provider's record, and only the provider's
      assert html =~ "1 records, 0 ticked"
      refute has_element?(view, ~s{[data-role="record"]}, "the file's tags")
    end

    test "propose the values the file carries, without anything being ticked",
         %{conn: conn} do
      media = tagged_media()
      patch_search()

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
      search(view, %{"title" => "The Martian", "author" => "Andy Weir"})

      assert has_element?(view, "#proposals-media_published button", "2010-08-31")

      assert has_element?(view, "#proposals-media_publisher button") or
               has_element?(view, "#proposals-media_published button")
    end

    # Narrators are credited people, and a chip that resolves a name silently
    # created one when it matched nothing. This form does not create people.
    test "do not propose narrators", %{conn: conn} do
      media = tagged_media()
      patch_search()

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
      search(view, %{"title" => "The Martian", "author" => "Andy Weir"})

      refute has_element?(view, "#proposals-narrators")
      assert Ambry.Repo.aggregate(Ambry.People.Person, :count) == 0
    end

    test "accepting one fills the field and records the file as the source", %{conn: conn} do
      media = tagged_media()
      patch_search()

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
      search(view, %{"title" => "The Martian", "author" => "Andy Weir"})

      view |> element("#proposals-media_published button") |> render_click()
      view |> form("#media-form", %{"media" => %{}}) |> render_submit()

      media = Media.get_media!(media.id)

      assert media.published == ~D[2010-08-31]
      assert %{"source" => "tags"} = Ambry.Provenance.entry(media, :published)
    end

    # Art is a stream in the container rather than a tag, and the import form
    # calls it "Embedded in the file" — the edit form says the same words
    # about the same picture.
    test "offer the file's own cover art, extracted on save", %{conn: conn} do
      media = tagged_media(cover_art: true)
      patch_search()

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
      search(view, %{"title" => "The Martian", "author" => "Andy Weir"})

      assert has_element?(view, "#proposals-image button", "Embedded in the file")

      view |> element("#proposals-image button", "Embedded in the file") |> render_click()
      view |> form("#media-form", %{"media" => %{}}) |> render_submit()

      media = Media.get_media!(media.id)

      assert media.image_path =~ "/uploads/images/"
      assert File.exists?(Ambry.Paths.web_to_disk(media.image_path))
      assert %{"source" => "embedded"} = Ambry.Provenance.entry(media, :image_path)
    end

    # The import form offers a cover that way round — provider covers, then
    # the file's own art — and one order in two places is one thing to learn.
    test "offer the file's own cover last, as the import form does", %{conn: conn} do
      media = tagged_media(cover_art: true)
      patch_search()

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
      search(view, %{"title" => "The Martian", "author" => "Andy Weir"})
      tick_first_record(view)

      row = view |> element("#proposals-image") |> render()

      assert :binary.match(row, "Embedded in the file") > :binary.match(row, "AUDIBLE")
    end

    test "preview the embedded art rather than describing it", %{conn: conn} do
      media = tagged_media(cover_art: true)

      conn = get(conn, ~p"/admin/audiobooks/#{media}/embedded-cover")

      assert conn.status == 200
      assert ["image/" <> _type] = Plug.Conn.get_resp_header(conn, "content-type")
    end

    # A recording whose files are gone says nothing about itself, and the
    # search still has to answer.
    test "are skipped when the file can't be read", %{conn: conn} do
      media = martian()
      patch_search()

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
      html = search(view, %{"title" => "The Martian", "author" => "Andy Weir"})

      refute html =~ "the file&#39;s tags"
      assert html =~ "1 records, 0 ticked"
    end
  end

  describe "going back to the saved value" do
    test "is offered once a field differs, and not before", %{conn: conn} do
      media = martian()
      {:ok, media} = Media.update_media(media, %{publisher: "Podium Audio"})

      patch_search(result_book(publisher: "Crown"))

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
      search(view, %{"title" => "The Martian", "author" => "Andy Weir"})
      tick_first_record(view)

      refute has_element?(view, "#proposals-media_publisher button", "saved")

      view |> element("#proposals-media_publisher button", "Crown") |> render_click()

      assert has_element?(view, "#proposals-media_publisher button", "Podium Audio")
    end

    test "restores the field and drops what would have been recorded", %{conn: conn} do
      media = martian()
      {:ok, media} = Media.update_media(media, %{publisher: "Podium Audio"})

      patch_search(result_book(publisher: "Crown"))

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
      search(view, %{"title" => "The Martian", "author" => "Andy Weir"})
      tick_first_record(view)

      view |> element("#proposals-media_publisher button", "Crown") |> render_click()

      html =
        view
        |> element(~s{#proposals-media_publisher button[phx-click="revert-field"]})
        |> render_click()

      # the field is back, and nothing is pending against it
      assert html =~ "Podium Audio"
      refute html =~ "will record"

      view |> form("#media-form", %{"media" => %{}}) |> render_submit()

      media = Media.get_media!(media.id)
      assert media.publisher == "Podium Audio"
    end

    test "puts a cover back, picture and all", %{conn: conn} do
      media = martian()
      saved_cover = on_disk("evidence-saved-cover.jpg")
      {:ok, media} = Media.update_media(media, %{image_path: saved_cover})

      patch_search()

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
      search(view, %{"title" => "The Martian", "author" => "Andy Weir"})
      tick_first_record(view)

      view |> element(~s{#proposals-image button}) |> render_click()
      view |> element(~s{#proposals-image button[phx-click="revert-field"]}) |> render_click()

      view |> form("#media-form", %{"media" => %{}}) |> render_submit()

      assert Media.get_media!(media.id).image_path == saved_cover
    end
  end

  # A real file carrying real tags, in the recording's own source folder.
  defp tagged_media(opts \\ []) do
    media = insert(:media, book: build(:book))
    folder = Media.Media.source_path(media)
    File.mkdir_p!(folder)

    fixture = tagged_audio(opts)
    file = Path.join(folder, "book" <> Path.extname(fixture))
    File.cp!(fixture, file)

    {:ok, media} = Media.update_media(media, %{source_files: [Ambry.Paths.disk_to_web(file)]})

    Media.get_media!(media.id)
  end
end
