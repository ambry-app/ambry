defmodule AmbryWeb.API.BookmarkController do
  use AmbryWeb, :controller

  import AmbryWeb.API.ControllerUtils

  alias Ambry.Media

  @limit 100

  def index(conn, %{"media_id" => media_id} = params) do
    offset = offset_from_params(params, @limit)

    {bookmarks, has_more?} =
      Media.list_bookmarks(conn.assigns.api_user.id, media_id, offset, @limit)

    render(conn, "index.json", bookmarks: bookmarks, has_more?: has_more?)
  end

  def create(conn, %{"bookmark" => bookmark_params}) do
    params = Map.put(bookmark_params, "user_id", conn.assigns.api_user.id)

    case Media.create_bookmark(params) do
      {:ok, bookmark} -> render(conn, "bookmark.json", bookmark: bookmark)
      {:error, _changeset} -> raise("bad params")
    end
  end

  def update(conn, %{"id" => bookmark_id, "bookmark" => %{"label" => new_label}}) do
    bookmark = Media.get_bookmark!(bookmark_id)

    {:ok, bookmark} = Media.update_bookmark(bookmark, %{label: new_label})

    render(conn, "bookmark.json", bookmark: bookmark)
  end

  def delete(conn, %{"id" => bookmark_id}) do
    bookmark = Media.get_bookmark!(bookmark_id)

    {:ok, _bookmark} = Media.delete_bookmark(bookmark)

    send_resp(conn, 201, "")
  end
end
