defmodule Ambry.Inbox.UndoTest do
  @moduledoc """
  Undoing an import, which is the loop the staged form is designed in: run an
  awkward release through it, see what reads wrong, put it back, run it again.
  """
  use Ambry.DataCase

  alias Ambry.Books
  alias Ambry.Inbox
  alias Ambry.Media
  alias Ambry.People
  alias Ambry.Repo

  describe "undoing an import" do
    test "deletes what the import created and puts the item back in the queue" do
      %{item: item, source: source} = downloads_item()

      {:ok, media} = Inbox.import_item(item)
      item = Inbox.get_item!(item.id)
      [placed] = Media.get_media!(media.id).source_files

      assert {:ok, summary} = Inbox.undo_import(item)

      # the records
      assert Repo.get(Media.Media, media.id) == nil
      assert Books.list_books() |> elem(0) == []
      assert People.list_people() |> elem(0) == []

      # the item, with the decisions it was imported with
      assert %{status: :pending, media_id: nil} = summary.item
      assert summary.item.draft.work.title.value == "The Way of Kings"

      # the bytes: the library copy goes, the file it was found as stays
      assert %{success: 1} = Oban.drain_queue(queue: :default)
      refute File.exists?(placed)
      assert File.exists?(source)
    end

    test "says what it deleted, in words" do
      %{item: item} = downloads_item()
      {:ok, _media} = Inbox.import_item(item)

      assert {:ok, summary} = Inbox.undo_import(Inbox.get_item!(item.id))

      assert "the audiobook" in summary.deleted
      assert "the book" in summary.deleted
      assert "the person Brandon Sanderson" in summary.deleted
      assert summary.kept == []
    end

    test "the same release can then be imported again" do
      %{item: item} = downloads_item()

      {:ok, first} = Inbox.import_item(item)
      {:ok, _summary} = Inbox.undo_import(Inbox.get_item!(item.id))
      assert %{success: 1} = Oban.drain_queue(queue: :default)

      assert {:ok, second} = Inbox.import_item(Inbox.get_item!(item.id))
      assert second.id != first.id
      assert Inbox.get_item!(item.id).status == :imported
    end

    # Nothing about undoing one import may damage another. A book that has
    # since grown a second recording is the case that would.
    test "keeps a book another audiobook has joined, and says so" do
      %{item: item} = downloads_item()
      {:ok, media} = Inbox.import_item(item)

      # a second recording of the same book, as a re-import would make
      insert(:media, book_id: media.book_id)

      assert {:ok, summary} = Inbox.undo_import(Inbox.get_item!(item.id))

      assert Repo.get(Books.Book, media.book_id)
      assert "the book: another audiobook uses it" in summary.kept
      # the person is exclusive to that book's author, so they stay too
      assert Enum.any?(summary.kept, &String.starts_with?(&1, "the person"))
    end

    # A `move` policy leaves the library copy as the only copy. Deleting it
    # would not be an undo.
    test "refuses when the files it was found as are gone" do
      %{item: item, source: source} = downloads_item(policy: :move)

      {:ok, _media} = Inbox.import_item(item)
      refute File.exists?(source)

      assert {:error, :source_files_missing} = Inbox.undo_import(Inbox.get_item!(item.id))
      assert Inbox.get_item!(item.id).status == :imported
    end

    test "refuses an item that was never imported" do
      %{item: item} = downloads_item()

      assert {:error, :not_imported} = Inbox.undo_import(item)
    end

    # The button is the explanation; this is the enforcement.
    test "refuses entirely on a build without the flag" do
      %{item: item} = downloads_item()
      {:ok, _media} = Inbox.import_item(item)

      Application.put_env(:ambry, :allow_undo_import, false)
      on_exit(fn -> Application.put_env(:ambry, :allow_undo_import, true) end)

      refute Inbox.undo_available?()
      assert {:error, :undo_unavailable} = Inbox.undo_import(Inbox.get_item!(item.id))
      assert Inbox.get_item!(item.id).status == :imported
    end
  end

  # The same arrangement `ManagedImportTest` uses: a watched downloads folder
  # bringing files into a library root, settled the way the form would leave
  # it.
  defp downloads_item(opts \\ []) do
    root = new_dir("root")
    root_record = insert(:root, path: root, name: "Library")

    downloads = new_dir("downloads")
    release = Path.join(downloads, "The Way of Kings [M4B]")
    File.mkdir_p!(release)

    source = Path.join(release, "book.m4b")
    File.cp!(tagged_audio(), source)

    watched = insert(:source, path: downloads, name: "Downloads #{Ecto.UUID.generate()}")

    # The policy lives on the pairing now, so a test that wants a particular
    # one seeds it the way an earlier import would have.
    {:ok, _memory} =
      Ambry.Library.remember_placement(watched, root_record, Keyword.get(opts, :policy, :copy))

    {:ok, _counts} = Inbox.discover(watched)
    {[item], false} = Inbox.list_items()
    {:ok, item} = Inbox.probe_item(item)

    %{item: settle(item), root: root, source: source}
  end

  defp new_dir(prefix) do
    dir = Ambry.Paths.source_media_disk_path("#{prefix}-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)
    dir
  end
end
