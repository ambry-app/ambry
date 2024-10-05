defmodule AmbryWeb.Preview.AudiobookController do
  use AmbryWeb, :controller

  alias Ambry.Media

  def show(conn, %{"id" => media_id}) do
    media = Media.get_media_with_book_details!(media_id)

    description = (media |> Media.get_media_description() |> String.slice(0..100)) <> "..."

    conn
    |> put_session(:user_return_to, current_path(conn))
    |> render(:show, %{
      media: media,
      page_title: description,
      og: %{
        title: description,
        image: media.thumbnails && unverified_url(conn, media.thumbnails.extra_large),
        description: media.description && truncate_markdown(media.description),
        url: url(conn, ~p"/audiobooks/#{media.id}")
      }
    })
  end

  defp truncate_markdown(markdown) do
    (markdown
     |> Earmark.as_html!()
     |> Floki.parse_document!()
     |> Floki.text()
     |> String.slice(0..252)) <>
      "..."
  end
end
