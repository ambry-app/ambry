defmodule AmbryWeb.Admin.InboxLive.ReorderTest do
  @moduledoc """
  Reordering credits on the import form.

  List order is billing order — the importer writes `position` from it — so
  before this the operator's only lever over who came first was remove +
  re-add, which threw curation away.
  """
  use AmbryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ambry.Inbox
  alias Ambry.Repo

  setup :register_and_log_in_admin_user

  # The fixture credits two narrators via its composer tag, which is exactly
  # a list whose order the operator might want to change.
  defp probed_item do
    dir = Ambry.Paths.source_media_disk_path("tagged-#{Ecto.UUID.generate()}")
    root = Path.join(dir, "The Way of Kings [M4B]")
    File.mkdir_p!(root)
    path = Path.join(root, "book.m4b")

    {_output, 0} =
      System.cmd("ffmpeg", [
        "-v",
        "quiet",
        "-i",
        valid_audio(:m4a),
        "-c",
        "copy",
        "-metadata",
        "album=The Way of Kings",
        "-metadata",
        "artist=Brandon Sanderson",
        "-metadata",
        "composer=Michael Kramer, Kate Reading",
        "-metadata",
        "date=2010-08-31",
        path
      ])

    {:ok, _counts} = Inbox.discover(dir)
    {[item], false} = Inbox.list_items(filter: "The Way of Kings")
    {:ok, item} = Inbox.probe_item(item)
    Repo.delete_all(Oban.Job)
    {:ok, item} = Inbox.prepare_draft(item)
    item
  end

  defp narrator_names(item_id) do
    Enum.map(Inbox.get_item!(item_id).draft.recording.narrators, & &1.name)
  end

  test "the narrator cards offer arrows, and moving one reorders the billing", %{conn: conn} do
    item = probed_item()
    assert narrator_names(item.id) == ["Michael Kramer", "Kate Reading"]

    {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

    assert has_element?(view, "[phx-click='move-credit'][phx-value-section='recording']")

    view
    |> element(
      "[phx-click='move-credit'][phx-value-section='recording'][phx-value-index='0'][phx-value-direction='down']"
    )
    |> render_click()

    assert narrator_names(item.id) == ["Kate Reading", "Michael Kramer"]

    # an order the operator chose is an answer, and answers survive reseeds
    assert Enum.all?(Inbox.get_item!(item.id).draft.recording.narrators, & &1.curated)
  end

  test "a one-row list offers no arrows", %{conn: conn} do
    item = probed_item()

    {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

    # one author (Brandon Sanderson) — nothing to reorder there
    refute has_element?(view, "[phx-click='move-credit'][phx-value-section='work']")
  end
end
