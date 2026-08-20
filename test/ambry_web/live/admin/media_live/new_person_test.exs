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
        "media_narrators" => %{"new" => %{"narrator_id" => "", "narrator" => %{"name" => name}}}
      }
    })
  end

  test "a credit that names nobody the library has gets a card", %{conn: conn} do
    media = insert(:media, book: build(:book), media_narrators: [])
    {:ok, view, html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

    refute html =~ ~s{data-role="new-person"}

    html = name_a_narrator(view, "Michael Kramer")

    assert html =~ ~s{data-role="new-person"}
    assert html =~ "New person · Michael Kramer"
    # a narrator's alias is a stage name, not a pen name
    assert html =~ "This is a stage name"
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

    refute html =~ ~s{data-role="new-person"}
  end

  test "ticking a record offers a photo and a bio that write the person's inputs",
       %{conn: conn} do
    patch_providers()
    media = insert(:media, book: build(:book), media_narrators: [])

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
    name_a_narrator(view, "Michael Kramer")

    render_click(view, "research-person", %{"key" => "0", "name" => "Michael Kramer"})
    render_async(view)

    html =
      view
      |> element(~s{[data-role="new-person"] [data-role="record"] input[type="checkbox"]})
      |> render_click()

    assert html =~ "has narrated over two hundred books"
    assert html =~ "media[media_narrators][0][narrator][person][description]"
    assert html =~ "media[media_narrators][0][narrator][person][image_import_url]"
    assert Repo.all(Person) == []
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
