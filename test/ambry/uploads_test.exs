defmodule Ambry.UploadsTest do
  use Ambry.DataCase

  alias Ambry.Uploads

  describe "create_upload/1" do
    test "can create everything about an upload using deeply nested params" do
      params = %{
        title: "Upload Title",
        files: [
          %{
            path: "/foo/bar",
            filename: "baz.txt"
          }
        ],
        book: %{
          title: "Book Title",
          published: "2023-01-01",
          book_authors: [
            %{
              author: %{
                name: "Author Name",
                person: %{
                  name: "Person Name"
                }
              }
            }
          ],
          series_books: [
            %{
              book_number: "2.1",
              series: %{
                name: "Series Name"
              }
            }
          ]
        }
      }

      assert {:ok, upload} = Uploads.create_upload(params)

      assert %{
               title: "Upload Title",
               book: %{
                 title: "Book Title",
                 book_authors: [%{author: %{name: "Author Name", person: %{name: "Person Name"}}}],
                 series_books: [%{series: %{name: "Series Name"}}]
               }
             } = upload

      dbg(upload)

      new_book = insert(:book)

      # update_params = %{
      #   id: upload.id
      # }

      upload
      |> Uploads.Upload.changeset(%{})
      |> Ecto.Changeset.put_assoc(:book, new_book)
      |> Ambry.Repo.update!()
      |> dbg()
    end

    # test "can create a upload with an existing book" do
    #   %{title: book_title} = book = insert(:book)

    #   params = %{
    #     title: "Upload Title",
    #     files: [
    #       %{
    #         path: "/foo/bar",
    #         filename: "baz.txt"
    #       }
    #     ],
    #     book: %{
    #       id: book.id,
    #       title: book.title,
    #       published: book.published
    #     }
    #   }

    #   assert {:ok, upload} = Uploads.create_upload(params)

    #   dbg(Ambry.Books.list_books())

    #   assert %{
    #            title: "Upload Title",
    #            book: %{
    #              title: ^book_title
    #            }
    #          } = upload
    # end
  end
end
