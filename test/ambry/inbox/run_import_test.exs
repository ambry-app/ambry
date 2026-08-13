defmodule Ambry.Inbox.RunImportTest do
  @moduledoc """
  Importing belongs to the server, not to a browser tab.

  It used to run in an async task owned by the form's LiveView, so closing the
  tab killed a multi-gigabyte placement mid-flight, and the operator had to sit
  and watch it either way.

  The end-to-end path — click, queue, drain, imported — is covered by the
  inbox LiveView tests, which own the fixture that puts real audio on disk.
  What is tested here is what only the worker can answer: what it does when
  there is nothing to import, and where a refusal ends up.
  """
  use Ambry.DataCase

  alias Ambry.Inbox
  alias Ambry.Inbox.InboxItem
  alias Ambry.Inbox.RunImport

  describe "perform/1" do
    # The job outlives the row it was queued for: an operator can ignore or
    # delete an item while its import waits behind a slower one.
    test "an item deleted while queued is not an error" do
      assert :ok = perform_job(RunImport, %{inbox_item_id: 0})
    end

    # A refusal is a decision the operator has to see *tomorrow*, and a
    # discarded job is deleted by the pruner within a day. `import_item/1`
    # writes the reason onto the item, so the job reports success — its work
    # is done — and the row carries the message.
    @tag :capture_log
    test "a refusal is recorded on the item rather than discarding the job" do
      item = unsettled_item()

      assert :ok = perform_job(RunImport, %{inbox_item_id: item.id})

      item = Inbox.get_item!(item.id)
      assert item.status == :pending
      assert item.issue
    end
  end

  describe "import_item_async/1" do
    test "queues the work and leaves the library alone until it runs" do
      item = unsettled_item()

      assert {:ok, _job} = Inbox.import_item_async(item)
      assert_enqueued(worker: RunImport, args: %{inbox_item_id: item.id})
      assert Inbox.get_item!(item.id).status == :pending
    end

    # The row lock in `Importer` is what makes a double import safe; this is
    # what stops one being attempted, because the wasted attempt is a whole
    # copy of the release.
    test "queuing twice queues once" do
      item = unsettled_item()

      assert {:ok, first} = Inbox.import_item_async(item)
      assert {:ok, second} = Inbox.import_item_async(item)

      refute first.conflict?
      assert second.conflict?
      assert [_only_one] = all_enqueued(worker: RunImport)
    end

    test "an item already in the library is refused at the door" do
      item = unsettled_item()
      {:ok, item} = Inbox.update_item(item, %{status: :imported})

      assert {:error, :already_imported} = Inbox.import_item_async(item)
    end
  end

  # Deliberately thin: an item with no probe and no draft can only be refused,
  # which is exactly what the refusal tests want, and it needs nothing on disk.
  defp unsettled_item do
    %InboxItem{}
    |> InboxItem.changeset(%{
      path: "/downloads/Nothing Settled Here",
      files: ["/downloads/Nothing Settled Here/book.m4b"]
    })
    |> Repo.insert!()
  end
end
