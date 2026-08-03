defmodule Ambry.MediaTest do
  use Ambry.DataCase

  alias Ambry.Media
  alias Ambry.Paths
  alias Ambry.Thumbnails.GenerateThumbnails
  alias Ambry.Utils.DeleteFiles

  describe "get_media_file_details/1" do
    test "delegates to Audit" do
      media =
        :media
        |> build(book: build(:book))
        |> with_source_files()
        |> insert()
        |> with_output_files()

      assert %{} = Media.get_media_file_details(media)
    end
  end

  describe "orphaned_files_audit/0" do
    test "delegates to Audit" do
      assert %{} = Media.orphaned_files_audit()
    end
  end

  describe "list_media/0" do
    test "returns the first 10 media sorted by title" do
      insert_list(11, :media, book: fn -> build(:book) end)

      {returned_media, has_more?} = Media.list_media()

      assert has_more?
      assert length(returned_media) == 10
    end
  end

  describe "list_media/1" do
    test "accepts an offset" do
      insert_list(11, :media, book: fn -> build(:book) end)

      {returned_media, has_more?} = Media.list_media(10)

      refute has_more?
      assert length(returned_media) == 1
    end
  end

  describe "list_media/2" do
    test "accepts a limit" do
      insert_list(6, :media, book: fn -> build(:book) end)

      {returned_media, has_more?} = Media.list_media(0, 5)

      assert has_more?
      assert length(returned_media) == 5
    end
  end

  describe "list_media/3" do
    test "accepts a 'search' filter that searches by book title" do
      [_m1, _m2, m3, _m4, _m5] = insert_list(5, :media, book: fn -> build(:book) end)

      %{id: id, book: %{title: title}} = m3

      {[matched], has_more?} = Media.list_media(0, 10, %{search: title})

      refute has_more?
      assert matched.id == id
    end

    test "accepts a 'search' filter that searches by series name" do
      insert_list(5, :media,
        book: fn ->
          build(:book, series_books: [build(:series_book, series: build(:series))])
        end
      )

      series_name = "Unique Series Name-#{Ecto.UUID.generate()}"

      target =
        insert(:media,
          book:
            build(:book,
              series_books: [build(:series_book, series: build(:series, name: series_name))]
            )
        )

      {[matched], has_more?} = Media.list_media(0, 10, %{search: series_name})

      refute has_more?
      assert matched.id == target.id
    end

    test "accepts a 'search' filter that searches by author name" do
      insert_list(5, :media,
        book: fn ->
          build(:book,
            book_authors: [build(:book_author, author: build(:author, person: build(:person)))]
          )
        end
      )

      author_name = "Unique Author Name-#{Ecto.UUID.generate()}"

      target =
        insert(:media,
          book:
            build(:book,
              book_authors: [
                build(:book_author,
                  author: build(:author, name: author_name, person: build(:person))
                )
              ]
            )
        )

      {[matched], has_more?} = Media.list_media(0, 10, %{search: author_name})

      refute has_more?
      assert matched.id == target.id
    end

    test "accepts a 'search' filter that searches by author's person name" do
      insert_list(5, :media,
        book: fn ->
          build(:book,
            book_authors: [build(:book_author, author: build(:author, person: build(:person)))]
          )
        end
      )

      person_name = "Unique Person Name-#{Ecto.UUID.generate()}"

      target =
        insert(:media,
          book:
            build(:book,
              book_authors: [
                build(:book_author,
                  author: build(:author, person: build(:person, name: person_name))
                )
              ]
            )
        )

      {[matched], has_more?} = Media.list_media(0, 10, %{search: person_name})

      refute has_more?
      assert matched.id == target.id
    end

    test "accepts a 'search' filter that searches by narrator name" do
      insert_list(5, :media,
        book: fn ->
          build(:book,
            book_authors: [build(:book_author, author: build(:author, person: build(:person)))]
          )
        end
      )

      narrator_name = "Unique Narrator Name-#{Ecto.UUID.generate()}"

      target =
        insert(:media,
          book: build(:book),
          media_narrators: [
            build(:media_narrator,
              narrator: build(:narrator, name: narrator_name, person: build(:person))
            )
          ]
        )

      {[matched], has_more?} = Media.list_media(0, 10, %{search: narrator_name})

      refute has_more?
      assert matched.id == target.id
    end

    test "accepts a 'search' filter that searches by narrator's person name" do
      insert_list(5, :media,
        book: fn ->
          build(:book,
            book_authors: [build(:book_author, author: build(:author, person: build(:person)))]
          )
        end
      )

      person_name = "Unique Person Name-#{Ecto.UUID.generate()}"

      target =
        insert(:media,
          book: build(:book),
          media_narrators: [
            build(:media_narrator,
              narrator: build(:narrator, person: build(:person, name: person_name))
            )
          ]
        )

      {[matched], has_more?} = Media.list_media(0, 10, %{search: person_name})

      refute has_more?
      assert matched.id == target.id
    end

    test "accepts a 'status' filter" do
      %{id: id} = insert(:media, book: build(:book), status: :pending)

      {[%{id: ^id}], false} = Media.list_media(0, 10, %{status: :pending})
      {[], false} = Media.list_media(0, 10, %{status: :ready})
    end

    test "accepts a 'full_cast' filter" do
      %{id: id} = insert(:media, book: build(:book), full_cast: true)

      {[%{id: ^id}], false} = Media.list_media(0, 10, %{full_cast: true})
      {[], false} = Media.list_media(0, 10, %{full_cast: false})
    end

    test "accepts a 'abridged' filter" do
      %{id: id} = insert(:media, book: build(:book), abridged: true)

      {[%{id: ^id}], false} = Media.list_media(0, 10, %{abridged: true})
      {[], false} = Media.list_media(0, 10, %{abridged: false})
    end

    test "accepts a 'has_chapters' filter" do
      %{id: id} = insert(:media, book: build(:book), chapters: [])

      {[%{id: ^id}], false} = Media.list_media(0, 10, %{has_chapters: false})
      {[], false} = Media.list_media(0, 10, %{has_chapters: true})
    end
  end

  describe "list_media/4" do
    test "allows sorting results by any field on the schema" do
      %{id: media1_id} = insert(:media, book: build(:book, title: "Apple"))
      %{id: media2_id} = insert(:media, book: build(:book, title: "Banana"))
      %{id: media3_id} = insert(:media, book: build(:book, title: "Carrot"))

      {media, false} = Media.list_media(0, 10, %{}, :book)

      assert [
               %{id: ^media1_id},
               %{id: ^media2_id},
               %{id: ^media3_id}
             ] = media

      {media, false} = Media.list_media(0, 10, %{}, {:desc, :book})

      assert [
               %{id: ^media3_id},
               %{id: ^media2_id},
               %{id: ^media1_id}
             ] = media
    end
  end

  describe "count_media/0" do
    test "returns the number of media in the database" do
      insert_list(3, :media, book: fn -> build(:book) end)

      assert 3 = Media.count_media()
    end
  end

  describe "get_media!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Media.get_media!(-1)
      end
    end

    test "returns the media with the given id" do
      %{id: id} = insert(:media, book: build(:book))

      assert %Media.Media{id: ^id} = Media.get_media!(id)
    end
  end

  describe "fetch_media/1" do
    test "returns error if id is invalid" do
      assert {:error, :not_found} = Media.fetch_media(-1)
    end

    test "returns the media with the given id" do
      %{id: id} = insert(:media, book: build(:book))

      assert {:ok, %Media.Media{id: ^id}} = Media.fetch_media(id)
    end
  end

  describe "create_media/1" do
    test "requires book and source_path to be set" do
      {:error, changeset} = Media.create_media(%{})

      assert %{
               book_id: ["can't be blank"],
               source_path: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "creates a media when given valid attributes" do
      %{id: book_id} = insert(:book)

      params =
        :media
        |> params_for(book_id: book_id)
        |> Map.take([:abridged, :full_cast, :source_path, :book_id])

      assert {:ok, media} = Media.create_media(params)

      assert %{book_id: ^book_id} = media
    end

    test "can create nested media narrators" do
      %{id: book_id} = insert(:book)
      %{id: narrator_id} = insert(:narrator, person: build(:person))

      params =
        :media
        |> params_for(
          book_id: book_id,
          media_narrators: [%{narrator_id: narrator_id}]
        )
        |> Map.take([:abridged, :full_cast, :source_path, :book_id, :media_narrators])

      assert {:ok, media} = Media.create_media(params)

      assert %{media_narrators: [%{narrator_id: ^narrator_id}]} = media
    end

    test "updates the search index" do
      %{id: book_id} = insert(:book)
      %{id: narrator_id, name: narrator_name} = insert(:narrator, person: build(:person))

      assert [] = Ambry.Search.search(narrator_name)

      params =
        :media
        |> params_for(
          book_id: book_id,
          media_narrators: [%{narrator_id: narrator_id}]
        )
        |> Map.take([:abridged, :full_cast, :source_path, :book_id, :media_narrators])

      assert {:ok, _media} = Media.create_media(params)

      assert [%{id: ^book_id}] = Ambry.Search.search(narrator_name)
    end
  end

  describe "display-title override" do
    test "creates media with a title override" do
      %{id: book_id} = insert(:book)

      params =
        :media
        |> params_for(book_id: book_id, title: "The Three-Body Problem (English)")
        |> Map.take([:abridged, :full_cast, :source_path, :book_id, :title])

      assert {:ok, media} = Media.create_media(params)

      assert %{title: "The Three-Body Problem (English)"} = media
    end
  end

  describe "multi-part recordings" do
    test "creates media with part fields and a new named recording group" do
      %{id: book_id} = insert(:book)

      params =
        :media
        |> params_for(
          book_id: book_id,
          part_number: 1,
          parts_total: 3,
          recording_group_choice: "new",
          recording_group_name: "Season One"
        )
        |> Map.take([
          :abridged,
          :full_cast,
          :source_path,
          :book_id,
          :part_number,
          :parts_total,
          :recording_group_choice,
          :recording_group_name
        ])

      assert {:ok, media} = Media.create_media(params)

      assert %{part_number: 1, parts_total: 3, recording_group: %{name: "Season One"}} = media
      assert [{"Season One", _id}] = Media.recording_groups_for_select(book_id)

      # label visibility defaults to off — an explicit choice, never
      # inferred from the label's presence
      assert media.recording_group.show_label == false
    end

    test "the group's show_label flag is set at creation and toggled on rename" do
      %{id: book_id} = insert(:book)

      params =
        :media
        |> params_for(
          book_id: book_id,
          recording_group_choice: "new",
          recording_group_name: "Season One",
          recording_group_show_label: "true"
        )
        |> Map.take([
          :abridged,
          :full_cast,
          :source_path,
          :book_id,
          :recording_group_choice,
          :recording_group_name,
          :recording_group_show_label
        ])

      assert {:ok, media} = Media.create_media(params)
      assert media.recording_group.show_label == true

      group_id = media.recording_group.id

      # toggling off through the linked-group edit path
      assert {:ok, _updated} =
               Media.update_media(Media.get_media!(media.id), %{
                 recording_group_choice: to_string(group_id),
                 recording_group_show_label: "false"
               })

      assert Ambry.Repo.get!(Ambry.Media.RecordingGroup, group_id).show_label == false
    end

    test "links a sibling part to an existing group via the choice field" do
      %{id: book_id} = insert(:book)

      {:ok, part_one} =
        :media
        |> params_for(book_id: book_id, part_number: 1, recording_group_choice: "new")
        |> Map.take([
          :abridged,
          :full_cast,
          :source_path,
          :book_id,
          :part_number,
          :recording_group_choice
        ])
        |> Media.create_media()

      group_id = part_one.recording_group.id

      {:ok, part_two} =
        :media
        |> params_for(
          book_id: book_id,
          part_number: 2,
          recording_group_choice: to_string(group_id)
        )
        |> Map.take([
          :abridged,
          :full_cast,
          :source_path,
          :book_id,
          :part_number,
          :recording_group_choice
        ])
        |> Media.create_media()

      assert part_two.recording_group_id == group_id

      # unnamed groups get a readable select label
      assert [{"Unnamed group #" <> _, ^group_id}] = Media.recording_groups_for_select(book_id)
    end

    test "clearing the last member deletes the orphaned group" do
      %{id: book_id} = insert(:book)

      {:ok, media} =
        :media
        |> params_for(book_id: book_id, recording_group_choice: "new")
        |> Map.take([:abridged, :full_cast, :source_path, :book_id, :recording_group_choice])
        |> Media.create_media()

      assert media.recording_group_id

      {:ok, updated} =
        Media.update_media(Media.get_media!(media.id), %{recording_group_choice: "none"})

      assert updated.recording_group_id == nil
      assert [] = Media.recording_groups_for_select(book_id)
      assert Ambry.Repo.aggregate(Ambry.Media.RecordingGroup, :count) == 0
    end

    test "renames the linked group from any part (shared by all parts)" do
      %{id: book_id} = insert(:book)

      {:ok, part_one} =
        :media
        |> params_for(book_id: book_id, recording_group_choice: "new")
        |> Map.take([:abridged, :full_cast, :source_path, :book_id, :recording_group_choice])
        |> Media.create_media()

      group_id = part_one.recording_group.id

      {:ok, updated} =
        Media.update_media(Media.get_media!(part_one.id), %{
          recording_group_choice: to_string(group_id),
          recording_group_name: "Season One"
        })

      assert %{recording_group: %{name: "Season One"}} = updated
      assert [{"Season One", ^group_id}] = Media.recording_groups_for_select(book_id)
    end

    test "clears a group's name with an empty string" do
      %{id: book_id} = insert(:book)

      {:ok, media} =
        :media
        |> params_for(
          book_id: book_id,
          recording_group_choice: "new",
          recording_group_name: "Typo Name"
        )
        |> Map.take([
          :abridged,
          :full_cast,
          :source_path,
          :book_id,
          :recording_group_choice,
          :recording_group_name
        ])
        |> Media.create_media()

      group_id = media.recording_group.id

      {:ok, updated} =
        Media.update_media(Media.get_media!(media.id), %{
          recording_group_choice: to_string(group_id),
          recording_group_name: ""
        })

      assert %{recording_group: %{name: nil}} = updated
    end

    test "the name field is ignored when switching to a different group" do
      %{id: book_id} = insert(:book)

      {:ok, first} =
        :media
        |> params_for(
          book_id: book_id,
          recording_group_choice: "new",
          recording_group_name: "Keep Me"
        )
        |> Map.take([
          :abridged,
          :full_cast,
          :source_path,
          :book_id,
          :recording_group_choice,
          :recording_group_name
        ])
        |> Media.create_media()

      {:ok, second} =
        :media
        |> params_for(book_id: book_id, recording_group_choice: "new")
        |> Map.take([:abridged, :full_cast, :source_path, :book_id, :recording_group_choice])
        |> Media.create_media()

      keep_me_id = first.recording_group.id

      # switch `second` over to the first group while a stale name value posts
      {:ok, moved} =
        Media.update_media(Media.get_media!(second.id), %{
          recording_group_choice: to_string(keep_me_id),
          recording_group_name: "Keep Me"
        })

      assert moved.recording_group_id == keep_me_id
      assert [{"Keep Me", ^keep_me_id}] = Media.recording_groups_for_select(book_id)
    end

    test "validates part fields" do
      %{id: book_id} = insert(:book)

      params =
        :media
        |> params_for(book_id: book_id, part_number: 3, parts_total: 2)
        |> Map.take([:abridged, :full_cast, :source_path, :book_id, :part_number, :parts_total])

      {:error, changeset} = Media.create_media(params)

      assert %{part_number: ["can't be greater than the total number of parts"]} =
               errors_on(changeset)
    end

    test "part_label/1 and display_title/1" do
      alias Ambry.Media.Media, as: MediaSchema

      assert MediaSchema.part_label(%{part_number: nil, parts_total: nil}) == nil
      assert MediaSchema.part_label(%{part_number: 2, parts_total: nil}) == "Part 2"
      assert MediaSchema.part_label(%{part_number: 2, parts_total: 3}) == "Part 2 of 3"

      book = build(:book, title: "The Way of Kings")

      plain = build(:media, book: book, part_number: nil, parts_total: nil, title: nil)
      assert MediaSchema.display_title(plain) == "The Way of Kings"

      part = build(:media, book: book, part_number: 2, parts_total: 3, title: nil)
      assert MediaSchema.display_title(part) == "The Way of Kings (Part 2 of 3)"

      override =
        build(:media,
          book: book,
          part_number: 2,
          parts_total: 3,
          title: "The Way of Kings (2 of 3)"
        )

      assert MediaSchema.display_title(override) == "The Way of Kings (2 of 3)"
    end

    test "get_media_description/1 includes the part label" do
      book = insert(:book, title: "The Way of Kings")
      media = insert(:media, book: book, part_number: 1, parts_total: 3)

      description = media.id |> Media.get_media!() |> Media.get_media_description()

      assert description =~ "The Way of Kings (Part 1 of 3)"
    end
  end

  describe "update_media/3" do
    test "allows updating a media's abridged value" do
      media = insert(:media, book: build(:book))
      original_value = media.abridged

      {:ok, updated_media} = Media.update_media(media, %{abridged: !original_value})

      assert updated_media.abridged == !original_value
    end

    test "allows updating a media's full_cast value" do
      media = insert(:media, book: build(:book))
      original_value = media.full_cast

      {:ok, updated_media} =
        Media.update_media(media, %{full_cast: !original_value})

      assert updated_media.full_cast == !original_value
    end

    test "allows updating a media's book" do
      %{id: book_id} = insert(:book)
      media = insert(:media, book: build(:book))

      {:ok, updated_media} = Media.update_media(media, %{book_id: book_id})

      assert updated_media.book_id == book_id
    end

    test "updates nested media narrators" do
      %{id: new_narrator_id} = insert(:narrator, person: build(:person))

      %{media_narrators: [existing_media_narrator | rest_media_narrators]} =
        media =
        insert(:media,
          book: build(:book),
          media_narrators: [
            build(:media_narrator, narrator: build(:narrator, person: build(:person)))
          ]
        )

      assert existing_media_narrator.narrator_id != new_narrator_id

      {:ok, updated_media} =
        Media.update_media(
          media,
          %{
            media_narrators: [
              %{id: existing_media_narrator.id, narrator_id: new_narrator_id}
              | Enum.map(rest_media_narrators, &%{id: &1.id})
            ]
          }
        )

      assert %{
               media_narrators: [
                 %{
                   narrator_id: ^new_narrator_id
                 }
                 | _rest
               ]
             } = updated_media
    end

    test "deletes nested media narrators" do
      %{media_narrators: media_narrators} =
        media =
        insert(:media,
          book: build(:book),
          media_narrators: [
            build(:media_narrator, narrator: build(:narrator, person: build(:person)))
          ]
        )

      {:ok, updated_media} =
        Media.update_media(
          media,
          %{
            media_narrators_drop: [0],
            media_narrators: media_narrators |> Enum.with_index(&{&2, %{id: &1.id}}) |> Map.new()
          }
        )

      assert %{media_narrators: new_media_narrators} = updated_media
      assert length(new_media_narrators) == length(media_narrators) - 1
    end

    test "replaces embedded chapters" do
      media = insert(:media, book: build(:book))

      new_chapters = [
        params_for(:chapter, time: 0, title: "Chapter 1"),
        params_for(:chapter, time: 300, title: "Chapter 2")
      ]

      {:ok, updated_media} = Media.update_media(media, %{chapters: new_chapters})

      assert length(updated_media.chapters) == 2
    end

    # The two narrators are named explicitly rather than by the faker: search
    # is fuzzy, so two randomly generated names occasionally resemble each
    # other enough that the *replaced* narrator still matches, and the test
    # fails on an unlucky seed for reasons that have nothing to do with it.
    test "updates the search index" do
      narrator_name = "Xylophone Quarkmonger"
      new_narrator_name = "Zeppelin Vortexbane"

      %{book_id: book_id} =
        media =
        :media
        |> insert(
          book: build(:book),
          media_narrators: [
            build(:media_narrator,
              narrator:
                build(:narrator,
                  name: narrator_name,
                  person: build(:person, name: narrator_name)
                )
            )
          ]
        )
        |> with_search_index()

      %{id: new_narrator_id} =
        insert(:narrator,
          name: new_narrator_name,
          person: build(:person, name: new_narrator_name)
        )

      assert [%{id: ^book_id}] = Ambry.Search.search(narrator_name)
      assert [] = Ambry.Search.search(new_narrator_name)

      {:ok, _updated_media} =
        Media.update_media(media, %{media_narrators: [%{narrator_id: new_narrator_id}]})

      assert [%{id: ^book_id}] = Ambry.Search.search(new_narrator_name)
      assert [] = Ambry.Search.search(narrator_name)
    end
  end

  describe "delete_media/1" do
    test "deletes a media" do
      media =
        insert(:media,
          book: build(:book)
        )

      {:ok, _media} = Media.delete_media(media)

      assert_raise Ecto.NoResultsError, fn ->
        Media.get_media!(media.id)
      end
    end

    test "updates the search index" do
      %{book_id: book_id, media_narrators: [%{narrator: %{name: narrator_name}} | _]} =
        media =
        :media
        |> insert(
          book: build(:book),
          media_narrators: [
            build(:media_narrator, narrator: build(:narrator, person: build(:person)))
          ]
        )
        |> with_search_index()

      assert [%{id: ^book_id}] = Ambry.Search.search(narrator_name)

      {:ok, _media} = Media.delete_media(media)

      assert [] = Ambry.Search.search(narrator_name)
    end

    test "deletes all related files from disk using a background job" do
      media =
        :media
        |> build(book: build(:book))
        |> with_source_files()
        |> with_image()
        |> insert()
        |> with_output_files()

      assert File.dir?(media.source_path)
      assert media.mp4_path |> Paths.web_to_disk() |> File.exists?()
      assert media.mpd_path |> Paths.web_to_disk() |> File.exists?()
      assert media.hls_path |> Paths.web_to_disk() |> File.exists?()
      assert media.hls_path |> Paths.hls_playlist_path() |> Paths.web_to_disk() |> File.exists?()
      assert media.image_path |> Paths.web_to_disk() |> File.exists?()

      {:ok, _media} = Media.delete_media(media)

      # Verify a job was scheduled to delete files
      assert_enqueued worker: DeleteFiles,
                      args: %{
                        "disk_paths" => [
                          Paths.web_to_disk(media.mpd_path),
                          Paths.web_to_disk(media.hls_path),
                          Paths.web_to_disk(media.mp4_path),
                          Paths.web_to_disk(Paths.hls_playlist_path(media.hls_path)),
                          Paths.web_to_disk(media.image_path)
                        ],
                        "folder_paths" => [media.source_path]
                      }
    end
  end

  describe "replace_media/2" do
    setup do
      media =
        :media
        |> build(book: build(:book))
        |> with_source_files()
        |> insert()
        |> with_output_files()

      media =
        Repo.update!(
          Ecto.Changeset.change(media, %{
            chapters: [
              %Ambry.Media.Media.Chapter{time: Decimal.new("0.0"), title: "Chapter 1"},
              %Ambry.Media.Media.Chapter{time: Decimal.new("60.0"), title: "Chapter 2"}
            ]
          })
        )

      playthrough =
        insert(:playthrough,
          media: media,
          user: build(:user),
          position: Decimal.new("123.4"),
          status: :in_progress
        )

      %{media: media, playthrough: playthrough}
    end

    test "updates source files, marks the media pending, and queues reprocessing", %{media: media} do
      new_source_path = Paths.source_media_disk_path(Ecto.UUID.generate())
      new_source_files = [valid_audio(:mp3)]

      {:ok, replaced} =
        Media.replace_media(media, %{
          source_path: new_source_path,
          source_files: new_source_files,
          processor: :auto
        })

      assert replaced.source_path == new_source_path
      assert replaced.source_files == new_source_files
      assert replaced.status == :pending

      assert_enqueued worker: Ambry.Media.RunProcessor,
                      args: %{"media_id" => media.id, "processor" => "auto"}
    end

    test "keeps the same streaming output URLs (overwrites in place)", %{media: media} do
      {:ok, replaced} =
        Media.replace_media(media, %{
          source_path: Paths.source_media_disk_path(Ecto.UUID.generate()),
          source_files: [valid_audio(:mp3)],
          processor: :auto
        })

      assert replaced.mp4_path == media.mp4_path
      assert replaced.mpd_path == media.mpd_path
      assert replaced.hls_path == media.hls_path
    end

    test "leaves chapters and listeners' saved positions untouched", %{
      media: media,
      playthrough: playthrough
    } do
      {:ok, replaced} =
        Media.replace_media(media, %{
          source_path: Paths.source_media_disk_path(Ecto.UUID.generate()),
          source_files: [valid_audio(:mp3)],
          processor: :auto
        })

      assert Enum.map(replaced.chapters, & &1.title) == ["Chapter 1", "Chapter 2"]

      reloaded_playthrough = Ambry.Playback.get_playthrough(playthrough.id)
      assert Decimal.equal?(reloaded_playthrough.position, Decimal.new("123.4"))
    end

    test "deletes the old source folder with a background job", %{media: media} do
      old_source_path = media.source_path

      {:ok, _replaced} =
        Media.replace_media(media, %{
          source_path: Paths.source_media_disk_path(Ecto.UUID.generate()),
          source_files: [valid_audio(:mp3)],
          processor: :auto
        })

      assert_enqueued worker: DeleteFiles,
                      args: %{"disk_paths" => [], "folder_paths" => [old_source_path]}
    end

    test "end-to-end: reprocessing regenerates the streaming files in place", %{media: media} do
      {:ok, replaced} =
        Media.replace_media(media, %{
          source_path: Paths.source_media_disk_path(Ecto.UUID.generate()),
          source_files: [valid_audio(:m4a)],
          processor: :auto
        })

      # Simulate the enqueued RunProcessor Oban job running.
      {:ok, processed} = Ambry.Media.Processor.run!(Media.get_media!(replaced.id))

      assert processed.status == :ready

      # Same URLs as before -> overwritten in place, not orphaned.
      assert processed.mp4_path == media.mp4_path
      assert processed.mpd_path == media.mpd_path
      assert processed.hls_path == media.hls_path

      # The streaming files actually exist on disk at those paths.
      assert processed.mp4_path |> Paths.web_to_disk() |> File.exists?()
      assert processed.hls_path |> Paths.web_to_disk() |> File.exists?()

      assert processed.hls_path
             |> Paths.hls_playlist_path()
             |> Paths.web_to_disk()
             |> File.exists?()

      # Duration was recomputed from the new audio by the processor.
      assert %Decimal{} = processed.duration
    end
  end

  describe "generate_thumbnails_async/1" do
    test "schedules a job to generate thumbnails if they're missing" do
      media =
        :media
        |> insert(book: build(:book))
        |> with_image()

      assert {:ok, %Oban.Job{}} = Media.generate_thumbnails_async(media)

      assert_enqueued worker: GenerateThumbnails,
                      args: %{"media_id" => media.id, "image_path" => media.image_path}
    end

    test "doesn't schedule a job if the thumbnails are already there" do
      media =
        :media
        |> insert(book: build(:book))
        |> with_image()
        |> with_thumbnails()

      assert {:ok, :noop} = Media.generate_thumbnails_async(media)
      refute_enqueued worker: GenerateThumbnails
    end
  end

  describe "change_media/1" do
    test "returns an unchanged changeset for a media" do
      media = insert(:media, book: build(:book))

      changeset = Media.change_media(media)

      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "change_media/2" do
    test "returns a changeset for a media" do
      media = insert(:media, book: build(:book))

      changeset = Media.change_media(media, %{abridged: !media.abridged})

      assert %Ecto.Changeset{valid?: true} = changeset
    end
  end

  describe "get_media_description/1" do
    test "returns a string describing the media" do
      author = insert(:author, person: build(:person), name: "Test Author")
      narrator = insert(:narrator, person: build(:person), name: "Test Narrator")

      book = insert(:book, book_authors: [build(:book_author, author: author)])

      media =
        insert(:media,
          book: book,
          media_narrators: [build(:media_narrator, narrator: narrator)]
        )

      loaded_media = Media.get_media!(media.id)

      description = Media.get_media_description(loaded_media)

      assert description =~ book.title
      assert description =~ author.name
      assert description =~ narrator.name
    end

    test "uses the display-title override when present" do
      book = insert(:book, title: "Philosopher's Stone")
      media = insert(:media, book: book, title: "Sorcerer's Stone")

      description = media.id |> Media.get_media!() |> Media.get_media_description()

      assert description =~ "Sorcerer's Stone"
      refute description =~ "Philosopher's Stone"
    end
  end
end
