defmodule Ambry.JobsTest do
  use Ambry.DataCase, async: false

  alias Ambry.Jobs

  describe "summary/0" do
    test "reports every configured queue, including the empty ones" do
      summary = Jobs.summary()

      names = Enum.map(summary.queues, & &1.queue)

      assert "default" in names
      assert "media" in names
      assert "metadata" in names
    end

    test "counts each state under its own queue, and totals them" do
      insert_job(queue: "media", state: "executing")
      insert_job(queue: "media", state: "available")
      insert_job(queue: "metadata", state: "retryable")
      insert_job(queue: "metadata", state: "discarded")

      summary = Jobs.summary()

      media = Enum.find(summary.queues, &(&1.queue == "media"))
      metadata = Enum.find(summary.queues, &(&1.queue == "metadata"))

      assert media.running == 1
      assert media.queued == 1
      assert metadata.retrying == 1
      assert metadata.failed == 1

      assert summary.running == 1
      assert summary.queued == 1
      assert summary.retrying == 1
      assert summary.failed == 1
    end

    test "a queue that is no longer configured still shows what it holds" do
      insert_job(queue: "retired", state: "available")

      summary = Jobs.summary()

      assert Enum.find(summary.queues, &(&1.queue == "retired")).queued == 1
    end

    test "completed jobs are not work" do
      insert_job(queue: "media", state: "completed")

      summary = Jobs.summary()

      refute Jobs.busy?(summary)
      assert summary.running == 0
    end
  end

  describe "busy?/1" do
    test "a job waiting to retry counts as busy" do
      assert Jobs.busy?(%{running: 0, queued: 0, retrying: 1, failed: 0})
    end

    test "a failure is not busy — nothing is going to happen" do
      refute Jobs.busy?(%{running: 0, queued: 0, retrying: 0, failed: 3})
    end
  end

  describe "recent_failures/1" do
    test "returns what gave up, newest first, with the last error's first line" do
      insert_job(
        queue: "media",
        state: "discarded",
        worker: "Ambry.Inbox.RunImport",
        discarded_at: ~N[2026-08-01 00:00:00],
        errors: [%{"error" => "** (RuntimeError) older\n    stacktrace"}]
      )

      insert_job(
        queue: "media",
        state: "discarded",
        worker: "Ambry.Inbox.RunProbe",
        discarded_at: ~N[2026-08-02 00:00:00],
        errors: [
          %{"error" => "** (RuntimeError) first try\n    stack"},
          %{"error" => "** (RuntimeError) gave up\n    stack"}
        ]
      )

      assert [newest, older] = Jobs.recent_failures()

      assert newest.worker == "Ambry.Inbox.RunProbe"
      assert newest.error == "** (RuntimeError) gave up"
      assert older.worker == "Ambry.Inbox.RunImport"
    end

    test "a job that failed without recording an error doesn't crash the list" do
      insert_job(queue: "media", state: "cancelled", errors: [])

      assert [failure] = Jobs.recent_failures()
      assert failure.error == nil
    end

    test "only failures are listed" do
      insert_job(queue: "media", state: "executing")
      insert_job(queue: "media", state: "completed")

      assert Jobs.recent_failures() == []
    end
  end
end
