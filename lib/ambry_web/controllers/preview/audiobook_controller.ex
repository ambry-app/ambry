defmodule AmbryWeb.Preview.AudiobookController do
  use AmbryWeb, :controller

  import Absinthe.Relay.Node, only: [to_global_id: 3]
  import AmbryWeb.Helpers.IdHelpers

  alias Ambry.Media

  def show(conn, %{"id" => id_param}) do
    with {:ok, media_id} <- parse_id(id_param, :media),
         {:ok, media} <- Media.fetch_media_with_book_details(media_id) do
      description = (media |> Media.get_media_description() |> String.slice(0..100)) <> "..."
      global_id = to_global_id("Media", media.id, AmbrySchema)

      conn
      |> put_session(:user_return_to, current_path(conn))
      |> render(:show, %{
        media: media,
        global_id: global_id,
        page_title: description,
        og: %{
          title: description,
          image: media.thumbnails && unverified_url(conn, media.thumbnails.extra_large),
          description: media.description && truncate_markdown(media.description),
          url: url(conn, ~p"/audiobooks/#{media.id}")
        }
      })
    else
      _ ->
        conn
        |> put_status(:not_found)
        |> put_view(AmbryWeb.ErrorHTML)
        |> render(:"404")
    end
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
