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

    refute html =~ ~s{data-role="new-person"}

    html = name_an_author(view, "Matt Dinniman")

    assert html =~ ~s{data-role="new-person"}
    assert html =~ "New person · Matt Dinniman"
    assert has_element?(view, ~s{[data-role="new-person"] textarea})
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

    refute html =~ ~s{data-role="new-person"}
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

    refute html =~ ~s{data-role="new-person"}
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
      assert has_element?(view, ~s{[data-role="new-person"] [data-role="record"]})

      html =
        view
        |> element(~s{[data-role="new-person"] [data-role="record"] input[type="checkbox"]})
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
