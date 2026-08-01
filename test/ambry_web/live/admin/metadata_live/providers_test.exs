defmodule AmbryWeb.Admin.MetadataLive.ProvidersTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Metadata.Registry

  setup :register_and_log_in_admin_user

  test "renders all known providers", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/metadata-providers")

    assert html =~ "rreading-glasses"
    assert html =~ "Audible"
    assert html =~ "Audnexus"
  end

  test "toggles a provider off and on", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/metadata-providers")

    view |> element("button[phx-value-id='audible'][phx-click='toggle']") |> render_click()

    {:ok, entry} = Registry.fetch("audible")
    refute entry.enabled

    view |> element("button[phx-value-id='audible'][phx-click='toggle']") |> render_click()

    {:ok, entry} = Registry.fetch("audible")
    assert entry.enabled
  end

  test "saves provider config", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/metadata-providers")

    view
    |> form("form[phx-submit='save-config']", %{
      "provider_id" => "rreading_glasses",
      "config" => %{"base_url" => "http://rg.local:8788"}
    })
    |> render_submit()

    {:ok, entry} = Registry.fetch("rreading_glasses")
    assert entry.config.base_url == "http://rg.local:8788"
  end

  test "reorders providers within a level", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/metadata-providers")

    view
    |> element("button[phx-value-id='audnexus'][phx-value-direction='up']")
    |> render_click()

    ids = Registry.all() |> Enum.map(& &1.id)
    assert Enum.find_index(ids, &(&1 == "audnexus")) < Enum.find_index(ids, &(&1 == "audible"))
  end
end
