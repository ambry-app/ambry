defmodule Ambry.JobsTest do
  use Ambry.DataCase, async: false

  alias Ambry.Jobs
  alias Ambry.Jobs.PubSub.JobActivity

  describe "summary/0" do
    test "reports every configured queue, including the empty ones" do
      summary = Jobs.summary()

      names = Enum.map(summary.queues, & &1.queue)

      assert "default" in names
      assert "images" in names
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

  describe "subscribe/0 and the telemetry bridge" do
    # The whole reason the header indicator is not on a three-second timer.
    # If this stops working the display silently degrades to whatever the
    # slow heartbeat catches, which is the kind of regression nobody
    # notices for a month.
    setup do
      :ok = Jobs.attach_telemetry()
      :ok = Jobs.subscribe()
    end

    test "a job starting reaches a subscriber" do
      emit(:start, "metadata")

      assert_receive %JobActivity{event: :start, queue: "metadata"}
    end

    test "a job finishing reaches a subscriber" do
      emit(:stop, "media")

      assert_receive %JobActivity{event: :stop, queue: "media"}
    end

    test "a job blowing up reaches a subscriber" do
      emit(:exception, "media")

      assert_receive %JobActivity{event: :exception, queue: "media"}
    end

    test "attaching twice is not an error" do
      assert :ok = Jobs.attach_telemetry()
    end
  end

  # A real `%Oban.Job{}` and the metadata Oban actually publishes, because
  # ours is not the only handler on these events. A half-built map crashed
  # Sentry's Oban reporter, and a telemetry handler that raises is
  # **detached globally** — so a lazy fixture here silently turned off error
  # reporting for every test after it.
  defp emit(event, queue) do
    job = %Oban.Job{
      id: System.unique_integer([:positive]),
      args: %{},
      queue: queue,
      worker: "Ambry.Inbox.RunProbe",
      attempt: 1,
      max_attempts: 3,
      tags: [],
      errors: []
    }

    metadata =
      %{job: job, conf: Oban.config(), state: :success, result: :ok}
      |> Map.merge(exception_metadata(event))

    :telemetry.execute([:oban, :job, event], %{duration: 1, queue_time: 1}, metadata)
  end

  defp exception_metadata(:exception) do
    %{
      state: :failure,
      kind: :error,
      reason: %RuntimeError{message: "boom"},
      stacktrace: [],
      error: %RuntimeError{message: "boom"}
    }
  end

  defp exception_metadata(_event), do: %{}

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
