defmodule AmbryWeb.Admin.BookLive.NewPersonTest do
  @moduledoc """
  The card for a human the book form is about to create.

  A credit box that can name somebody new made a `Person` out of a name and
  nothing else; the same human imported through the inbox arrived with a face
  and a biography. This is that card on the edit form — `EDIT_PARITY_PLAN.md`
  phase 3.
  """
  use AmbryWeb.ConnCase, async: false
  use Patch

  import Phoenix.ConnTest, except: [patch: 3]
  import Phoenix.LiveViewTest

  alias Ambry.Metadata.Provider
  alias Ambry.People.Person
  alias Ambry.Repo

  setup :register_and_log_in_admin_user

  @photo "https://images.gr-assets.com/authors/999015.jpg"
  @person_prefix "book[book_authors][0][author][author_people][0][person]"

  defp patch_providers do
    patch(Ambry.Metadata.Providers, :search_authors, fn
      "rreading_glasses", _query, _opts ->
        {:ok,
         [
           %Provider.Author{
             provider: "rreading_glasses",
             id: "999015",
             name: "Matt Dinniman",
             description: "Matt Dinniman writes dungeon crawls.",
             image_url: @photo
           }
         ]}

      _other_provider, _query, _opts ->
        {:ok, []}
    end)

    patch(Ambry.Metadata.Providers, :author_details, fn _provider, _id, _opts ->
      {:error, :not_found}
    end)
  end

  # A row that names an author nobody has: the state the card exists for.
  defp name_an_author(view, name) do
    view
    |> form("#book-form")
    |> render_change(%{
      "book" => %{
        "book_authors_sort" => ["new"],
        "book_authors" => %{"new" => %{"author_id" => "", "author" => %{"name" => name}}}
      }
    })
  end

  test "a credit that names nobody the library has gets a card", %{conn: conn} do
    book = insert(:book, book_authors: [])
    {:ok, view, html} = live(conn, ~p"/admin/books/#{book}/edit")

    refute html =~ ~s{data-role="person-card"}

    html = name_an_author(view, "Matt Dinniman")

    assert html =~ ~s{data-role="person-card"}
    assert html =~ "Matt Dinniman"
    assert has_element?(view, ~s{[data-role="person-card"] textarea})

    # A section of its own, under the credits that name them — the import
    # form's anatomy. It used to be a card inside the Authors card.
    assert has_element?(view, ~s{#new-people [data-role="person-card"]})

    assert Floki.find(Floki.parse_document!(html), ~s{#new-people h2}) |> Floki.text() ==
             "New people"
  end

  # The complaint this card was rebuilt on: it is the import form's card, not
  # a lookalike, so the parts that make it that card have to be here.
  # Landmarks rather than markup — each one is a piece somebody would notice
  # missing.
  test "it is the import form's card, not a redrawing of it", %{conn: conn} do
    patch_providers()
    book = insert(:book, book_authors: [])
    {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

    html = name_an_author(view, "Matt Dinniman")

    # the pen-name reveal, and the photo/bio half under it
    assert html =~ "This is a pen name"
    assert has_element?(view, ~s{[data-role="person-face"]})

    # the biography box, with the markdown preview beside it
    assert has_element?(view, ~s{textarea[placeholder="a short bio"]})
    assert html =~ "-preview"

    # A search covers the whole card while it runs — the same scrim a matching
    # job gets in the inbox, held open here so it can be seen.
    test = self()

    patch(Ambry.Metadata.Search, :people, fn _name ->
      send(test, {:searching, self()})
      receive do: (:go -> {[], []})
    end)

    render_click(view, "research-person", %{"key" => "0", "name" => "Matt Dinniman"})

    assert_receive {:searching, searcher}
    assert render(view) =~ ~s{data-role="busy-overlay"}

    send(searcher, :go)
    render_async(view)
  end

  # Every event the card raises has to be answered by whichever form renders
  # it. "This is a pen name" was raising `separate-name` at a LiveView that
  # had never heard of it, which is a crash, not a no-op.
  test "the pen-name reveal opens the name box and closes again", %{conn: conn} do
    book = insert(:book, book_authors: [])
    {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

    name_an_author(view, "Matt Dinniman")
    refute has_element?(view, ~s{input[name="#{@person_prefix}[name]"]})

    html = render_click(view, "separate-name", %{"key" => "0"})

    assert html =~ "A pen name of"
    assert has_element?(view, ~s{input[name="#{@person_prefix}[name]"]})

    html = render_click(view, "use-credited-name", %{"key" => "0"})
    assert html =~ "This is a pen name"
  end

  # A chip that writes an input is only as good as the input being there: the
  # photo chip pointed at a hidden field the card never rendered, so clicking
  # it did nothing at all and said nothing about why.
  test "every chip that writes an input has one to write", %{conn: conn} do
    patch_providers()
    book = insert(:book, book_authors: [])
    {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

    name_an_author(view, "Matt Dinniman")
    render_click(view, "research-person", %{"key" => "0", "name" => "Matt Dinniman"})
    render_async(view)

    html =
      view
      |> element(~s{[data-role="person-card"] [data-role="record"] input[type="checkbox"]})
      |> render_click()

    doc = Floki.parse_document!(html)
    targets = doc |> Floki.find("[data-set-input]") |> Floki.attribute("data-set-input")

    assert targets != [], "no chip writes an input, so this proves nothing"

    for target <- Enum.uniq(targets) do
      assert Floki.find(doc, ~s{[name="#{target}"]}) != [],
             "a chip writes #{target}, which is not on the page"
    end
  end

  # "again" presumes a search that may never have happened — and on either
  # form, since the inbox grows cards for people the matcher never saw.
  test "the search button does not claim there was a search before", %{conn: conn} do
    book = insert(:book, book_authors: [])
    {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

    html = name_an_author(view, "Matt Dinniman")

    refute html =~ "Search again"
    assert has_element?(view, ~s{input[name="#{@person_prefix}[search_query]"]})
  end

  # Two passes over one list: the credit rows post the hidden inputs, and the
  # section below them posts the nested person. A row posting its id twice
  # would be two rows as far as Ecto's `sort -- drop` is concerned.
  test "the second pass over the rows posts no hidden input twice", %{conn: conn} do
    book = insert(:book, book_authors: [])
    {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

    html = name_an_author(view, "Matt Dinniman")
    doc = Floki.parse_document!(html)

    for name <- ~w(book[book_authors][0][_persistent_id] book[book_authors][0][id]) do
      assert length(Floki.find(doc, ~s{input[name="#{name}"]})) <= 1,
             "#{name} is posted more than once"
    end
  end

  # The whole point of nesting the person under the credit: a row that points
  # at an author is a row that creates nobody, and the card would be offering
  # to edit a person credited on every other book they wrote.
  test "a credit that points at an author the library has gets no card", %{conn: conn} do
    person = insert(:person, name: "Matt Dinniman")
    author = insert(:author, name: "Matt Dinniman", person: person)
    book = insert(:book, book_authors: [])

    {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

    html =
      view
      |> form("#book-form")
      |> render_change(%{
        "book" => %{
          "book_authors_sort" => ["new"],
          "book_authors" => %{
            "new" => %{
              "author_id" => to_string(author.id),
              "author" => %{"name" => "Matt Dinniman"}
            }
          }
        }
      })

    refute html =~ ~s{data-role="person-card"}
  end

  # A pen name for a person the library already has reaches an existing
  # `Person`, so there is nobody to make and nothing to ask.
  test "a new pen name for a person the library has gets no card", %{conn: conn} do
    person = insert(:person, name: "Ty Franck")
    book = insert(:book, book_authors: [])

    {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

    html =
      view
      |> form("#book-form")
      |> render_change(%{
        "book" => %{
          "book_authors_sort" => ["new"],
          "book_authors" => %{
            "new" => %{
              "author_id" => "",
              "author" => %{
                "name" => "James S.A. Corey",
                "author_people" => %{"0" => %{"person_id" => to_string(person.id)}}
              }
            }
          }
        }
      })

    refute html =~ ~s{data-role="person-card"}
  end

  describe "the card's evidence" do
    setup do
      patch_providers()
      :ok
    end

    test "searching lists records; ticking offers a photo and a bio", %{conn: conn} do
      book = insert(:book, book_authors: [])
      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      name_an_author(view, "Matt Dinniman")

      render_click(view, "research-person", %{"key" => "0", "name" => "Matt Dinniman"})
      html = render_async(view)

      assert html =~ "rreading-glasses: 1"
      assert has_element?(view, ~s{[data-role="person-card"] [data-role="record"]})

      html =
        view
        |> element(~s{[data-role="person-card"] [data-role="record"] input[type="checkbox"]})
        |> render_click()

      # The chips write the person's own inputs, so the name they carry is
      # the whole path Ecto will cast them back through.
      assert html =~ "Matt Dinniman writes dungeon crawls."

      assert html =~
               "book[book_authors][0][author][author_people][0][person][description]"

      assert html =~ "book[book_authors][0][author][author_people][0][person][image_import_url]"
    end

    # Nothing is fetched while the operator is still deciding, and nothing is
    # written before Save: a search leaves no person behind.
    test "searching creates nobody", %{conn: conn} do
      book = insert(:book, book_authors: [])
      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      name_an_author(view, "Matt Dinniman")
      render_click(view, "research-person", %{"key" => "0", "name" => "Matt Dinniman"})
      render_async(view)

      assert Repo.all(Person) == []
    end
  end

  describe "saving" do
    test "the biography typed on the card is the person's", %{conn: conn} do
      book = insert(:book, book_authors: [])
      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      view
      |> form("#book-form")
      |> render_submit(%{
        "book" => %{
          "book_authors_sort" => ["new"],
          "book_authors" => %{
            "new" => %{
              "author_id" => "",
              "author" => %{
                "name" => "Matt Dinniman",
                "author_people" => %{
                  "0" => %{"person" => %{"description" => "Writes dungeon crawls."}}
                }
              }
            }
          }
        }
      })

      assert [%Person{name: "Matt Dinniman", description: "Writes dungeon crawls."}] =
               Repo.all(Person)
    end

    # The URL is what the chip writes and what the form posts; `image_path`
    # only ever holds a local upload path, so the save downloads it.
    test "the photo chosen on the card is downloaded by the save", %{conn: conn} do
      # saving processes the image into thumbnails, so it must really exist
      %{web_path: web_path} = Ambry.Factory.valid_image(:person)

      patch(AmbryWeb.Admin.UploadHelpers, :handle_image_import, fn url ->
        assert url == @photo
        {:ok, web_path}
      end)

      book = insert(:book, book_authors: [])
      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      view
      |> form("#book-form")
      |> render_submit(%{
        "book" => %{
          "book_authors_sort" => ["new"],
          "book_authors" => %{
            "new" => %{
              "author_id" => "",
              "author" => %{
                "name" => "Matt Dinniman",
                "author_people" => %{"0" => %{"person" => %{"image_import_url" => @photo}}}
              }
            }
          }
        }
      })

      assert [%Person{name: "Matt Dinniman", image_path: ^web_path}] = Repo.all(Person)
    end

    # A person the credit merely links must not be reached by the walk: the
    # save downloads nothing and touches nobody's photo but a new person's.
    test "a linked person's photo is left alone", %{conn: conn} do
      person = insert(:person, name: "Ty Franck", image_path: "/uploads/images/ty.jpg")
      book = insert(:book, book_authors: [])

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      view
      |> form("#book-form")
      |> render_submit(%{
        "book" => %{
          "book_authors_sort" => ["new"],
          "book_authors" => %{
            "new" => %{
              "author_id" => "",
              "author" => %{
                "name" => "James S.A. Corey",
                "author_people" => %{"0" => %{"person_id" => to_string(person.id)}}
              }
            }
          }
        }
      })

      assert %Person{image_path: "/uploads/images/ty.jpg"} = Repo.get!(Person, person.id)
      assert Repo.aggregate(Person, :count) == 1
    end
  end
end
