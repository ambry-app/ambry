defmodule AmbryWeb.Admin.EditParityTest do
  @moduledoc """
  Every decision the import form stages, the edit forms can propose.

  The asymmetry `EDIT_PARITY_PLAN.md` is about grew because nothing was
  watching it: fields were added to the inbox's draft one at a time, and the
  edit forms fell behind one at a time. This walks the draft's own decisions
  against the surfaces the edit forms render, so adding a decision to the
  import form is a failing test until somebody decides what the edit form
  does about it.

  It asserts the *offer*, not the wiring — a chip row that exists is a chip
  row an operator can click. Whether accepting it does the right thing is
  each form's own tests.
  """
  use AmbryWeb.ConnCase, async: false
  use Patch

  import Phoenix.ConnTest, except: [patch: 3]
  import Phoenix.LiveViewTest

  alias Ambry.Inbox.Draft
  alias Ambry.Metadata.Provider

  setup :register_and_log_in_admin_user

  # Bookkeeping, not decisions: where the values came from, and the
  # match/curation state the tiers are computed from.
  @not_a_decision [:sources]

  # One decision → where the edit form offers it. `:published_format` rides
  # its date, which is one control and one chip.
  @book_surfaces %{
    title: "#proposals-book_title",
    published: "#proposals-book_published",
    authors: "#proposals-authors",
    series: "#proposals-series"
  }

  @recording_surfaces %{
    title: "#proposals-media_title",
    published: "#proposals-media_published",
    published_format: "#proposals-media_published",
    publisher: "#proposals-media_publisher",
    description: "#proposals-description",
    cover: "#proposals-image",
    narrators: "#proposals-narrators",
    chapters: "#chapter-title-chips",
    # Not a provider's proposal: a set is named or joined, never fetched.
    # The parity claim is that the control exists at all, which is what
    # phase 5 was.
    recording_group: "input[name='media[recording_group][name]']"
  }

  @person_surfaces %{
    name: "#proposals-person_name",
    image: "#proposals-image",
    description: "#proposals-description"
  }

  defp decisions(schema), do: schema.__schema__(:embeds) -- @not_a_decision

  defp work_record do
    %Provider.Book{
      provider: "rreading_glasses",
      id: "76027608",
      title: "Dungeon Crawler Carl",
      published: %Provider.PublishedDate{date: ~D[2020-07-20], display_format: :full},
      authors: [%Provider.Contributor{id: "1", name: "Matt Dinniman", role: "author"}],
      series: [%Provider.Series{id: "2", name: "Dungeon Crawler Carl", number: "1"}]
    }
  end

  defp edition_record do
    %Provider.Book{
      provider: "audible",
      id: "B08BKGYQXW",
      asin: "B08BKGYQXW",
      title: "Dungeon Crawler Carl",
      publisher: "Audible Studios",
      description: "Carl goes into a dungeon.",
      cover_url: "https://example.test/covers/dcc.jpg",
      published: %Provider.PublishedDate{date: ~D[2020-07-20], display_format: :full},
      narrators: [%Provider.Contributor{id: "3", name: "Jeff Hays", role: "narrator"}]
    }
  end

  defp person_record do
    %Provider.Author{
      provider: "rreading_glasses",
      id: "999015",
      name: "Matt Dinniman",
      description: "Writes dungeon crawls.",
      image_url: "https://example.test/people/dinniman.jpg"
    }
  end

  defp tick_first_record(view) do
    view |> element(~s{[data-role="record"] input[type="checkbox"]}) |> render_click()
  end

  # Every decision has a home, and every home is somewhere the operator can
  # reach. The first half is what fails when the inbox grows a decision the
  # edit forms have not been told about.
  defp assert_parity(view, schema, surfaces) do
    for decision <- decisions(schema) do
      assert Map.has_key?(surfaces, decision),
             "#{inspect(schema)} stages #{inspect(decision)} and no edit form offers it. " <>
               "Give it a surface, or say here why it has none."
    end

    for {decision, selector} <- surfaces do
      assert has_element?(view, selector),
             "#{inspect(decision)} has no #{selector} on the form"
    end
  end

  test "the book form offers every decision the work level stages", %{conn: conn} do
    patch(Ambry.Metadata.Providers, :search_books, fn _provider, _query, _opts ->
      {:ok, [work_record()]}
    end)

    book = insert(:book, title: "Dungeon Crawler Carl", book_authors: [])

    {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

    view
    |> form("#research-work", %{"title" => "Dungeon Crawler Carl", "author" => "Matt Dinniman"})
    |> render_submit()

    render_async(view)
    tick_first_record(view)

    assert_parity(view, Draft.Work, @book_surfaces)
  end

  test "the audiobook form offers every decision the recording level stages", %{conn: conn} do
    patch(Ambry.Metadata.Search, :books, fn _query, opts ->
      case Keyword.fetch!(opts, :level) do
        :recording ->
          {:ok, entry} = Ambry.Metadata.Registry.fetch("audible")

          {[{entry, [edition_record()]}],
           [%{"id" => "audible", "name" => "Audible", "status" => "ok", "count" => 1}]}

        :work ->
          {[], []}
      end
    end)

    media = insert(:media, book: build(:book, title: "Dungeon Crawler Carl"))

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

    view
    |> form("#research-recording", %{
      "title" => "Dungeon Crawler Carl",
      "author" => "Matt Dinniman"
    })
    |> render_submit()

    render_async(view)
    tick_first_record(view)

    # the set control only stands up once the operator says there is a set
    view |> element("button[phx-click='add-group-row']") |> render_click()

    assert_parity(view, Draft.Recording, @recording_surfaces)
  end

  test "the person form offers every decision a person decision stages", %{conn: conn} do
    patch(Ambry.Metadata.Providers, :search_authors, fn
      "rreading_glasses", _query, _opts -> {:ok, [person_record()]}
      _other, _query, _opts -> {:ok, []}
    end)

    patch(Ambry.Metadata.Providers, :author_details, fn _provider, _id, _opts ->
      {:error, :not_found}
    end)

    person = insert(:person, name: "Matt Dinniman")

    {:ok, view, _html} = live(conn, ~p"/admin/people/#{person}/edit")

    view |> form("#research-person", %{"name" => "Matt Dinniman"}) |> render_submit()
    render_async(view)
    tick_first_record(view)

    assert_parity(view, Draft.PersonDecision, @person_surfaces)
  end
end
