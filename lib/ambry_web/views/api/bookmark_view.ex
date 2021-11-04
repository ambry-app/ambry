defmodule AmbryWeb.API.BookmarkView do
  use AmbryWeb, :view

  alias AmbryWeb.API.BookmarkView

  def render("index.json", %{bookmarks: bookmarks, has_more?: has_more?}) do
    %{
      data: render_many(bookmarks, BookmarkView, "bookmark.json"),
      hasMore: has_more?
    }
  end

  def render("bookmark.json", %{bookmark: bookmark}) do
    %{
      id: bookmark.id,
      label: bookmark.label,
      position: bookmark.position
    }
  end
end
