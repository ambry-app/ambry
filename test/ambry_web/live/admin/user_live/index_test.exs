defmodule AmbryWeb.Admin.UserLive.IndexTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin_user

  describe "Index" do
    test "renders list of users", %{conn: conn} do
      user =
        insert(:user,
          email: "test@example.com",
          admin: true,
          confirmed_at: ~N[2023-01-01 00:00:00]
        )

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      assert has_element?(view, "[data-role='user-email']", user.email)
      assert has_element?(view, "[data-role='is-admin']")
      assert has_element?(view, "[data-role='is-confirmed']")
    end

    test "shows media progress counts", %{conn: conn} do
      user = insert(:user)

      # Create 2 in-progress and 1 finished media
      :media
      |> insert()
      |> then(&insert(:player_state, user: user, media: &1, status: :in_progress))

      :media
      |> insert()
      |> then(&insert(:player_state, user: user, media: &1, status: :in_progress))

      :media
      |> insert()
      |> then(&insert(:player_state, user: user, media: &1, status: :finished))

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      assert has_element?(view, "[data-role='user-in-progress']", "2")
      assert has_element?(view, "[data-role='user-finished']", "1")
    end
  end

  describe "Admin actions" do
    test "can promote a user to admin", %{conn: conn} do
      user = insert(:user, admin: false)

      refute user.admin

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      view
      |> element("[data-role='promote-admin']")
      |> render_click()

      assert render(view) =~ "User promoted to admin"

      user = Ambry.Accounts.get_user!(user.id)

      assert user.admin
    end

    test "can demote an admin user", %{conn: conn} do
      user = insert(:user, admin: true)

      assert user.admin

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      view
      |> element("[data-role='demote-admin']")
      |> render_click()

      assert render(view) =~ "User demoted from admin"

      user = Ambry.Accounts.get_user!(user.id)

      refute user.admin
    end

    test "cannot demote yourself", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      refute has_element?(view, "[data-role='demote-admin']")
      assert has_element?(view, "[data-role='is-admin']")
    end

    test "can delete a user", %{conn: conn} do
      user = insert(:user)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      assert has_element?(view, "[data-role='user-email']", user.email)

      view
      |> element("[data-role='delete-user']")
      |> render_click()

      refute has_element?(view, "[data-role='user-email']", user.email)
      assert render(view) =~ "User deleted successfully"

      assert_raise Ecto.NoResultsError, fn -> Ambry.Accounts.get_user!(user.id) end
    end

    test "cannot delete yourself", %{conn: conn, user: current_user} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      assert has_element?(view, "[data-role='user-email']", current_user.email)
      refute has_element?(view, "[data-role='delete-user']")
    end
  end

  describe "Search" do
    test "filters users by search query", %{conn: conn} do
      user1 = insert(:user, email: "unique@example.com")
      user2 = insert(:user, email: "another@example.com")

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Initially shows all users
      assert has_element?(view, "[data-role='user-email']", user1.email)
      assert has_element?(view, "[data-role='user-email']", user2.email)

      # Search for specific user
      view
      |> form("[data-role='search-form']")
      |> render_submit(%{search: %{query: "unique"}})

      # Should only show matching user
      assert has_element?(view, "[data-role='user-email']", user1.email)
      refute has_element?(view, "[data-role='user-email']", user2.email)
    end
  end

  describe "Sort" do
    test "sorts users by different fields", %{conn: conn, user: current_user} do
      _user1 = insert(:user, email: "a@example.com", inserted_at: ~N[2023-01-01 00:00:00])
      _user2 = insert(:user, email: "b@example.com", inserted_at: ~N[2023-02-01 00:00:00])

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Default sort is inserted_at desc, so newer user should be first
      emails =
        view
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("[data-role='user-email']")
        |> Enum.map(&Floki.text/1)
        |> Enum.reject(&(&1 == current_user.email))

      assert emails == ["b@example.com", "a@example.com"]

      # Sort by email ascending
      view
      |> element("[data-role=sort-button][phx-value-field=email]")
      |> render_click()

      emails =
        view
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("[data-role='user-email']")
        |> Enum.map(&Floki.text/1)
        |> Enum.reject(&(&1 == current_user.email))

      assert emails == ["a@example.com", "b@example.com"]

      # Click again for descending
      view
      |> element("[data-role=sort-button][phx-value-field=email]")
      |> render_click()

      emails =
        view
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("[data-role='user-email']")
        |> Enum.map(&Floki.text/1)
        |> Enum.reject(&(&1 == current_user.email))

      assert emails == ["b@example.com", "a@example.com"]
    end
  end
end
