defmodule AmbrySchema.MediaTest do
  use AmbryWeb.ConnCase

  import Absinthe.Relay.Node, only: [to_global_id: 2]
  import Ambry.GraphQLSigil

  setup :register_and_put_user_api_token

  # Asked through `mediaChangedSince` rather than `node(id:)`, which is the
  # query the app actually issues. The field resolvers are the same ones; the
  # node door was retired with the server-driven client it was built for.
  describe "mediaChangedSince" do
    @query ~G"""
    query Media {
      mediaChangedSince {
        id
        fullCast
        abridged
        duration
        mpdPath
        hlsPath
        chapters {
          id
          title
          startTime
          endTime
        }
        book {
          id
        }
        insertedAt
        updatedAt
      }
    }
    """
    test "resolves a recording's fields", %{conn: conn} do
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
        book_id: book_id,
        full_cast: full_cast,
        abridged: abridged,
        duration: duration,
        mpd_path: mpd_path,
        hls_path: hls_path
      } = media

      gid = to_global_id("Media", id)
      book_gid = to_global_id("Book", book_id)

      conn = post(conn, "/gql", %{"query" => @query})

      duration_match = Decimal.to_float(duration)

      assert %{
               "data" => %{
                 "mediaChangedSince" => [
                   %{
                     "id" => ^gid,
                     "fullCast" => ^full_cast,
                     "abridged" => ^abridged,
                     "duration" => ^duration_match,
                     "mpdPath" => ^mpd_path,
                     "hlsPath" => ^hls_path,
                     "chapters" => [
                       %{
                         "id" => "gY",
                         "startTime" => start_time,
                         "endTime" => _,
                         "title" => "Chapter 1"
                       }
                     ],
                     "book" => %{"id" => ^book_gid},
                     "insertedAt" => "" <> _,
                     "updatedAt" => "" <> _
                   }
                 ]
               }
             } = json_response(conn, 200)

      assert start_time == 0.0
    end
  end
end
