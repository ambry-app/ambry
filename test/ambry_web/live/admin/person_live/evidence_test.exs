defmodule AmbryWeb.Admin.PersonLive.EvidenceTest do
  @moduledoc """
  The person form's inline evidence panel — one name search across every
  person-capable provider, records of humans as tickable evidence, photos
  and bios as chips. Replaced both the import-modal tests and the
  image-picker tests when those two mechanisms merged into this one.
  """
  use AmbryWeb.ConnCase, async: false
  use Patch

  import Phoenix.ConnTest, except: [patch: 3]
  import Phoenix.LiveViewTest

  alias Ambry.Metadata.Provider
  alias Ambry.Provenance

  setup :register_and_log_in_admin_user

  @gr_image "https://images.gr-assets.com/authors/999015.jpg"

  # The fan-out asks every enabled author-search provider
  # (rreading_glasses, audnexus, wikidata in the zero-config test env).
  # A match without images and description is filtered out by PersonSearch,
  # so the interesting hit carries both.
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
             image_url: @gr_image
           }
         ]}

      _other_provider, _query, _opts ->
        {:ok, []}
    end)

    patch(Ambry.Metadata.Providers, :author_details, fn _provider, _id, _opts ->
      {:error, :not_found}
    end)
  end

  defp search(view, name) do
    view |> form("#research-person", %{"name" => name}) |> render_submit()
    render_async(view)
  end

  defp tick_first_record(view) do
    view
    |> element(~s{[data-role="record"] input[type="checkbox"]})
    |> render_click()
  end

  test "searching lists person records; ticking offers name, bio and photo chips",
       %{conn: conn} do
    patch_providers()

    {:ok, view, _html} = live(conn, ~p"/admin/people/new")
    html = search(view, "Matt Dinniman")

    assert html =~ "Matt Dinniman"
    assert html =~ "has a photo"
    assert html =~ "rreading-glasses: 1"

    html = tick_first_record(view)

    # a chip row under each field the record can fill
    assert html =~ "proposals-person_name"
    assert html =~ "proposals-description"
    assert html =~ "proposals-image"
  end

  test "accepting a photo stages a URL import, and saving records the provider",
       %{conn: conn} do
    patch_providers()

    # saving processes the image into thumbnails, so it must really exist
    %{web_path: web_path} = Ambry.Factory.valid_image(:person)

    patch(AmbryWeb.Admin.UploadHelpers, :handle_image_import, fn url ->
      assert url == @gr_image
      {:ok, web_path}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/people/new")
    search(view, "Matt Dinniman")
    tick_first_record(view)

    view |> element(~s{#proposals-person_name button}) |> render_click()
    html = view |> element(~s{#proposals-image button}) |> render_click()

    # the accept switched the image machinery to a URL import
    assert html =~ @gr_image

    view |> form("#person-form", %{"person" => %{}}) |> render_submit()

    person = Ambry.Repo.one!(Ambry.People.Person)
    assert person.name == "Matt Dinniman"
    assert person.image_path == web_path

    assert %{"source" => "provider:rreading_glasses", "locked" => false} =
             Provenance.entry(person, :name)

    assert %{"source" => "provider:rreading_glasses", "locked" => false} =
             Provenance.entry(person, :image_path)
  end

  test "accepting a bio fills the description with provider provenance", %{conn: conn} do
    patch_providers()

    {:ok, view, _html} = live(conn, ~p"/admin/people/new")
    search(view, "Matt Dinniman")
    tick_first_record(view)

    view |> element(~s{#proposals-person_name button}) |> render_click()
    view |> element(~s{#proposals-description button}) |> render_click()
    view |> form("#person-form", %{"person" => %{}}) |> render_submit()

    person = Ambry.Repo.one!(Ambry.People.Person)
    assert person.description == "Matt Dinniman writes dungeon crawls."

    assert %{"source" => "provider:rreading_glasses", "locked" => false} =
             Provenance.entry(person, :description)
  end

  test "re-searching adds records without un-ticking choices", %{conn: conn} do
    patch_providers()

    {:ok, view, _html} = live(conn, ~p"/admin/people/new")
    search(view, "Matt Dinniman")
    tick_first_record(view)

    html = search(view, "Matt Dinniman again")

    # the ticked record survived the second fan-out
    assert html =~ ~s(data-used="true")
  end

  test "the evidence search is seeded with the person's own name", %{conn: conn} do
    person = insert(:person, name: "Anthony Palmini")

    {:ok, _view, html} = live(conn, ~p"/admin/people/#{person.id}/edit")

    assert html =~ ~s(value="Anthony Palmini")
  end

  # This form and the import form's person cards render the same component
  # now — the markup was hand-written in both places and had already drifted.
  # The rule they share: the box holds the query, from the click onward, so a
  # search for a name other than this person's own does not read as a rename
  # and does not revert while it runs.
  test "the box keeps the searched name, which is not the person's name", %{conn: conn} do
    patch_providers()
    person = insert(:person, name: "Anthony Palmini")

    {:ok, view, _html} = live(conn, ~p"/admin/people/#{person.id}/edit")

    search(view, "Matt Dinniman")

    assert view
           |> render()
           |> Floki.parse_document!()
           |> Floki.find("form#research-person input[name='name']")
           |> Floki.attribute("value") == ["Matt Dinniman"]
  end

  describe "the provenance flag" do
    test "shows the recorded source in the field header", %{conn: conn} do
      person =
        insert(:person,
          field_provenance: %{
            "name" => %{
              "source" => "provider:audible",
              "locked" => false,
              "at" => "2026-08-01T00:00:00Z"
            }
          }
        )

      {:ok, _view, html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      assert html =~ "from Audible"
    end

    test "no flag is rendered for records without provenance", %{conn: conn} do
      person = insert(:person)

      {:ok, _view, html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      refute html =~ "data-role=\"provenance-flag\""
    end
  end
end
