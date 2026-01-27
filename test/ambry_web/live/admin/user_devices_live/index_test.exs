defmodule AmbryWeb.Admin.UserDevicesLive.IndexTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin_user

  describe "Index" do
    test "renders list of devices for a selected user", %{conn: conn} do
      user = insert(:user, email: "device_user@example.com")

      device1 = insert(:device, type: :web, browser: "Firefox", os_name: "Linux")

      insert(:device_user,
        device: device1,
        user: user,
        last_seen_at: ~U[2023-01-02 10:00:00.000000Z]
      )

      device2 =
        insert(:device,
          type: :android,
          brand: "Google",
          model_name: "Pixel 6",
          os_name: "Android"
        )

      insert(:device_user,
        device: device2,
        user: user,
        last_seen_at: ~U[2023-01-01 10:00:00.000000Z]
      )

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/devices")

      assert html =~ "Devices for device_user@example.com"

      # Check device 1 details - uses format_web_device
      assert html =~ "Firefox (Linux)"
      assert html =~ device1.id

      # Check device 2 details - uses format_mobile_device
      assert html =~ "Pixel 6 / Android"
      assert html =~ device2.id
    end

    test "orders devices by last_seen_at descending", %{conn: conn} do
      user = insert(:user)

      device1 = insert(:device, type: :android, model_name: "Old Device")

      insert(:device_user,
        device: device1,
        user: user,
        last_seen_at: ~U[2023-01-01 10:00:00.000000Z]
      )

      device2 = insert(:device, type: :android, model_name: "New Device")

      insert(:device_user,
        device: device2,
        user: user,
        last_seen_at: ~U[2023-01-03 10:00:00.000000Z]
      )

      device3 = insert(:device, type: :android, model_name: "Middle Device")

      insert(:device_user,
        device: device3,
        user: user,
        last_seen_at: ~U[2023-01-02 10:00:00.000000Z]
      )

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/devices")

      # Verify order in the rendered HTML
      html = render(view)

      first_idx = :binary.match(html, "New Device") |> elem(0)
      second_idx = :binary.match(html, "Middle Device") |> elem(0)
      third_idx = :binary.match(html, "Old Device") |> elem(0)

      assert first_idx < second_idx
      assert second_idx < third_idx
    end

    test "shows event counts", %{conn: conn} do
      user = insert(:user)
      device = insert(:device)
      insert(:device_user, device: device, user: user)

      # Events need to be associated with a playthrough owned by the user
      playthrough = insert(:playthrough, user: user)
      insert_list(3, :playback_event, device: device, playthrough: playthrough)

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/devices")

      assert html =~ "3"
    end
  end
end
