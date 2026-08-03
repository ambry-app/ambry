defmodule Ambry.Media.Scanner.TagsTest do
  use Ambry.DataCase

  alias Ambry.Media.Scanner.Tags

  describe "parse/2" do
    test "reads what an audiobook file says about itself" do
      tags =
        Tags.parse(%{
          "album" => "The Way of Kings",
          "artist" => "Brandon Sanderson",
          "composer" => "Michael Kramer, Kate Reading",
          "date" => "2010-08-31",
          "comment" => "The first book of the Stormlight Archive.",
          "genre" => "Fantasy",
          "publisher" => "Macmillan Audio"
        })

      assert tags.book_title == "The Way of Kings"
      assert tags.authors == ["Brandon Sanderson"]
      assert tags.narrators == ["Michael Kramer", "Kate Reading"]
      assert tags.published == ~D[2010-08-31]
      assert tags.published_format == :full
      assert tags.description =~ "Stormlight"
      assert tags.genre == "Fantasy"
      assert tags.publisher == "Macmillan Audio"
    end

    test "takes the narrator from composer, the audiobook convention" do
      tags = Tags.parse(%{"composer" => "Ray Porter"})

      assert tags.narrators == ["Ray Porter"]
    end

    # Measured against a real library: where the two differed on a
    # single-file recording, `title` was the better book title in 11 of 12
    # cases — taggers park series names and track numbers in `album`.
    test "prefers title for a single-file recording, which has no chapter to name" do
      tags =
        Tags.parse(%{"album" => "Interdependency Book 1", "title" => "The Collapsing Empire"},
          single_file: true
        )

      assert tags.book_title == "The Collapsing Empire"
    end

    test "drops a leading track number from the book title" do
      assert Tags.parse(%{"album" => "01 Electric Angel"}).book_title == "Electric Angel"
      assert Tags.parse(%{"album" => "00.3 Machine Vendetta"}).book_title == "Machine Vendetta"
    end

    test "keeps a title that merely starts with a number" do
      assert Tags.parse(%{"album" => "1984"}).book_title == "1984"
      assert Tags.parse(%{"album" => "11/22/63"}).book_title == "11/22/63"
    end

    test "prefers album over title for the book, since title is per-file" do
      tags = Tags.parse(%{"album" => "Dungeon Crawler Carl", "title" => "Chapter One"})

      assert tags.book_title == "Dungeon Crawler Carl"
      assert tags.title == "Chapter One"
    end

    test "falls back to title when there's no album" do
      tags = Tags.parse(%{"title" => "Project Hail Mary"})

      assert tags.book_title == "Project Hail Mary"
    end

    test "ignores container bookkeeping" do
      tags =
        Tags.parse(%{
          "major_brand" => "M4A ",
          "minor_version" => "512",
          "compatible_brands" => "M4A isomiso2",
          "encoder" => "Lavf62.12.102",
          "handler_name" => "SoundHandler"
        })

      assert tags.raw == %{}
      refute Tags.any?(tags)
    end

    test "an untagged file parses to nothing, not an error" do
      tags = Tags.parse(%{})

      assert tags.authors == []
      assert tags.narrators == []
      refute Tags.any?(tags)
    end
  end

  describe "parse/2 series" do
    test "reads series and a decimal position" do
      tags = Tags.parse(%{"series" => "The Stormlight Archive", "series-part" => "1"})

      assert tags.series == "The Stormlight Archive"
      assert Decimal.equal?(tags.series_number, 1)
    end

    test "keeps a half-book position" do
      tags = Tags.parse(%{"series" => "The Expanse", "series-part" => "3.5"})

      assert Decimal.equal?(tags.series_number, "3.5")
    end

    test "digs a number out of a wordy position" do
      tags = Tags.parse(%{"series" => "Discworld", "series-part" => "Book 5"})

      assert Decimal.equal?(tags.series_number, 5)
    end

    test "reads the MP4 movement atoms some taggers use instead" do
      tags = Tags.parse(%{"movement_name" => "Mistborn", "movement" => "2"})

      assert tags.series == "Mistborn"
      assert Decimal.equal?(tags.series_number, 2)
    end
  end

  describe "parse/2 dates" do
    test "keeps a year-only tag year-only" do
      tags = Tags.parse(%{"date" => "2010"})

      assert tags.published == ~D[2010-01-01]
      assert tags.published_format == :year
    end

    test "keeps a year-month tag year-month" do
      tags = Tags.parse(%{"date" => "2010-08"})

      assert tags.published == ~D[2010-08-01]
      assert tags.published_format == :year_month
    end

    test "handles a full timestamp" do
      tags = Tags.parse(%{"date" => "2010-08-31T00:00:00Z"})

      assert tags.published == ~D[2010-08-31]
      assert tags.published_format == :full
    end

    test "ignores a date it can't make sense of" do
      tags = Tags.parse(%{"date" => "sometime in the 90s"})

      refute tags.published
    end

    test "ignores an impossible date" do
      tags = Tags.parse(%{"date" => "2010-02-30"})

      refute tags.published
    end
  end

  describe "parse/2 ASIN" do
    test "reads an ASIN, however the tagger cased the key" do
      assert Tags.parse(%{"ASIN" => "b003zwfo7e"}).asin == "B003ZWFO7E"
      assert Tags.parse(%{"asin" => "B003ZWFO7E"}).asin == "B003ZWFO7E"
      assert Tags.parse(%{"TXXX:ASIN" => "B003ZWFO7E"}).asin == "B003ZWFO7E"
      assert Tags.parse(%{"audible_asin" => "B003ZWFO7E"}).asin == "B003ZWFO7E"
    end

    test "refuses something that isn't one" do
      refute Tags.parse(%{"asin" => "not-an-asin"}).asin
      refute Tags.parse(%{"asin" => "B003"}).asin
      refute Tags.parse(%{"asin" => ""}).asin
    end
  end

  describe "parse/2 multi-value fields" do
    test "splits the separators taggers actually use" do
      assert Tags.parse(%{"artist" => "A; B"}).authors == ["A", "B"]
      assert Tags.parse(%{"artist" => "A & B"}).authors == ["A", "B"]
      assert Tags.parse(%{"artist" => "A and B"}).authors == ["A", "B"]
      assert Tags.parse(%{"composer" => "A, B, C"}).narrators == ["A", "B", "C"]
    end

    test "doesn't repeat a name listed twice" do
      assert Tags.parse(%{"artist" => "A; A"}).authors == ["A"]
    end

    # Splitting "Sanderson, Brandon" into two people is wrong, and there's no
    # way to tell it from "Kramer, Reading" in the tag alone. That's tolerable
    # because these are only ever proposals — and `raw` keeps the original for
    # a consumer that wants to try matching the whole string first.
    test "keeps the raw value so a bad split can be second-guessed" do
      tags = Tags.parse(%{"artist" => "Sanderson, Brandon"})

      assert tags.authors == ["Sanderson", "Brandon"]
      assert tags.raw["artist"] == "Sanderson, Brandon"
    end
  end
end
