defmodule Ambry.Media.Chapters.MergeTest do
  @moduledoc """
  Pouring titles onto markers.

  The cases here are the ones the roadmap's 1h names: equal lists merge
  index-wise, unequal ones align by duration, and a retail edition's extra
  credits entries are absorbed rather than shifting everything after them.
  """
  use ExUnit.Case, async: true

  alias Ambry.Media.Chapters.Merge
  alias Ambry.Media.Media.Chapter

  describe "titles/3 with matching lists" do
    test "merges index-wise when the lists are the same length" do
      markers = markers([0, 100, 200])
      incoming = [titled(0, "Prologue"), titled(90, "Chapter 1"), titled(210, "Chapter 2")]

      assert {chapters, _alignment} = Merge.titles(markers, incoming)

      assert Enum.map(chapters, & &1.title) == ["Prologue", "Chapter 1", "Chapter 2"]
      assert Enum.all?(chapters, &(&1.title_source == :provider))
    end

    test "never moves a marker" do
      markers = markers([0, 100, 200])
      # Times a full minute out, which is what accumulated drift looks like.
      incoming = [titled(0, "A"), titled(160, "B"), titled(320, "C")]

      assert {chapters, _alignment} = Merge.titles(markers, incoming)

      assert Enum.map(chapters, &Decimal.to_integer(&1.time)) == [0, 100, 200]
    end

    test "keeps a marker's own title when the incoming one is blank" do
      markers = markers([0, 100])
      incoming = [titled(0, "Prologue"), titled(100, "  ")]

      assert {[first, second], _alignment} = Merge.titles(markers, incoming)

      assert first.title == "Prologue"
      assert second.title == "Chapter 2"
      assert second.title_source == :generated
    end

    test "records the source it was told" do
      assert {[chapter], _alignment} =
               Merge.titles(markers([0]), [titled(0, "Opening")], :filename)

      assert chapter.title_source == :filename
    end
  end

  describe "titles/3 with a bare title list" do
    test "merges index-wise when the incoming titles carry no times" do
      markers = markers([0, 100, 200])
      incoming = [%{title: "One", time: nil}, %{title: "Two", time: nil}]

      assert {chapters, _alignment} = Merge.titles(markers, incoming)

      assert Enum.map(chapters, & &1.title) == ["One", "Two", "Chapter 3"]
    end
  end

  describe "align/2 by duration sequence" do
    # The case the whole approach exists for: absolute times have wandered
    # minutes apart by the end of the book, but each chapter still runs the
    # length it runs.
    test "pairs correctly through accumulated drift" do
      markers = markers([0, 1200, 2500, 3900, 5000])

      # Same durations, every time pushed later and later.
      incoming = [
        titled(30, "Prologue"),
        titled(1260, "Chapter 1"),
        titled(2610, "Chapter 2"),
        titled(4080, "Chapter 3"),
        titled(5240, "Chapter 4"),
        titled(5600, "End Credits")
      ]

      assert {chapters, alignment} = Merge.titles(markers, incoming)

      assert Enum.map(chapters, & &1.title) == [
               "Prologue",
               "Chapter 1",
               "Chapter 2",
               "Chapter 3",
               "Chapter 4"
             ]

      assert %{matched: 5, unmatched_markers: 0, extra_titles: 1} = Merge.summarize(alignment)
    end

    # An extra entry at the front is the one that would wreck an index-wise
    # merge: everything after it lands one chapter early.
    test "absorbs an opening-credits entry the rip doesn't have" do
      markers = markers([0, 1200, 2500, 3900])

      incoming = [
        titled(0, "Opening Credits"),
        titled(35, "Prologue"),
        titled(1240, "Chapter 1"),
        titled(2545, "Chapter 2"),
        titled(3950, "Chapter 3")
      ]

      assert {chapters, alignment} = Merge.titles(markers, incoming)

      assert Enum.map(chapters, & &1.title) == ["Prologue", "Chapter 1", "Chapter 2", "Chapter 3"]
      assert %{matched: 4, extra_titles: 1} = Merge.summarize(alignment)
      assert {nil, 0} = hd(alignment)
    end

    # The rip splits in two what the catalogue calls one chapter, so one
    # marker has no title coming to it. It must keep its own — taking a
    # neighbour's name is worse than saying nothing.
    test "leaves a marker the title list has nothing for" do
      markers = markers([0, 600, 1200, 1500, 2400])

      incoming = [
        titled(0, "Ascension"),
        titled(600, "The Crossing"),
        titled(1200, "Nightfall"),
        titled(2400, "Homecoming")
      ]

      assert {chapters, alignment} = Merge.titles(markers, incoming)

      assert %{matched: 4, unmatched_markers: 1, extra_titles: 0} = Merge.summarize(alignment)
      assert [{0, 0}, {1, 1}, {2, nil}, {3, 2}, {4, 3}] = alignment

      assert Enum.map(chapters, & &1.title) == [
               "Ascension",
               "The Crossing",
               "Chapter 3",
               "Nightfall",
               "Homecoming"
             ]

      assert Enum.map(chapters, & &1.title_source) ==
               [:provider, :provider, :generated, :provider, :provider]
    end

    test "the alignment reads in timeline order" do
      markers = markers([0, 1200, 2500])
      incoming = [titled(0, "Credits"), titled(30, "A"), titled(1230, "B"), titled(2530, "C")]

      assert alignment = Merge.align(markers, incoming)

      marker_order = alignment |> Enum.map(&elem(&1, 0)) |> Enum.reject(&is_nil/1)
      title_order = alignment |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1)

      assert marker_order == Enum.sort(marker_order)
      assert title_order == Enum.sort(title_order)
    end
  end

  describe "align/2 edge cases" do
    test "no markers means every title is extra" do
      assert Merge.align([], [titled(0, "A"), titled(1, "B")]) == [{nil, 0}, {nil, 1}]
    end

    test "no titles means every marker is unmatched" do
      assert Merge.align(markers([0, 100]), []) == [{0, nil}, {1, nil}]
    end

    test "both empty" do
      assert Merge.align([], []) == []
    end
  end

  describe "renumber/1" do
    test "renumbers generated titles and leaves chosen ones alone" do
      chapters = [
        %Chapter{time: Decimal.new(0), title: "Prologue", title_source: :provider},
        %Chapter{time: Decimal.new(100), title: "Chapter 5", title_source: :generated},
        %Chapter{time: Decimal.new(200), title: "Chapter 6", title_source: :generated}
      ]

      assert [first, second, third] = Merge.renumber(chapters)

      assert first.title == "Prologue"
      assert second.title == "Chapter 2"
      assert third.title == "Chapter 3"
    end
  end

  defp markers(times) do
    times
    |> Enum.with_index()
    |> Enum.map(fn {time, index} ->
      %Chapter{
        time: Decimal.new(time),
        title: Chapter.generated_title(index),
        title_source: :generated
      }
    end)
  end

  defp titled(time, title), do: %{time: Decimal.new(time), title: title}
end
