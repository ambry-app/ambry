defmodule Ambry.Library.NamingTemplateTest do
  use ExUnit.Case, async: true

  alias Ambry.Library.NamingTemplate

  @book %{
    author: "Brandon Sanderson",
    series: "The Stormlight Archive",
    series_book_number: "1",
    title: "The Way of Kings",
    year: 2010
  }

  describe "render/2" do
    test "the default template" do
      assert {:ok, path} = NamingTemplate.render(@book)

      assert path ==
               "Brandon Sanderson/The Stormlight Archive/1 - The Way of Kings (2010)"
    end

    # A standalone book must not land in a folder called "" or leave an empty
    # path segment behind.
    test "drops the series segment entirely for a standalone book" do
      values = %{@book | series: nil, series_book_number: nil}

      assert {:ok, "Andy Weir/Project Hail Mary (2021)"} =
               NamingTemplate.render(%{
                 values
                 | author: "Andy Weir",
                   title: "Project Hail Mary",
                   year: 2021
               })
    end

    # The dash only existed to join the number. Without this every standalone
    # book would sit in a folder whose name starts with "- ".
    test "drops the punctuation that only joined a missing token" do
      assert {:ok, path} = NamingTemplate.render(%{@book | series_book_number: nil})
      assert path == "Brandon Sanderson/The Stormlight Archive/The Way of Kings (2010)"
    end

    test "drops the brackets around a missing year" do
      assert {:ok, path} = NamingTemplate.render(%{@book | year: nil})
      assert path == "Brandon Sanderson/The Stormlight Archive/1 - The Way of Kings"
    end

    test "drops an unknown author rather than writing an empty folder" do
      assert {:ok, path} = NamingTemplate.render(%{@book | author: nil})
      assert path == "The Stormlight Archive/1 - The Way of Kings (2010)"
    end

    test "refuses without a title rather than inventing one" do
      assert {:error, :no_title} = NamingTemplate.render(%{@book | title: nil})
      assert {:error, :no_title} = NamingTemplate.render(%{@book | title: "   "})
    end

    test "accepts a custom template" do
      assert {:ok, "Brandon Sanderson/The Way of Kings"} =
               NamingTemplate.render("{author}/{title}", @book)
    end

    test "accepts string keys as well as atoms" do
      assert {:ok, "A/T"} =
               NamingTemplate.render("{author}/{title}", %{"author" => "A", "title" => "T"})
    end

    # A title containing a slash must never become two directories — that's
    # how a recording escapes its library root.
    test "strips path separators out of values" do
      assert {:ok, path} =
               NamingTemplate.render("{author}/{title}", %{
                 author: "AC/DC",
                 title: "../../etc/passwd"
               })

      assert path == "ACDC/....etcpasswd"
      refute String.contains?(path, "/etc")
    end

    test "strips characters that break Windows and SMB shares" do
      assert {:ok, path} =
               NamingTemplate.render("{title}", %{
                 title: ~s(What Is It? "Quoted" <tag>: *star*|pipe)
               })

      assert path == "What Is It Quoted tag starpipe"
    end

    # A trailing dot or space is legal on Linux but silently dropped by
    # Windows and SMB, which is where these files usually get read from — so
    # the name on disk would stop matching the name in the database.
    test "collapses whitespace and trims a trailing dot" do
      assert {:ok, "A B"} = NamingTemplate.render("{title}", %{title: "  A  B.  "})
    end

    test "leaves ordinary punctuation alone" do
      assert {:ok, "Gwendy's Button Box & Other Stories, Vol. 1"} =
               NamingTemplate.render("{title}", %{
                 title: "Gwendy's Button Box & Other Stories, Vol. 1"
               })
    end

    # Filesystems cap a name at 255 bytes, and cutting on a byte boundary can
    # split a multi-byte character into invalid UTF-8.
    test "truncates a very long name on a character boundary" do
      title = String.duplicate("é", 300)

      assert {:ok, path} = NamingTemplate.render("{title}", %{title: title})
      assert byte_size(path) <= 255
      assert String.valid?(path)
    end

    test "renders a half-numbered book without a trailing zero" do
      assert {:ok, path} = NamingTemplate.render("{series_book_number} - {title}", @book)
      assert path == "1 - The Way of Kings"
    end
  end

  describe "filename/2" do
    test "names the file after the work, keeping the extension" do
      assert {:ok, "The Way of Kings.m4b"} =
               NamingTemplate.filename(@book, "/downloads/x/book.m4b")
    end

    test "normalizes the extension's case" do
      assert {:ok, "The Way of Kings.mp3"} =
               NamingTemplate.filename(@book, "/downloads/x/BOOK.MP3")
    end

    test "sanitizes the title" do
      assert {:ok, "ACDC Live.m4b"} =
               NamingTemplate.filename(%{@book | title: "AC/DC Live"}, "a.m4b")
    end

    test "refuses without a title" do
      assert {:error, :no_title} = NamingTemplate.filename(%{@book | title: nil}, "a.m4b")
    end

    test "suffixes a part of a set, in the set's own wording" do
      assert {:ok, "The Way of Kings - Part 2 of 3.m4b"} =
               NamingTemplate.filename(@book, "a.m4b", %{part: part(2, 3, nil)})

      assert {:ok, "The Way of Kings - Part 2.m4b"} =
               NamingTemplate.filename(@book, "a.m4b", %{part: part(2, nil, nil)})

      assert {:ok, "The Way of Kings - Episode 2 of 3.m4b"} =
               NamingTemplate.filename(@book, "a.m4b", %{part: part(2, 3, "episode")})
    end
  end

  # The token is what makes a name unique inside a book folder that is shared
  # by every part of a set and every recording of the work. Two readings of
  # one book published the same year used to render to one identical path.
  describe "filename/3 with a recording token" do
    test "brackets the token onto the end of the name" do
      assert {:ok, "The Way of Kings [7bKq].m4b"} =
               NamingTemplate.filename(@book, "a.m4b", %{token: "7bKq"})
    end

    test "sits after the part label, so the readable part stays readable" do
      assert {:ok, "The Way of Kings - Part 2 of 3 [7bKq].m4b"} =
               NamingTemplate.filename(@book, "a.m4b", %{part: part(2, 3, nil), token: "7bKq"})
    end

    test "two recordings of one book no longer render to one path" do
      assert {:ok, first} = NamingTemplate.filename(@book, "a.m4b", %{token: "7bKq"})
      assert {:ok, second} = NamingTemplate.filename(@book, "a.m4b", %{token: "9mZp"})

      refute first == second
    end

    test "a missing token is simply absent, never an empty bracket" do
      assert {:ok, "The Way of Kings.m4b"} = NamingTemplate.filename(@book, "a.m4b", %{})

      assert {:ok, "The Way of Kings.m4b"} =
               NamingTemplate.filename(@book, "a.m4b", %{token: nil})

      assert {:ok, "The Way of Kings.m4b"} = NamingTemplate.filename(@book, "a.m4b", %{token: ""})
    end
  end

  describe "filenames/3" do
    test "a single file sits directly in the book folder, exactly as before" do
      assert {:ok, ["The Way of Kings.m4b"]} =
               NamingTemplate.filenames(@book, ["/downloads/x/book.m4b"])
    end

    test "a multi-file recording gets a subfolder of its own and indexed names" do
      sources = for i <- 1..3, do: "/downloads/x/track#{i}.mp3"

      assert {:ok, names} = NamingTemplate.filenames(@book, sources)

      assert names == [
               "The Way of Kings/The Way of Kings - 001.mp3",
               "The Way of Kings/The Way of Kings - 002.mp3",
               "The Way of Kings/The Way of Kings - 003.mp3"
             ]
    end

    test "the index is wide enough for the recording it numbers" do
      sources = for i <- 1..1200, do: "/downloads/x/#{i}.mp3"

      assert {:ok, names} = NamingTemplate.filenames(@book, sources)

      assert List.first(names) =~ "- 0001.mp3"
      assert List.last(names) =~ "- 1200.mp3"
    end

    test "keeps each file's own extension" do
      assert {:ok, [first, second]} =
               NamingTemplate.filenames(@book, ["/x/a.MP3", "/x/b.m4a"])

      assert first =~ ".mp3"
      assert second =~ ".m4a"
    end

    test "a part of a set takes its suffix into the subfolder name too" do
      assert {:ok, names} =
               NamingTemplate.filenames(@book, ["/x/a.mp3", "/x/b.mp3"], %{part: part(2, 3, nil)})

      assert names == [
               "The Way of Kings - Part 2 of 3/The Way of Kings - Part 2 of 3 - 001.mp3",
               "The Way of Kings - Part 2 of 3/The Way of Kings - Part 2 of 3 - 002.mp3"
             ]
    end

    # The folder is the thing that has to be unique inside the book folder,
    # so it carries the token — and the files inside it don't repeat it,
    # because the index is already all the uniqueness they need.
    test "the token goes on the recording's folder, not on every file in it" do
      assert {:ok, names} =
               NamingTemplate.filenames(@book, ["/x/a.mp3", "/x/b.mp3"], %{token: "7bKq"})

      assert names == [
               "The Way of Kings [7bKq]/The Way of Kings - 001.mp3",
               "The Way of Kings [7bKq]/The Way of Kings - 002.mp3"
             ]
    end

    test "two multi-file recordings of one book get separate folders" do
      sources = ["/x/a.mp3", "/x/b.mp3"]

      assert {:ok, [first | _]} = NamingTemplate.filenames(@book, sources, %{token: "7bKq"})
      assert {:ok, [second | _]} = NamingTemplate.filenames(@book, sources, %{token: "9mZp"})

      refute Path.dirname(first) == Path.dirname(second)
    end

    test "refuses without a title" do
      assert {:error, :no_title} =
               NamingTemplate.filenames(%{@book | title: nil}, ["a.mp3", "b.mp3"])
    end
  end

  describe "validate/1" do
    test "accepts the default" do
      assert :ok = NamingTemplate.validate(NamingTemplate.default_template())
    end

    test "rejects a blank template" do
      assert {:error, :blank} = NamingTemplate.validate("")
      assert {:error, :blank} = NamingTemplate.validate("   ")
    end

    # An absolute template would ignore the library root entirely, and `..`
    # would climb out of it.
    test "rejects escaping the library root" do
      assert {:error, :absolute} = NamingTemplate.validate("/{author}/{title}")
      assert {:error, :traversal} = NamingTemplate.validate("../{author}/{title}")
    end

    test "rejects an unknown token" do
      assert {:error, {:unknown_token, "publisher"}} =
               NamingTemplate.validate("{author}/{publisher}/{title}")
    end

    # Without a title every book by one author collapses into one folder.
    test "requires the title token" do
      assert {:error, :no_title_token} = NamingTemplate.validate("{author}/{year}")
    end
  end

  defp part(number, total, word), do: %{number: number, total: total, word: word}
end
