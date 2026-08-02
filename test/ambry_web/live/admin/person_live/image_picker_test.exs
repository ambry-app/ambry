defmodule AmbryWeb.Admin.PersonLive.ImagePickerTest do
  use AmbryWeb.ConnCase, async: false
  use Patch

  import Phoenix.ConnTest, except: [patch: 3]
  import Phoenix.LiveViewTest

  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers
  alias Ambry.Provenance

  setup :register_and_log_in_admin_user

  @gr_image "https://images.gr-assets.com/authors/999015.jpg"
  @commons_image "https://commons.wikimedia.org/wiki/Special:FilePath/Matt%20Dinniman.jpg?width=1200"

  # the picker fans out over the enabled author-search providers
  # (rreading_glasses, audnexus, wikidata in the zero-config test env):
  # one with an image on the search hit, one with no results, and one that
  # needs the details round-trip for its image
  defp patch_providers do
    patch(Providers, :search_authors, fn
      "rreading_glasses", _query, [] ->
        {:ok,
         [
           %Provider.Author{
             provider: "rreading_glasses",
             id: "999015",
             name: "Matt Dinniman",
             image_url: @gr_image
           }
         ]}

      "audnexus", _query, [] ->
        {:ok, []}

      "wikidata", _query, [] ->
        {:ok, [%Provider.Author{provider: "wikidata", id: "Q110191067", name: "Matt Dinniman"}]}
    end)

    patch(Providers, :author_details, fn "wikidata", "Q110191067", [] ->
      {:ok,
       %Provider.Author{
         provider: "wikidata",
         id: "Q110191067",
         name: "Matt Dinniman",
         image_url: @commons_image
       }}
    end)
  end

  defp open_picker(conn) do
    {:ok, view, _html} = live(conn, ~p"/admin/people/new")

    view
    |> form("#person-form", %{"person" => %{"name" => "Matt Dinniman"}})
    |> render_change()

    view |> element("button[phx-click='open-image-picker']") |> render_click()
    render_async(view)

    view
  end

  test "collects each provider's best-match photo into a grid", %{conn: conn} do
    patch_providers()

    view = open_picker(conn)
    html = render(view)

    # both image candidates present (proxied), the empty provider says so
    assert html =~ URI.encode_www_form(@gr_image)
    assert html =~ URI.encode_www_form(@commons_image)
    assert html =~ "No match"

    # external search links are always offered
    assert html =~ "google.com/search?tbm=isch&amp;q=Matt+Dinniman"
    assert html =~ "duckduckgo.com"
  end

  test "picking a candidate stages a URL import in the form", %{conn: conn} do
    patch_providers()

    view = open_picker(conn)

    view
    |> element(~s{button[phx-value-source="provider:wikidata"]})
    |> render_click()

    html = render(view)

    # modal closed, form switched to url_import with the picked URL staged
    refute html =~ "Find images</h2>"

    assert view |> element("#person-form input[name='person[image_import_url]']") |> render() =~
             "Special:FilePath"
  end

  test "saving a picked image records the provider as image provenance", %{conn: conn} do
    patch_providers()

    %{web_path: web_path} = Ambry.Factory.valid_image(:person)

    patch(AmbryWeb.Admin.UploadHelpers, :handle_image_import, fn url ->
      assert url == @commons_image
      {:ok, web_path}
    end)

    view = open_picker(conn)

    view
    |> element(~s{button[phx-value-source="provider:wikidata"]})
    |> render_click()

    view |> form("#person-form", %{"person" => %{}}) |> render_submit()

    person = Ambry.Repo.get_by!(Ambry.People.Person, name: "Matt Dinniman")

    assert person.image_path == web_path

    # picked from a provider: provider source, unlocked
    assert %{"source" => "provider:wikidata", "locked" => false} =
             Provenance.entry(person, :image_path)

    # typed by hand: manual, locked
    assert %{"source" => "manual", "locked" => true} = Provenance.entry(person, :name)
  end

  test "the find-images button is disabled until the person has a name", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/people/new")

    assert has_element?(view, "button[phx-click='open-image-picker'][disabled]")

    view
    |> form("#person-form", %{"person" => %{"name" => "Somebody"}})
    |> render_change()

    refute has_element?(view, "button[phx-click='open-image-picker'][disabled]")
  end
end
