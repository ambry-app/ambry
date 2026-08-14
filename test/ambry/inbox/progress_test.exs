defmodule Ambry.Inbox.ProgressTest do
  @moduledoc """
  What is happening to an inbox item right now.

  The whole difficulty is that the job table is not the answer. Oban prunes
  jobs after a day, so an item from last week has no jobs and is perfectly
  fine — "no job" has to mean "look at the item itself", not "nothing
  happened".
  """
  use Ambry.DataCase

  alias Ambry.Inbox
  alias Ambry.Inbox.Progress

  describe "status/1 from the job table" do
    test "a queued job reads as queued" do
      item = item()
      job(item, :available)

      assert Progress.status(item) == :queued
    end

    test "a running job reads as working" do
      item = item()
      job(item, :executing)

      assert Progress.status(item) == :working
    end

    # These workers run max_attempts: 1, so a failure goes straight to
    # discarded rather than retrying.
    test "a discarded job reads as failed" do
      item = item()
      job(item, :discarded)

      assert Progress.status(item) == :failed
    end

    # Running beats waiting: an item with a finished probe and a queued match
    # is still being worked on.
    test "the most active job wins" do
      item = item()
      job(item, :completed)
      job(item, :executing)

      assert Progress.status(item) == :working
    end
  end

  describe "status/1 with no jobs left" do
    # The pruner deletes jobs after a day. An item probed and matched last
    # week is done, not broken.
    test "a fully processed item reads as done" do
      item = item(probe: %{"duration" => 1}, matches: %{"work" => %{}})

      assert Progress.status(item) == :done
    end

    test "an item that was never probed reads as never ran" do
      assert Progress.status(item()) == :never_ran
    end

    test "an item probed but never matched reads as incomplete" do
      item = item(probe: %{"duration" => 1})

      assert Progress.status(item) == :incomplete
    end

    # An issue outlives every job, which is the entire reason failures get
    # written onto the item.
    test "a recorded issue wins over the item's contents" do
      item = item(probe: %{"duration" => 1}, matches: %{}, issue: "no publication date")

      assert Progress.status(item) == :issue
    end
  end

  describe "statuses/1" do
    test "answers for a whole page in one go" do
      queued = item()
      job(queued, :available)
      done = item(probe: %{"d" => 1}, matches: %{"work" => %{}})
      fresh = item()

      statuses = Progress.statuses([queued, done, fresh])

      assert statuses[queued.id] == :queued
      assert statuses[done.id] == :done
      assert statuses[fresh.id] == :never_ran
    end

    test "handles an empty page" do
      assert Progress.statuses([]) == %{}
    end

    # Jobs are matched on the item id inside the args, so one item's jobs must
    # never be read as another's.
    test "doesn't attribute one item's jobs to another" do
      mine = item()
      theirs = item()
      job(theirs, :executing)

      statuses = Progress.statuses([mine, theirs])

      assert statuses[mine.id] == :never_ran
      assert statuses[theirs.id] == :working
    end
  end

  describe "import failures" do
    # A flash lasts one page load and a discarded job lasts a day; the
    # operator needs to know tomorrow.
    test "are written onto the item" do
      item = item(files: [], probe: %{"d" => 1})

      assert {:error, :no_audio_files} = Inbox.import_item(item)

      assert Repo.reload(item).issue == "Couldn't add this to the library."
    end

    test "say what to do about a cross-filesystem refusal" do
      message = Inbox.describe_error({:cross_filesystem, "/a/x.m4b", "/b/x.m4b"})

      assert message =~ "different filesystems"
      assert message =~ "copy or move"
    end
  end

  defp item(attrs \\ []) do
    {:ok, item} =
      %Ambry.Inbox.InboxItem{}
      |> Ambry.Inbox.InboxItem.changeset(
        Enum.into(attrs, %{
          path: "release-#{Ecto.UUID.generate()}",
          files: ["x/book.m4b"],
          status: :pending,
          source_id: insert(:source).id
        })
      )
      |> Repo.insert()

    item
  end

  defp job(item, state) do
    Repo.insert_all("oban_jobs", [
      %{
        state: to_string(state),
        queue: "media",
        worker: "Ambry.Inbox.RunProbe",
        args: %{"inbox_item_id" => item.id},
        inserted_at: DateTime.utc_now(:second),
        scheduled_at: DateTime.utc_now(:second)
      }
    ])

    :ok
  end
end
