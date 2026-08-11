defmodule Ambry.Media.Chapters.FromFilesTest do
  @moduledoc """
  Chapter markers read out of the files, at scan time.

  The interesting cases are all about *titles*: the markers themselves are
  either there or they aren't, but a chapter-per-file release's names are
  usually the book's title with a counter attached, and taking those
  literally produces forty near-identical chapter names that look like data.
  """
  use ExUnit.Case, async: true

  alias Ambry.Media.Chapters.FromFiles

  describe "a single file" do
    test "takes its embedded markers, titles and all" do
      probe = probe("book.m4b", chapters: [{0, "Opening Credits"}, {120, "Chapter One"}])

      assert {[first, second], :embedded} = FromFiles.extract([probe], tracks([0]))

      assert first.title == "Opening Credits"
      assert first.title_source == :embedded
      assert Decimal.equal?(first.time, 0)
      assert second.title == "Chapter One"
      assert Decimal.equal?(second.time, 120)
    end

    test "offers nothing when the file carries no markers" do
      assert {[], nil} = FromFiles.extract([probe("book.mp3")], tracks([0]))
    end

    test "falls back to the floor for a marker with no title of its own" do
      probe = probe("book.m4b", chapters: [{0, "Prologue"}, {120, "  "}])

      assert {[_first, second], :embedded} = FromFiles.extract([probe], tracks([0]))

      assert second.title == "Chapter 2"
      assert second.title_source == :generated
    end
  end

  describe "a chapter-per-file release" do
    test "makes each file's start a marker, titled from the filenames" do
      probes = [
        probe("01 - Prologue.mp3"),
        probe("02 - The Crossing.mp3"),
        probe("03 - Nightfall.mp3")
      ]

      assert {chapters, :file_boundaries} = FromFiles.extract(probes, tracks([0, 600, 1300]))

      assert Enum.map(chapters, & &1.title) == ["Prologue", "The Crossing", "Nightfall"]
      assert Enum.all?(chapters, &(&1.title_source == :filename))
      assert Enum.map(chapters, &Decimal.to_integer(&1.time)) == [0, 600, 1300]
    end

    test "prefers each file's own title tag over its name" do
      probes = [
        probe("01.mp3", title: "Prologue"),
        probe("02.mp3", title: "The Crossing")
      ]

      assert {chapters, :file_boundaries} = FromFiles.extract(probes, tracks([0, 600]))

      assert Enum.map(chapters, & &1.title) == ["Prologue", "The Crossing"]
      assert Enum.all?(chapters, &(&1.title_source == :embedded))
    end

    # Measured on the operator's own library: every file of "This Is How You
    # Lose the Time War" is tagged "NN-28 This Is How You Lose the Time War".
    # Twenty-eight chapters of that is worse than "Chapter N", because it
    # looks like somebody chose it.
    test "rejects names that are the book's title with a counter attached" do
      probes =
        for index <- 1..4 do
          padded = index |> to_string() |> String.pad_leading(3, "0")

          probe("#{padded} -  #{index}-4 This Is How You Lose the Time War.mp3",
            title: "#{index}-4 This Is How You Lose the Time War"
          )
        end

      assert {chapters, :file_boundaries} =
               FromFiles.extract(probes, tracks([0, 600, 1200, 1800]))

      assert Enum.map(chapters, & &1.title) ==
               ["Chapter 1", "Chapter 2", "Chapter 3", "Chapter 4"]

      assert Enum.all?(chapters, &(&1.title_source == :generated))
    end

    test "rejects names that are already just a chapter number" do
      probes = for index <- 1..3, do: probe("Chapter #{index}.mp3")

      assert {chapters, :file_boundaries} = FromFiles.extract(probes, tracks([0, 600, 1200]))

      assert Enum.all?(chapters, &(&1.title_source == :generated))
    end

    # Half a named chapter list reads as data where it's really a gap, so the
    # tags are taken whole or not at all.
    test "ignores title tags when only some files carry one" do
      probes = [
        probe("01 - Prologue.mp3", title: "Prologue"),
        probe("02 - The Crossing.mp3")
      ]

      assert {chapters, :file_boundaries} = FromFiles.extract(probes, tracks([0, 600]))

      assert Enum.all?(chapters, &(&1.title_source == :filename))
      assert Enum.map(chapters, & &1.title) == ["Prologue", "The Crossing"]
    end
  end

  describe "a multi-file release whose files carry their own markers" do
    test "shifts each file's markers onto the book timeline" do
      probes = [
        probe("part1.m4b", chapters: [{0, "One"}, {300, "Two"}]),
        probe("part2.m4b", chapters: [{0, "Three"}, {200, "Four"}])
      ]

      assert {chapters, :embedded} = FromFiles.extract(probes, tracks([0, 900]))

      assert Enum.map(chapters, &Decimal.to_integer(&1.time)) == [0, 300, 900, 1100]
      assert Enum.map(chapters, & &1.title) == ["One", "Two", "Three", "Four"]
    end

    test "falls back to boundaries when only some files carry markers" do
      probes = [
        probe("01 - Prologue.m4b", chapters: [{0, "One"}]),
        probe("02 - The Crossing.m4b")
      ]

      assert {chapters, :file_boundaries} = FromFiles.extract(probes, tracks([0, 900]))

      assert Enum.map(chapters, & &1.title) == ["Prologue", "The Crossing"]
    end
  end

  test "no probes at all" do
    assert {[], nil} = FromFiles.extract([], [])
  end

  defp probe(name, opts \\ []) do
    chapters =
      opts
      |> Keyword.get(:chapters, [])
      |> Enum.map(fn {time, title} -> %{time: Decimal.new(time), title: title} end)

    %{
      path: "/downloads/release/#{name}",
      chapters: chapters,
      tags: %Ambry.Media.Scanner.Tags{title: opts[:title]}
    }
  end

  defp tracks(offsets), do: Enum.map(offsets, &%{start_offset: Decimal.new(&1)})
end
