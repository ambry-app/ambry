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

  # For titles that arrived from tags rather than a folder name — same junk,
  # different road. Parse-only cleaning left "Children of Time (Unabridged)"
  # searching providers with the parenthetical attached.
  describe "strip_noise/1" do
    test "drops a noise parenthetical" do
      assert ReleaseName.strip_noise("Children of Time (Unabridged)") == "Children of Time"
    end

    test "drops noise brackets" do
      assert ReleaseName.strip_noise("Project Hail Mary [m4b]") == "Project Hail Mary"
    end

    test "keeps parenthetical title material" do
      assert ReleaseName.strip_noise("A Court of Mist and Fury (A Court of Thorns and Roses #2)") ==
               "A Court of Mist and Fury (A Court of Thorns and Roses #2)"
    end

    test "a title that is nothing but noise strips to nil" do
      assert ReleaseName.strip_noise("(Unabridged)") == nil
      assert ReleaseName.strip_noise(nil) == nil
    end

    # Album tags carry shelf ordering the way folder names do: "01 Mr.
    # Mercedes" sent the search into junk ("01 Mistrunner" led), and
    # "Limitless 01" the same. A trailing number only goes when zero-padded:
    # "Judicator Jane 4" and "Fahrenheit 451" are titles.
    test "strips shelf ordering but not numbers that are the title" do
      assert ReleaseName.strip_noise("01 Mr. Mercedes") == "Mr. Mercedes"
      assert ReleaseName.strip_noise("Limitless 01") == "Limitless"
      assert ReleaseName.strip_noise("01 Superworld") == "Superworld"
      assert ReleaseName.strip_noise("Judicator Jane 4") == "Judicator Jane 4"
      assert ReleaseName.strip_noise("Fahrenheit 451") == "Fahrenheit 451"
      assert ReleaseName.strip_noise("1984") == "1984"
      assert ReleaseName.strip_noise("Catch-22") == "Catch-22"
    end

    # With ": A Novel" attached, neither provider returned the actual
    # Jurassic Park — and because they returned junk rather than nothing,
    # the zero-result retry never fired.
    test "drops a marketing subtitle but keeps a real one" do
      assert ReleaseName.strip_noise("Jurassic Park: A Novel") == "Jurassic Park"
      assert ReleaseName.strip_noise("Wool: A Memoir") == "Wool"

      assert ReleaseName.strip_noise("A Deadly Education: Lessons") ==
               "A Deadly Education: Lessons"
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
