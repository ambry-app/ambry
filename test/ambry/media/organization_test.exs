defmodule Ambry.Media.OrganizationTest do
  @moduledoc """
  Keeping a managed recording's files where the naming template says.

  A tree organized once at import drifts the moment anything is corrected —
  fix a title, reorder the authors, add the series you forgot — and the
  folder still says what it said the day the file landed.
  """
  use Ambry.DataCase

  alias Ambry.Books
  alias Ambry.Media.Organization
  alias Ambry.Repo
  alias Ambry.Settings

  describe "organize/1" do
    test "moves the file when the book's title changed" do
      %{media: media, root: root, file: file} = organized_media()

      {:ok, _book} = Books.update_book(Books.get_book!(media.book_id), %{title: "Oathbringer"})
      media = reload(media)

      assert {:ok, :moved} = Organization.organize(media)

      moved = Path.join([root, "Brandon Sanderson", "Oathbringer (2010)", "Oathbringer.m4b"])
      assert File.read!(moved) == "audio"
      refute File.exists?(file)

      media = reload(media)
      assert media.source_files == [moved]
      assert media.source_path == Path.dirname(moved)
      assert [%{path: ^moved}] = media.media_tracks
    end

    test "does nothing when the file is already where it belongs" do
      %{media: media, file: file} = organized_media()

      assert {:ok, :noop} = Organization.organize(media)
      assert File.exists?(file)
    end

    # Regression: destination/3 used to render the filename without the part
    # suffix, so re-organizing one part of a set "corrected" it onto its
    # sibling's path.
    test "a part of a set keeps its part suffix" do
      %{media: media, folder: folder, file: file} = organized_media()

      part_file = Path.join(folder, "The Way of Kings - Part 2 of 3.m4b")
      File.rename!(file, part_file)

      group = insert(:recording_group, parts_total: 3)
      [track] = media.media_tracks
      {:ok, _track} = track |> Ecto.Changeset.change(%{path: part_file}) |> Repo.update()

      media
      |> Ecto.Changeset.change(%{
        part_number: 2,
        recording_group_id: group.id,
        source_files: [part_file]
      })
      |> Repo.update!()

      assert {:ok, :noop} = Organization.organize(reload(media))
      assert File.exists?(part_file)
    end

    # The folder the file left shouldn't stand around empty, but the root
    # itself is configuration and must survive.
    test "prunes the folders it emptied, but never the root" do
      %{media: media, root: root} = organized_media()

      {:ok, _book} = Books.update_book(Books.get_book!(media.book_id), %{title: "Oathbringer"})

      assert {:ok, :moved} = Organization.organize(reload(media))

      refute File.dir?(Path.join([root, "Brandon Sanderson", "The Way of Kings (2010)"]))
      assert File.dir?(Path.join(root, "Brandon Sanderson"))
      assert File.dir?(root)
    end

    # External custody promises Ambry never writes to those files, and a
    # rename is a write.
    test "never moves an external recording" do
      %{media: media, file: file} = organized_media(custody: :external)

      {:ok, _book} = Books.update_book(Books.get_book!(media.book_id), %{title: "Oathbringer"})

      assert {:ok, :noop} = Organization.organize(reload(media))
      assert File.exists?(file)
    end

    # The legacy uploads library is `managed` but isn't template-organized —
    # it's Phase 4's to migrate, not this function's to rearrange.
    test "never moves a managed recording that lives outside a library root" do
      %{media: media, file: file} = organized_media(register_root: false)

      assert {:ok, :noop} = Organization.organize(reload(media))
      assert File.exists?(file)
    end

    # `/data/library-old` is not inside `/data/library`, however much the
    # string says otherwise.
    test "matches the root on a path boundary, not a bare prefix" do
      %{media: media, file: file, root: root} = organized_media(register_root: false)
      insert(:root, path: root <> "-elsewhere")

      assert {:ok, :noop} = Organization.organize(reload(media))
      assert File.exists?(file)
    end

    test "follows a changed template" do
      %{media: media, root: root} = organized_media()
      {:ok, _setting} = Settings.set_library_naming_template("{title}")

      assert {:ok, :moved} = Organization.organize(reload(media))

      assert File.read!(Path.join([root, "The Way of Kings", "The Way of Kings.m4b"])) == "audio"
    end

    # Two recordings rendering to one path is a curation problem the operator
    # has to see; quietly appending " (2)" would hide it forever.
    test "refuses when something already occupies the new path" do
      %{media: media, root: root, file: file} = organized_media()

      occupied = Path.join([root, "Brandon Sanderson", "Oathbringer (2010)", "Oathbringer.m4b"])
      File.mkdir_p!(Path.dirname(occupied))
      File.write!(occupied, "someone else")

      {:ok, _book} = Books.update_book(Books.get_book!(media.book_id), %{title: "Oathbringer"})

      assert {:error, {:destination_exists, ^occupied}} = Organization.organize(reload(media))
      assert File.read!(occupied) == "someone else"
      assert File.exists?(file)
    end

    # Reconciliation's job to notice and record. Moving a file that isn't
    # there would only turn one problem into two.
    test "refuses when the file it was going to move has vanished" do
      %{media: media, file: file} = organized_media()
      File.rm!(file)

      {:ok, _book} = Books.update_book(Books.get_book!(media.book_id), %{title: "Oathbringer"})

      assert {:error, {:source_missing, ^file}} = Organization.organize(reload(media))
    end
  end

  describe "organize_all/0" do
    test "counts what moved and what was already right" do
      %{media: media} = organized_media()
      {:ok, _book} = Books.update_book(Books.get_book!(media.book_id), %{title: "Oathbringer"})

      assert {:ok, %{moved: 1, noop: 0, failed: 0}} = Organization.organize_all()
      assert {:ok, %{moved: 0, noop: 1, failed: 0}} = Organization.organize_all()
    end
  end

  defp organized_media(opts \\ []) do
    root = new_dir("root")

    if Keyword.get(opts, :register_root, true) do
      insert(:root, path: root)
    end

    author = insert(:author, name: "Brandon Sanderson")

    book =
      insert(:book,
        title: "The Way of Kings",
        published: ~D[2010-08-31],
        published_format: :full,
        book_authors: [build(:book_author, author: author, position: 0)]
      )

    folder = Path.join([root, "Brandon Sanderson", "The Way of Kings (2010)"])
    File.mkdir_p!(folder)
    file = Path.join(folder, "The Way of Kings.m4b")
    File.write!(file, "audio")

    media =
      insert(:media,
        book: book,
        # the recording's own date wins over the book's in the template, and
        # the factory would otherwise pick a random one
        published: ~D[2010-08-31],
        custody: Keyword.get(opts, :custody, :managed),
        source_path: folder,
        source_files: [file],
        mp4_path: nil,
        hls_path: nil,
        mpd_path: nil,
        media_tracks: [build(:media_track, path: file)]
      )

    %{media: reload(media), root: root, file: file, folder: folder, book: book}
  end

  defp reload(media) do
    media.id
    |> then(&Repo.get!(Ambry.Media.Media, &1))
    |> Repo.preload([:media_tracks, book: [book_authors: :author, series_books: :series]])
  end

  defp new_dir(prefix) do
    dir = Ambry.Paths.source_media_disk_path("#{prefix}-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)
    dir
  end
end
