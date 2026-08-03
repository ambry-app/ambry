defmodule Ambry.Inbox.ReleaseNameTest do
  use ExUnit.Case, async: true

  alias Ambry.Inbox.ReleaseName

  # Every name below is taken verbatim from a real 295-release downloads
  # folder, which is also what the parser was tuned against.

  describe "parse/1 author and title" do
    test "splits the common \"Author - Title\" shape" do
      assert %{author: "Cory Doctorow", title: "The Bezzle"} =
               ReleaseName.parse("Cory Doctorow - The Bezzle [m4b]")
    end

    test "splits \"Title by Author\"" do
      assert %{author: "Stephen King", title: "Joyland"} =
               ReleaseName.parse("Joyland by Stephen King")
    end

    test "drops a leading track number rather than reading it as an author" do
      assert %{author: nil, title: "Angels and Demons"} =
               ReleaseName.parse("01 Angels and Demons.m4b")
    end

    test "drops trailing release bookkeeping" do
      assert %{author: "Mary Robinette Kowal", title: "The Calculating Stars"} =
               ReleaseName.parse(
                 "Mary Robinette Kowal - The Calculating Stars - 2018 - 125 kbps.m4b"
               )
    end

    test "keeps a title that simply has no author in it" do
      assert %{author: nil, title: "This Is How You Lose the Time War"} =
               ReleaseName.parse("This Is How You Lose the Time War")
    end

    test "refuses to read a series prefix as an author" do
      assert %{author: nil, title: "The Wee Free Men"} =
               ReleaseName.parse("Discworld 30 - The Wee Free Men")
    end
  end

  describe "parse/1 series" do
    test "reads a bracketed series and number" do
      assert %{author: "Dan Brown", title: "The Secret of Secrets", series: "Robert Langdon"} =
               parsed =
               ReleaseName.parse("Dan Brown ~ [Robert Langdon 06] - The Secret of Secrets (M4b)")

      assert Decimal.equal?(parsed.series_number, 6)
    end

    test "reads a hash-numbered bracketed series" do
      assert %{title: "A Court of Thorns and Roses", series: "ACOTAR"} =
               parsed =
               ReleaseName.parse(
                 "[ACOTAR #1] A Court of Thorns and Roses [GraphicAudio] (chapterized)"
               )

      assert Decimal.equal?(parsed.series_number, 1)
    end

    test "reads a series that a separator marks off" do
      assert %{title: "Dirk Gently's Holistic Detective Agency", series: "Dirk Gently"} =
               parsed =
               ReleaseName.parse(
                 "Dirk Gently's Holistic Detective Agency: Dirk Gently, Book 1.m4b"
               )

      assert Decimal.equal?(parsed.series_number, 1)
    end

    # Nothing says where the title stops and the series starts here, and
    # guessing used to eat the whole title. The number is still worth having.
    test "keeps the number but not a guessed series when nothing marks the split" do
      assert %{
               title: "A Fearful Symmetry Destiny's Crucible",
               author: "Olan Thorensen",
               series: nil
             } =
               parsed =
               ReleaseName.parse("Olan Thorensen - A Fearful Symmetry Destiny's Crucible, Book 8")

      assert Decimal.equal?(parsed.series_number, 8)
    end
  end

  describe "parse/1 other hints" do
    test "reads an ASIN out of the name" do
      assert %{title: "Sunrise on the Reaping", asin: "B0D6PCZ98M"} =
               ReleaseName.parse("Sunrise on the Reaping [B0D6PCZ98M]")
    end

    test "reads a narrator credit and keeps it out of the title" do
      assert %{title: "Discworld 30 The Wee Free Men", narrator: "Steven Briggs"} =
               ReleaseName.parse(
                 "Discworld 30 The Wee Free Men  (Read by Steven Briggs - Clear sound)"
               )
    end

    # The underscore is a filesystem-safe stand-in for a colon, so it reads
    # as a separator rather than part of the title.
    test "keeps parenthetical title material while dropping format noise" do
      assert %{title: "A Court of Mist and Fury Part 2", series: "A Court of Thorns and Roses"} =
               ReleaseName.parse(
                 "A Court of Mist and Fury_ Part 2 (A Court of Thorns and Roses #2) (Unabridged).m4b"
               )
    end
  end

  describe "query/1" do
    test "combines title and author when both are known" do
      assert "The Bezzle Cory Doctorow" =
               "Cory Doctorow - The Bezzle" |> ReleaseName.parse() |> ReleaseName.query()
    end

    test "falls back to the title alone" do
      assert "Sophie's World" = "Sophie's World" |> ReleaseName.parse() |> ReleaseName.query()
    end
  end
end
