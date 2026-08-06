defmodule AmbryWeb.Admin.PersonPickerTest do
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

    # The picker asks every plausible hit for its details, so the mock has to
    # answer for every provider — not only the one whose photo lives there.
    patch(Providers, :author_details, fn
      "wikidata", "Q110191067", [] ->
        {:ok,
         %Provider.Author{
           provider: "wikidata",
           id: "Q110191067",
           name: "Matt Dinniman",
           image_url: @commons_image
         }}

      _provider, _id, [] ->
        {:error, :not_found}
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

  test "collects every photo every provider has into one grid", %{conn: conn} do
    patch_providers()

    view = open_picker(conn)
    html = render(view)

    # both image candidates present (proxied), the empty provider says so
    assert html =~ URI.encode_www_form(@gr_image)
    assert html =~ URI.encode_www_form(@commons_image)
    assert html =~ "nothing"

    # external search links are always offered
    assert html =~ "google.com/search?tbm=isch&amp;q=Matt+Dinniman"
    assert html =~ "duckduckgo.com"
  end

  # A profile photo has to survive a circular crop, and the obvious portrait
  # is frequently the one that doesn't. One image per provider can't offer
  # the alternative that works.
  test "every photo a provider has of one person is offered, not just the first" do
    alias Ambry.Metadata.PersonSearch

    patch(Providers, :search_authors, fn "tmdb", _query, [] ->
      {:ok, [%Provider.Author{provider: "tmdb", id: "42", name: "Jason Pargin"}]}
    end)

    patch(Providers, :author_details, fn "tmdb", "42", [] ->
      {:ok,
       Provider.Author.new(%{
         provider: "tmdb",
         id: "42",
         name: "Jason Pargin",
         description: "An American author.",
         image_urls: ["https://example.test/a.jpg", "https://example.test/b.jpg"]
       })}
    end)

    entry = %{id: "tmdb", display_name: "TMDB"}

    assert [match] = PersonSearch.matches(entry, "Jason Pargin")
    assert match.images == ["https://example.test/a.jpg", "https://example.test/b.jpg"]
    assert match.description == "An American author."
  end

  # `image_urls` is additive: a provider that only ever had one photo per
  # person still builds the struct the old way and must keep contributing it.
  test "a provider that only sets image_url still contributes its photo" do
    alias Ambry.Metadata.PersonSearch

    patch(Providers, :search_authors, fn "audnexus", _query, [] ->
      {:ok, [%Provider.Author{provider: "audnexus", id: "1", name: "Jason Pargin"}]}
    end)

    patch(Providers, :author_details, fn "audnexus", "1", [] ->
      {:ok,
       %Provider.Author{
         provider: "audnexus",
         id: "1",
         name: "Jason Pargin",
         image_url: @gr_image
       }}
    end)

    assert [match] =
             PersonSearch.matches(%{id: "audnexus", display_name: "Audnexus"}, "Jason Pargin")

    assert match.images == [@gr_image]
  end

  test "picking a candidate stages a URL import in the form", %{conn: conn} do
    patch_providers()

    view = open_picker(conn)

    view
    |> element(~s{button[phx-value-provider="wikidata"][phx-value-url]})
    |> render_click()

    html = render(view)

    # The picker STAYS OPEN: a photo and a bio are two decisions off one
    # search, and closing on the first made getting both mean running the whole
    # search again.
    assert html =~ "A photo for"

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
    |> element(~s{button[phx-value-provider="wikidata"][phx-value-url]})
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

  test "a top hit sharing no name token with the query is not offered", %{conn: conn} do
    # rreading-glasses author search is book-relevance driven: searching
    # the narrator "Jefferson Mays" surfaces the *author* James S.A. Corey
    patch(Providers, :search_authors, fn
      "rreading_glasses", _query, [] ->
        {:ok,
         [
           %Provider.Author{
             provider: "rreading_glasses",
             id: "1",
             name: "James S.A. Corey",
             image_url: @gr_image
           }
         ]}

      _other, _query, [] ->
        {:ok, []}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/people/new")

    view
    |> form("#person-form", %{"person" => %{"name" => "Jefferson Mays"}})
    |> render_change()

    view |> element("button[phx-click='open-image-picker']") |> render_click()
    html = render_async(view)

    refute html =~ URI.encode_www_form(@gr_image)
    refute html =~ "James S.A. Corey"
    assert html =~ "nothing"
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
