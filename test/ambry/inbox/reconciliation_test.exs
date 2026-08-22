defmodule Ambry.Inbox.ReconciliationTest do
  @moduledoc """
  Noticing that an inbox item's files stopped being there.

  The queue's whole failure mode here was silence: an item whose files were
  deleted kept its file list and stayed importable until Add failed inside
  placement, after every decision had been made.
  """
  use Ambry.DataCase

  alias Ambry.Inbox
  alias Ambry.Inbox.Reconciliation

  describe "reconcile/1" do
    test "an item whose files are all there is unchanged" do
      %{item: item} = queued_item()

      assert {:ok, :unchanged} = Reconciliation.reconcile(item)
      refute Inbox.get_item!(item.id).missing_since
    end

    test "an item whose file was deleted is missing" do
      %{item: item, files: [file]} = queued_item()
      File.rm!(file)

      assert {:ok, :missing} = Reconciliation.reconcile(item)
      assert Inbox.get_item!(item.id).missing_since
    end

    # An item is its files. A release that has lost one of two cannot be
    # imported as the recording the draft describes.
    test "losing one file of several is missing" do
      %{item: item, files: [one, _two]} = queued_item(files: ["a.m4b", "b.m4b"])
      File.rm!(one)

      assert {:ok, :missing} = Reconciliation.reconcile(item)
    end

    # The reason this is a timestamp and not a status: files come back.
    test "an item whose files come back is healed" do
      %{item: item, files: [file]} = queued_item()
      contents = File.read!(file)
      File.rm!(file)

      assert {:ok, :missing} = Reconciliation.reconcile(item)

      File.write!(file, contents)
      item = Inbox.get_item!(item.id)

      assert {:ok, :healed} = Reconciliation.reconcile(item)
      refute Inbox.get_item!(item.id).missing_since
    end

    test "an item already known to be missing is not restamped" do
      %{item: item, files: [file]} = queued_item()
      File.rm!(file)

      assert {:ok, :missing} = Reconciliation.reconcile(item)
      first = Inbox.get_item!(item.id).missing_since

      assert {:ok, :unchanged} = Reconciliation.reconcile(Inbox.get_item!(item.id))
      assert Inbox.get_item!(item.id).missing_since == first
    end
  end

  describe "reconcile_source/1" do
    # The property that keeps an unplugged NAS from rewriting the queue. A
    # source that cannot be read is not a source full of missing items, and
    # one that comes back must not need a repair pass.
    test "an unreachable source is not checked at all" do
      %{item: item, source: source, downloads: downloads} = queued_item()

      File.rm_rf!(downloads)

      assert {:error, :source_unreachable} = Reconciliation.reconcile_source(source)
      refute Inbox.get_item!(item.id).missing_since
    end

    test "counts what it found" do
      %{item: item, source: source, files: [file]} = queued_item()
      File.rm!(file)

      assert {:ok, %{checked: 1, missing: 1, healed: 0}} = Reconciliation.reconcile_source(source)
      assert Inbox.get_item!(item.id).missing_since
    end
  end

  describe "importing a missing item" do
    # Refused before the importer is entered, rather than deep inside
    # placement after the curation is done.
    test "is refused" do
      %{item: item, files: [file]} = queued_item()
      File.rm!(file)
      {:ok, :missing} = Reconciliation.reconcile(item)

      assert {:error, :files_missing} = item.id |> Inbox.get_item!() |> Inbox.import_item()
    end
  end

  defp queued_item(opts \\ []) do
    downloads = Path.join(Ambry.Paths.source_media_disk_path("watched"), Ecto.UUID.generate())
    release = Path.join(downloads, "The Way of Kings [M4B]")
    File.mkdir_p!(release)

    files =
      opts
      |> Keyword.get(:files, ["book.m4b"])
      |> Enum.map(fn name ->
        path = Path.join(release, name)
        File.cp!(tagged_audio(), path)
        path
      end)

    source = insert(:source, path: downloads, name: "Downloads #{Ecto.UUID.generate()}")
    {:ok, _counts} = Inbox.discover(source)
    {[item], false} = Inbox.list_items(filter: "Way of Kings")

    %{item: Inbox.get_item!(item.id), source: source, files: files, downloads: downloads}
  end
end
