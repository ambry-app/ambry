defmodule AmbryWeb.Admin.MediaLive.NewPersonTest do
  @moduledoc """
  The card for a human the audiobook form is about to create.

  The book form's card, one join shallower: a narrator belongs to a person
  directly, where an author reaches theirs through a pen name. The card does
  not know the difference — `EDIT_PARITY_PLAN.md` phase 3.
  """
  use AmbryWeb.ConnCase, async: false
  use Patch

  import Phoenix.ConnTest, except: [patch: 3]
  import Phoenix.LiveViewTest

  alias Ambry.Metadata.Provider
  alias Ambry.People.Person
  alias Ambry.Repo

  setup :register_and_log_in_admin_user

  @photo "https://images.gr-assets.com/authors/12345.jpg"

  defp patch_providers do
    patch(Ambry.Metadata.Providers, :search_authors, fn
      "rreading_glasses", _query, _opts ->
        {:ok,
         [
           %Provider.Author{
             provider: "rreading_glasses",
             id: "12345",
             name: "Michael Kramer",
             description: "Michael Kramer has narrated over two hundred books.",
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

  defp name_a_narrator(view, name) do
    view
    |> form("#media-form")
    |> render_change(%{
      "media" => %{
        "media_narrators_sort" => ["new"],
        "media_narrators" => %{
          "new" => %{"narrator_id" => "", "narrator" => %{"name" => name}}
        }
      }
    })
  end

  test "a credit that names nobody the library has gets a card", %{conn: conn} do
    media = insert(:media, book: build(:book), media_narrators: [])
    {:ok, view, html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

    refute html =~ ~s{data-role="person-card"}

    html = name_a_narrator(view, "Michael Kramer")

    assert html =~ ~s{data-role="person-card"}
    assert html =~ "Michael Kramer"
    # a narrator's alias is a stage name, not a pen name
    assert html =~ "This is a stage name"

    # a section of its own, under the credits that name them
    assert has_element?(view, ~s{#people [data-role="person-card"]})
  end

  test "a credit that points at a narrator the library has gets no card", %{conn: conn} do
    person = insert(:person, name: "Michael Kramer")
    narrator = insert(:narrator, name: "Michael Kramer", person: person)
    media = insert(:media, book: build(:book), media_narrators: [])

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

    html =
      view
      |> form("#media-form")
      |> render_change(%{
        "media" => %{
          "media_narrators_sort" => ["new"],
          "media_narrators" => %{
            "new" => %{
              "narrator_id" => to_string(narrator.id),
              "narrator" => %{"name" => "Michael Kramer"}
            }
          }
        }
      })

    refute html =~ ~s{data-role="person-card"}
  end

  # An import takes the best record's face and biography and leaves the rest
  # one click away (`Draft.Seed.scalar/2`); a credit on an edit form was only
  # ever *offered* them, so the operator who ticked a record and saved got a
  # person with a name and nothing else. Same three questions, same answers.
  test "a record about this human arrives ticked and answers both fields", %{conn: conn} do
    patch_providers()
    media = insert(:media, book: build(:book), media_narrators: [])

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
    name_a_narrator(view, "Michael Kramer")

    render_click(view, "research-person", %{"key" => "0", "name" => "Michael Kramer"})
    html = render_async(view)

    assert has_element?(
             view,
             ~s{[data-role="person-card"] [data-role="record"] input[type="checkbox"][checked]}
           )

    assert bio_input(html) == "Michael Kramer has narrated over two hundred books."
    assert photo_input(html) == @photo
    assert Repo.all(Person) == []
  end

  # Recall-first: person search offers everybody sharing a name token, and a
  # record about somebody else is listed, not used.
  test "a record about somebody else is listed and left alone", %{conn: conn} do
    patch(Ambry.Metadata.Providers, :search_authors, fn
      "rreading_glasses", _query, _opts ->
        {:ok,
         [
           %Provider.Author{
             provider: "rreading_glasses",
             id: "999",
             name: "Michael Crichton",
             description: "Wrote Jurassic Park.",
             image_url: @photo
           }
         ]}

      _other_provider, _query, _opts ->
        {:ok, []}
    end)

    patch(Ambry.Metadata.Providers, :author_details, fn _provider, _id, _opts ->
      {:error, :not_found}
    end)

    media = insert(:media, book: build(:book), media_narrators: [])
    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
    name_a_narrator(view, "Michael Kramer")

    render_click(view, "research-person", %{"key" => "0", "name" => "Michael Kramer"})
    html = render_async(view)

    assert html =~ "Michael Crichton"

    refute has_element?(
             view,
             ~s{[data-role="person-card"] [data-role="record"] input[type="checkbox"][checked]}
           )

    assert photo_input(html) == nil
  end

  # The card's controls are inputs, so everything the form posts after one has
  # rendered carries an answer — including the empty one that means "not this
  # face". Only a person nobody has said anything about yet is unanswered.
  test "an answer already given is not overwritten", %{conn: conn} do
    patch_providers()
    media = insert(:media, book: build(:book), media_narrators: [])

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
    name_a_narrator(view, "Michael Kramer")
    render_click(view, "research-person", %{"key" => "0", "name" => "Michael Kramer"})
    render_async(view)

    # "no photo", which posts the same shape the chip does
    html =
      view
      |> form("#media-form")
      |> render_change(%{
        "media" => %{
          "media_narrators" => %{
            "0" => %{
              "narrator_id" => "",
              "narrator" => %{
                "name" => "Michael Kramer",
                "person" => %{"image_import_url" => "", "description" => ""}
              }
            }
          }
        }
      })

    assert photo_input(html) == nil
    assert bio_input(html) == ""
  end

  # The bug the operator hit: a chip stages a credit without going anywhere
  # near the picker, and the card it needs was gated on something only the
  # picker set. Nothing gates it now but the row itself.
  test "a narrator credited by a provider chip gets their card at once", %{conn: conn} do
    patch(Ambry.Metadata.Providers, :search_books, fn _provider, _query, _opts ->
      {:ok,
       [
         %Provider.Book{
           provider: "audible",
           id: "B0983R6VP1",
           title: "The Martian",
           narrators: [%Provider.Contributor{id: "9", name: "Michael Kramer", role: "narrator"}]
         }
       ]}
    end)

    media = insert(:media, book: build(:book, title: "The Martian"), media_narrators: [])
    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

    view |> form("#research-recording", %{"title" => "The Martian"}) |> render_submit()
    render_async(view)
    view |> element(~s{[data-role="record"] input[type="checkbox"]}) |> render_click()

    html = view |> element("#proposals-narrators button", "Michael Kramer") |> render_click()

    assert html =~ ~s{data-role="person-card"}
    assert html =~ "media[media_narrators][0][narrator][person][description]"
    assert Repo.all(Person) == []
  end

  # Every card on an edit form is the first person behind the first credit of
  # the only section, so keying their ids by that address gave every card the
  # same four ids — and LiveView's patcher, which finds elements by id, moved
  # a bio box out of one card and into another (operator, 2026-08-21). The
  # test harness raises on a duplicate id, so rendering two is the assertion;
  # this counts them so a failure says what it means.
  test "two new people share no DOM ids", %{conn: conn} do
    media = insert(:media, book: build(:book), media_narrators: [])
    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

    html =
      view
      |> form("#media-form")
      |> render_change(%{
        "media" => %{
          "media_narrators_sort" => ["a", "b"],
          "media_narrators" => %{
            "a" => %{"narrator_id" => "", "narrator" => %{"name" => "Michael Kramer"}},
            "b" => %{"narrator_id" => "", "narrator" => %{"name" => "Kate Reading"}}
          }
        }
      })

    assert [_one, _two] = Floki.find(Floki.parse_document!(html), ~s{[data-role="person-card"]})

    duplicates =
      ~r/ id="([^"]+)"/
      |> Regex.scan(html)
      |> Enum.map(&Enum.at(&1, 1))
      |> Enum.frequencies()
      |> Enum.filter(fn {_id, count} -> count > 1 end)

    assert duplicates == []
  end

  # A face that could not be fetched used to be dropped in silence, so a form
  # that saved perfectly well created a person without one and said nothing —
  # indistinguishable from a photo nobody chose.
  test "a photo that cannot be downloaded stops the save and says so", %{conn: conn} do
    patch(AmbryWeb.Admin.UploadHelpers, :handle_image_import, fn
      @photo -> {:error, :failed_to_download_image}
      _no_url -> {:ok, :no_image_url}
    end)

    media = insert(:media, book: build(:book), media_narrators: [])
    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

    html =
      view
      |> form("#media-form")
      |> render_submit(%{
        "media" => %{
          "media_narrators_sort" => ["new"],
          "media_narrators" => %{
            "new" => %{
              "narrator_id" => "",
              "narrator" => %{
                "name" => "Michael Kramer",
                "person" => %{"image_import_url" => @photo}
              }
            }
          }
        }
      })

    assert html =~ "Couldn&#39;t download the photo chosen for a new person"
    assert Repo.all(Person) == []
  end

  # What the card's own box holds, which is not the same question as whether
  # the words are on the page: a record's row states its biography whether or
  # not the person is taking it.
  defp bio_input(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(~s{textarea[name="media[media_narrators][0][narrator][person][description]"]})
    |> Floki.text()
  end

  # The auto-filled face is a guess, and a wrong guess needs one obvious way
  # off. It used to be a text button after the strip that only appeared once
  # a photo was chosen, which read as a caption; it is one of the faces now.
  test "no face is one of the faces, and taking one off is one click", %{conn: conn} do
    patch_providers()
    media = insert(:media, book: build(:book), media_narrators: [])

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
    name_a_narrator(view, "Michael Kramer")
    render_click(view, "research-person", %{"key" => "0", "name" => "Michael Kramer"})
    html = render_async(view)

    assert photo_input(html) == @photo

    # the none chip writes the same input the photo chips do, with nothing
    assert [target] =
             html
             |> Floki.parse_document!()
             |> Floki.attribute(~s{button[title="no photo"]}, "data-set-input")

    assert target == "media[media_narrators][0][narrator][person][image_import_url]"

    html =
      view
      |> form("#media-form")
      |> render_change(%{
        "media" => %{
          "media_narrators" => %{
            "0" => %{
              "narrator_id" => "",
              "narrator" => %{
                "name" => "Michael Kramer",
                "person" => %{"image_import_url" => ""}
              }
            }
          }
        }
      })

    assert photo_input(html) == nil

    # and the way back is still there, wearing the ring that says it is the
    # answer in force
    assert html
           |> Floki.parse_document!()
           |> Floki.attribute(~s{button[title="no photo"]}, "class")
           |> List.first() =~ "ring-brand-dark/50"
  end

  # A face whose record has since been unticked has no strip under it, and
  # the strip is where the way out lives.
  test "a chosen face keeps its strip when the records go", %{conn: conn} do
    media = insert(:media, book: build(:book), media_narrators: [])
    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

    html =
      view
      |> form("#media-form")
      |> render_change(%{
        "media" => %{
          "media_narrators_sort" => ["new"],
          "media_narrators" => %{
            "new" => %{
              "narrator_id" => "",
              "narrator" => %{
                "name" => "Michael Kramer",
                "person" => %{"image_import_url" => @photo}
              }
            }
          }
        }
      })

    assert photo_input(html) == @photo
    assert has_element?(view, ~s{button[title="no photo"]})
  end

  # The import form's answer to "the databases found people and none of them
  # is this human", which the edit forms did not have — so the records ran
  # straight into the biography with nothing between them, and saying "wrong
  # person" meant unticking every row and clearing two fields by hand.
  test "None of these unticks the records and takes back what they gave", %{conn: conn} do
    patch_providers()
    media = insert(:media, book: build(:book), media_narrators: [])

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
    name_a_narrator(view, "Michael Kramer")
    render_click(view, "research-person", %{"key" => "0", "name" => "Michael Kramer"})
    html = render_async(view)

    assert html =~ ~s{data-role="none-of-these"}

    # it empties the person's own inputs on the client, the way the chips
    # fill them — both of them, from the one control
    assert [blanks] =
             html
             |> Floki.parse_document!()
             |> Floki.attribute(~s{[data-role="none-of-these"]}, "data-set-blank")

    assert Jason.decode!(blanks) == [
             "media[media_narrators][0][narrator][person][image_import_url]",
             "media[media_narrators][0][narrator][person][description]"
           ]

    html = render_click(view, "uncatalogued-person", %{"key" => "0"})

    refute has_element?(
             view,
             ~s{[data-role="person-card"] [data-role="record"] input[type="checkbox"][checked]}
           )

    # and it reads as the answer it is, rather than as an offer
    assert html =~ ~s{data-role="none-of-these"}
    assert html =~ "ring-brand-dark/50"
  end

  # An untouched card that found nobody has not been answered — it just found
  # nobody — so the button must not claim it has.
  test "None of these is not lit before anybody presses it", %{conn: conn} do
    patch_providers()
    media = insert(:media, book: build(:book), media_narrators: [])

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
    name_a_narrator(view, "Michael Kramer")
    render_click(view, "research-person", %{"key" => "0", "name" => "Michael Kramer"})
    render_async(view)

    # untick by hand: now they HAVE touched it
    view
    |> element(~s{[data-role="person-card"] [data-role="record"] input[type="checkbox"]})
    |> render_click()

    assert view |> element(~s{[data-role="none-of-these"]}) |> render() =~ "ring-brand-dark/50"
  end

  # Ten chips is ten cards, and finding out about them was ten clicks in ten
  # places.
  test "Search all asks about every card nobody has asked about", %{conn: conn} do
    # a record for whoever is asked about, so each card gets its own answer
    patch(Ambry.Metadata.Providers, :search_authors, fn
      "rreading_glasses", query, _opts ->
        {:ok,
         [
           %Provider.Author{
             provider: "rreading_glasses",
             id: "id-#{query}",
             name: query,
             description: "Narrates.",
             image_url: @photo
           }
         ]}

      _other_provider, _query, _opts ->
        {:ok, []}
    end)

    patch(Ambry.Metadata.Providers, :author_details, fn _provider, _id, _opts ->
      {:error, :not_found}
    end)

    media = insert(:media, book: build(:book), media_narrators: [])

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

    html =
      view
      |> form("#media-form")
      |> render_change(%{
        "media" => %{
          "media_narrators_sort" => ["a", "b"],
          "media_narrators" => %{
            "a" => %{"narrator_id" => "", "narrator" => %{"name" => "Michael Kramer"}},
            "b" => %{"narrator_id" => "", "narrator" => %{"name" => "Kate Reading"}}
          }
        }
      })

    assert html =~ "Search all 2"

    view |> element("#people button", "Search all") |> render_click()
    render_async(view)

    # one card each, both answered
    assert [_first, _second] =
             Floki.find(
               Floki.parse_document!(render(view)),
               ~s{[data-role="person-card"] [data-role="record"]}
             )

    # and it stops offering once there is nothing left to ask
    refute render(view) =~ "Search all"
  end

  # A single card has its own Search two inches below; a second button for
  # the same click is noise.
  test "Search all stays away from a form with one new person", %{conn: conn} do
    media = insert(:media, book: build(:book), media_narrators: [])
    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

    html = name_a_narrator(view, "Michael Kramer")

    assert html =~ ~s{data-role="person-card"}
    refute html =~ "Search all"
  end

  # The URL the save downloads, as the card is holding it — absent rather
  # than blank when nobody has chosen one, which is HEEx omitting a nil.
  defp photo_input(html) do
    html
    |> Floki.parse_document!()
    |> Floki.attribute(
      ~s{input[name="media[media_narrators][0][narrator][person][image_import_url]"]},
      "value"
    )
    |> List.first()
  end

  test "the biography and photo chosen on the card are the person's", %{conn: conn} do
    %{web_path: web_path} = Ambry.Factory.valid_image(:person)

    # the recording's own cover import runs on every save and asks the same
    # helper, so this answers for the person's photo only
    patch(AmbryWeb.Admin.UploadHelpers, :handle_image_import, fn
      @photo -> {:ok, web_path}
      _no_url -> {:ok, :no_image_url}
    end)

    media = insert(:media, book: build(:book), media_narrators: [])
    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

    view
    |> form("#media-form")
    |> render_submit(%{
      "media" => %{
        "media_narrators_sort" => ["new"],
        "media_narrators" => %{
          "new" => %{
            "narrator_id" => "",
            "narrator" => %{
              "name" => "Michael Kramer",
              "person" => %{"description" => "Narrates.", "image_import_url" => @photo}
            }
          }
        }
      }
    })

    assert [
             %Person{
               name: "Michael Kramer",
               description: "Narrates.",
               image_path: ^web_path
             }
           ] = Repo.all(Person)
  end
end
