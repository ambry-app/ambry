defmodule AmbrySchema.MediaTest do
  use AmbryWeb.ConnCase

  import Absinthe.Relay.Node, only: [to_global_id: 2, from_global_id: 2]
  import Ambry.GraphQLSigil

  setup :register_and_put_user_api_token

  describe "Media node" do
    @query ~G"""
    query Media($id: ID!) {
      node(id: $id) {
        id
        ... on Media {
          fullCast
          abridged
          duration
          mpdPath
          hlsPath
          description
          imagePath
          chapters {
            id
            title
            startTime
            endTime
          }
          book {
            __typename
          }
          narrators {
            __typename
          }
          insertedAt
          updatedAt
        }
      }
    }
    """
    test "resolves Media fields", %{conn: conn, user: user} do
      media =
        :media
        |> build(
          book: build(:book),
          media_narrators: [
            build(:media_narrator, narrator: build(:narrator, person: build(:person)))
          ],
          chapters: [build(:chapter, title: "Chapter 1", time: Decimal.new(0))]
        )
        |> with_source_files()
        |> insert()
        |> with_output_files()

      %{
        id: id,
        full_cast: full_cast,
        abridged: abridged,
        duration: duration,
        mpd_path: mpd_path,
        hls_path: hls_path
      } = media

      gid = to_global_id("Media", id)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{id: gid}
        })

      duration_match = Decimal.to_float(duration)

      assert %{
               "data" => %{
                 "node" => %{
                   "id" => ^gid,
                   "fullCast" => ^full_cast,
                   "abridged" => ^abridged,
                   "duration" => ^duration_match,
                   "mpdPath" => ^mpd_path,
                   "hlsPath" => ^hls_path,
                   "chapters" => [
                     %{
                       "id" => "gY",
                       "startTime" => t,
                       "endTime" => _,
                       "title" => "Chapter 1"
                     }
                   ],
                   "book" => %{"__typename" => "Book"},
                   "narrators" => [%{"__typename" => "Narrator"}],
                   "insertedAt" => "" <> _,
                   "updatedAt" => "" <> _
                 }
               }
             } = json_response(conn, 200)

      assert t == 0.0
    end
  end
end
