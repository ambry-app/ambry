defmodule AmbryWeb.Admin.ProbeFactsTest do
  @moduledoc """
  What the probe found, as the queue and the import form both read it.

  The line exists to be compared: two imports of one audiobook are told apart
  by these facts and by nothing a filename shows.
  """
  use ExUnit.Case, async: true

  import AmbryWeb.Admin.Components, only: [probe_facts: 1, probe_facts: 2]

  # The pair production actually got wrong. Same recording to within four
  # seconds out of 28.7 hours, half the bytes, and the file was called
  # `This Inevitable Ruin.m4b` on both sides.
  test "tells two rips of one recording apart" do
    kept = %{"size" => 1_639_966_385, "duration" => "103238.043333", "codec" => "aac"}
    worse = %{"size" => 819_378_051, "duration" => "103242.001000", "codec" => "aac"}

    assert "127 kbps" in probe_facts(kept)
    assert "63 kbps" in probe_facts(worse)
  end

  test "reads as one line, duration first" do
    facts =
      probe_facts(%{
        "duration" => "3600.0",
        "size" => 28_800_000,
        "codec" => "aac",
        "chapters" => 12
      })

    assert Enum.join(facts, " · ") =~ "1:00:00"
    assert Enum.join(facts, " · ") =~ "64 kbps"
    assert Enum.join(facts, " · ") =~ "aac · 12 chapters"
  end

  # The one thing the two surfaces are allowed to disagree about: the queue
  # says it as a count chip on the row's facts rail, the form says it in the
  # line.
  test "the file count is the caller's to ask for" do
    probe = %{"duration" => "3600.0", "files" => 40}

    refute "40 files" in probe_facts(probe)
    assert "40 files" in probe_facts(probe, files: true)
  end

  test "one file is not worth saying" do
    refute "1 files" in probe_facts(%{"duration" => "3600.0", "files" => 1}, files: true)
  end

  # A probe that measured no duration cannot yield a rate, and a rate
  # invented from a divide by zero would be worse than its absence.
  test "says nothing rather than guessing" do
    refute Enum.any?(probe_facts(%{"size" => 100, "duration" => "0.0"}), &(&1 =~ "kbps"))
    refute Enum.any?(probe_facts(%{"size" => 100}), &(&1 =~ "kbps"))
    refute Enum.any?(probe_facts(%{"duration" => "60.0"}), &(&1 =~ "kbps"))
    assert probe_facts(nil) == []
  end
end
