defmodule AmbryWeb.Admin.UserDevicesLive.IndexTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin_user

  describe "Index" do
    test "renders list of devices for a selected user", %{conn: conn} do
      user = insert(:user, email: "device_user@example.com")

      device1 =
        insert(:device,
          user: user,
          type: :web,
          browser: "Firefox",
          os_name: "Linux",
          last_seen_at: ~U[2023-01-02 10:00:00.000Z]
        )

      device2 =
        insert(:device,
          user: user,
          type: :android,
          brand: "Google",
          model_name: "Pixel 6",
          os_name: "Android",
          last_seen_at: ~U[2023-01-01 10:00:00.000Z]
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

      _device1 =
        insert(:device,
          user: user,
          type: :android,
          last_seen_at: ~U[2023-01-01 10:00:00.000Z],
          model_name: "Old Device"
        )

      _device2 =
        insert(:device,
          user: user,
          type: :android,
          last_seen_at: ~U[2023-01-03 10:00:00.000Z],
          model_name: "New Device"
        )

      _device3 =
        insert(:device,
          user: user,
          type: :android,
          last_seen_at: ~U[2023-01-02 10:00:00.000Z],
          model_name: "Middle Device"
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
      device = insert(:device, user: user)

      insert_list(3, :playback_event, device: device)

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/devices")

      assert html =~ "3"
    end
  end
end
