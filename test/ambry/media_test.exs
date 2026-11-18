defmodule Ambry.MediaTest do
  use Ambry.DataCase

  alias Ambry.Books.Book
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

      # The narrator's own person is already indexed — everything is, now that
      # the index maintains itself — so the question is only ever about the
      # book.
      assert is_nil(searched_book(narrator_name))

      params =
        :media
        |> params_for(
          book_id: book_id,
          media_narrators: [%{narrator_id: narrator_id}]
        )
        |> Map.take([:abridged, :full_cast, :source_path, :book_id, :media_narrators])

      assert {:ok, _media} = Media.create_media(params)

      assert %{id: ^book_id} = searched_book(narrator_name)
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
    test "creates media in a group with a part number" do
      %{id: book_id} = insert(:book)

      {:ok, group} =
        Media.create_recording_group(%{name: "Season One", parts_total: 3, book_id: book_id})

      params =
        :media
        |> params_for(book_id: book_id, part_number: 1, recording_group_id: group.id)
        |> Map.take([
          :abridged,
          :full_cast,
          :source_path,
          :book_id,
          :part_number,
          :recording_group_id
        ])

      assert {:ok, media} = Media.create_media(params)

      media = Media.get_media!(media.id)
      assert %{part_number: 1, recording_group: %{name: "Season One", parts_total: 3}} = media

      assert [%{label: "Season One", detail: "1 of 3 parts"}] =
               Media.recording_group_options(book_id)
    end

    test "a part number requires a group" do
      %{id: book_id} = insert(:book)

      params =
        :media
        |> params_for(book_id: book_id, part_number: 1)
        |> Map.take([:abridged, :full_cast, :source_path, :book_id, :part_number])

      assert {:error, changeset} = Media.create_media(params)
      assert %{part_number: ["requires a group"]} = errors_on(changeset)
    end

    test "leaving the group clears the part number and sweeps the orphaned set" do
      %{id: book_id} = insert(:book)
      {:ok, group} = Media.create_recording_group(%{name: "Season One", book_id: book_id})

      media =
        insert(:media, book_id: book_id, part_number: 1, recording_group_id: group.id)

      # the form posts "" when the drop-down is cleared
      {:ok, updated} =
        Media.update_media(Media.get_media!(media.id), %{"recording_group_id" => ""})

      assert updated.recording_group_id == nil
      assert updated.part_number == nil
      assert [] = Media.recording_group_options(book_id)
      assert Ambry.Repo.aggregate(Ambry.Media.RecordingGroup, :count) == 0
    end

    test "an unrelated media save leaves an empty admin-created group alone" do
      %{id: book_id} = insert(:book)
      {:ok, group} = Media.create_recording_group(%{name: "Awaiting Parts", book_id: book_id})

      media = insert(:media, book_id: book_id)
      {:ok, _updated} = Media.update_media(Media.get_media!(media.id), %{abridged: true})

      assert Ambry.Repo.get!(Ambry.Media.RecordingGroup, group.id)
    end

    test "validates the part number against the loaded group's total" do
      %{id: book_id} = book = insert(:book)
      group = insert(:recording_group, parts_total: 2, book: book)
      media = insert(:media, book_id: book_id, part_number: 1, recording_group: group)

      assert {:error, changeset} =
               Media.update_media(Media.get_media!(media.id), %{part_number: 3})

      assert %{part_number: ["can't be greater than the total number of parts"]} =
               errors_on(changeset)
    end

    test "part_label/1 and display_title/1" do
      alias Ambry.Media.Media, as: MediaSchema
      alias Ambry.Media.RecordingGroup

      # flat-row shape: part_number/parts_total/part_word columns
      assert MediaSchema.part_label(%{part_number: nil, parts_total: nil}) == nil

      assert MediaSchema.part_label(%{part_number: 2, parts_total: nil, part_word: nil}) ==
               "Part 2"

      assert MediaSchema.part_label(%{part_number: 2, parts_total: 3, part_word: nil}) ==
               "Part 2 of 3"

      book = build(:book, title: "The Way of Kings")
      open_set = build(:recording_group, parts_total: nil)
      set_of_three = build(:recording_group, parts_total: 3)

      plain = build(:media, book: book, part_number: nil, title: nil)
      assert MediaSchema.display_title(plain) == "The Way of Kings"

      lone_part = build(:media, book: book, part_number: 2, recording_group: open_set, title: nil)
      assert MediaSchema.display_title(lone_part) == "The Way of Kings (Part 2)"

      part = build(:media, book: book, part_number: 2, recording_group: set_of_three, title: nil)
      assert MediaSchema.display_title(part) == "The Way of Kings (Part 2 of 3)"

      # an explicitly passed group wins over the loaded one
      assert MediaSchema.part_label(part, %RecordingGroup{parts_total: 5}) == "Part 2 of 5"

      override =
        build(:media,
          book: book,
          part_number: 2,
          recording_group: set_of_three,
          title: "The Way of Kings (2 of 3)"
        )

      assert MediaSchema.display_title(override) == "The Way of Kings (2 of 3)"
    end

    test "get_media_description/1 includes the part label" do
      book = insert(:book, title: "The Way of Kings")
      group = insert(:recording_group, parts_total: 3)
      media = insert(:media, book: book, part_number: 1, recording_group: group)

      description = media.id |> Media.get_media!() |> Media.get_media_description()

      assert description =~ "The Way of Kings (Part 1 of 3)"
    end
  end

  describe "the recording group form" do
    test "creates a group with members attached" do
      book = insert(:book)
      media_one = insert(:media, book: book)
      media_two = insert(:media, book: book)

      assert {:ok, group} =
               Media.create_recording_group_from_form(%{
                 "name" => "GraphicAudio",
                 "book_id" => to_string(book.id),
                 "parts_total" => "2",
                 "members" => %{
                   "0" => %{"media_id" => to_string(media_one.id), "part_number" => "1"},
                   "1" => %{"media_id" => to_string(media_two.id), "part_number" => "2"}
                 }
               })

      assert %{name: "GraphicAudio", parts_total: 2} = group

      loaded = Media.get_recording_group!(group.id)

      assert Enum.map(loaded.media, &{&1.id, &1.part_number}) ==
               [{media_one.id, 1}, {media_two.id, 2}]
    end

    test "updates facts and diffs members — a removed row detaches and loses its number" do
      book = insert(:book)
      group = insert(:recording_group, name: "Before", book: book)
      keep = insert(:media, book: book, part_number: 1, recording_group: group)
      drop = insert(:media, book: book, part_number: 2, recording_group: group)
      add = insert(:media, book: book)

      group = Media.get_recording_group!(group.id)

      assert {:ok, _group} =
               Media.update_recording_group_from_form(group, %{
                 "name" => "After",
                 "members" => %{
                   "0" => %{"media_id" => to_string(keep.id), "part_number" => "1"},
                   "1" => %{"media_id" => to_string(add.id), "part_number" => "3"}
                 }
               })

      assert Media.get_recording_group!(group.id).name == "After"

      assert Media.get_media!(keep.id).part_number == 1
      assert Media.get_media!(add.id).recording_group_id == group.id
      assert Media.get_media!(add.id).part_number == 3

      dropped = Media.get_media!(drop.id)
      assert dropped.recording_group_id == nil
      assert dropped.part_number == nil
    end

    test "pulling a recording from another group sweeps the one it left" do
      book = insert(:book)
      old_group = insert(:recording_group, name: "Old Set", book: book)
      media = insert(:media, book: book, part_number: 1, recording_group: old_group)

      {:ok, new_group} = Media.create_recording_group(%{name: "New Set", book_id: book.id})
      new_group = Media.get_recording_group!(new_group.id)

      assert {:ok, _} =
               Media.update_recording_group_from_form(new_group, %{
                 "name" => "New Set",
                 "members" => %{
                   "0" => %{"media_id" => to_string(media.id), "part_number" => "1"}
                 }
               })

      assert Media.get_media!(media.id).recording_group_id == new_group.id
      refute Ambry.Repo.get(Ambry.Media.RecordingGroup, old_group.id)
    end

    test "refuses a duplicate member, a part past the total, and a blank name" do
      book = insert(:book)
      media = insert(:media, book: book)

      assert {:error, changeset} =
               Media.create_recording_group_from_form(%{
                 "name" => "Set",
                 "book_id" => to_string(book.id),
                 "members" => %{
                   "0" => %{"media_id" => to_string(media.id), "part_number" => "1"},
                   "1" => %{"media_id" => to_string(media.id), "part_number" => "2"}
                 }
               })

      # the error lands on the offending row, where the form points at it
      assert [%{}, %{media_id: ["is already in the set"]}] = errors_on(changeset).members

      assert {:error, changeset} =
               Media.create_recording_group_from_form(%{
                 "name" => "Set",
                 "book_id" => to_string(book.id),
                 "parts_total" => "2",
                 "members" => %{
                   "0" => %{"media_id" => to_string(media.id), "part_number" => "5"}
                 }
               })

      assert [%{part_number: ["is past the total"]}] = errors_on(changeset).members

      assert {:error, changeset} = Media.create_recording_group_from_form(%{"name" => ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
      assert Media.count_recording_groups() == 0
    end
  end

  describe "recording group CRUD" do
    test "create_recording_group/1 requires a name and a book, and allows an empty group" do
      assert {:error, changeset} = Media.create_recording_group(%{})
      assert %{name: ["can't be blank"], book_id: ["can't be blank"]} = errors_on(changeset)

      %{id: book_id} = insert(:book)

      assert {:ok, group} =
               Media.create_recording_group(%{
                 name: "Season One",
                 parts_total: 3,
                 book_id: book_id
               })

      assert %{name: "Season One", parts_total: 3, media: []} =
               Media.get_recording_group!(group.id)
    end

    test "a book can't hold two sets by one name" do
      %{id: book_id} = insert(:book)
      {:ok, _first} = Media.create_recording_group(%{name: "Graphic Audio", book_id: book_id})

      assert {:error, changeset} =
               Media.create_recording_group(%{name: "Graphic Audio", book_id: book_id})

      assert %{book_id: ["this book already has a set by that name"]} = errors_on(changeset)

      # the same name on another book is the whole point of local names
      %{id: other_book_id} = insert(:book)

      assert {:ok, _second} =
               Media.create_recording_group(%{name: "Graphic Audio", book_id: other_book_id})
    end

    test "a media can't join another book's set" do
      group = insert(:recording_group)
      media = insert(:media, book: build(:book))

      assert {:error, changeset} =
               Media.update_media(Media.get_media!(media.id), %{recording_group_id: group.id})

      assert %{recording_group_id: ["belongs to a different book"]} = errors_on(changeset)
    end

    test "update_recording_group/2 changes set-level facts" do
      %{id: book_id} = insert(:book)
      {:ok, group} = Media.create_recording_group(%{name: "Season One", book_id: book_id})

      assert {:ok, updated} =
               Media.update_recording_group(group, %{parts_total: 2, part_word: "episode"})

      assert %{parts_total: 2, part_word: "episode"} = updated

      assert {:error, changeset} = Media.update_recording_group(group, %{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "delete_recording_group/1 detaches members and clears their part numbers" do
      %{id: book_id} = insert(:book)
      group = insert(:recording_group, parts_total: 2)
      part_one = insert(:media, book_id: book_id, part_number: 1, recording_group: group)
      part_two = insert(:media, book_id: book_id, part_number: 2, recording_group: group)

      assert {:ok, _deleted} = Media.delete_recording_group(group)

      for id <- [part_one.id, part_two.id] do
        media = Media.get_media!(id)
        assert media.recording_group_id == nil
        assert media.part_number == nil
      end
    end

    test "list_recording_groups/4 paginates and filters by name" do
      insert(:recording_group, name: "The Audio Immersion Experience")
      insert(:recording_group, name: "GraphicAudio Set")

      {all, false} = Media.list_recording_groups()
      assert length(all) == 2

      {filtered, false} = Media.list_recording_groups(0, 10, %{search: "immersion"})
      assert [%{name: "The Audio Immersion Experience"}] = filtered

      assert Media.count_recording_groups() == 2
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

      %{id: new_narrator_id} =
        insert(:narrator,
          name: new_narrator_name,
          person: build(:person, name: new_narrator_name)
        )

      assert %{id: ^book_id} = searched_book(narrator_name)
      assert is_nil(searched_book(new_narrator_name))

      {:ok, _updated_media} =
        Media.update_media(media, %{media_narrators: [%{narrator_id: new_narrator_id}]})

      assert %{id: ^book_id} = searched_book(new_narrator_name)
      assert is_nil(searched_book(narrator_name))
    end
  end

  describe "unlist_media/1 and relist_media/1" do
    test "unlisting stamps unlisted_at once and relisting clears it" do
      media = insert(:media, book: build(:book))

      {:ok, unlisted} = Media.unlist_media(media)
      assert %DateTime{} = unlisted.unlisted_at

      {:ok, still_unlisted} = Media.unlist_media(unlisted)
      assert still_unlisted.unlisted_at == unlisted.unlisted_at

      {:ok, relisted} = Media.relist_media(still_unlisted)
      assert relisted.unlisted_at == nil

      {:ok, still_listed} = Media.relist_media(relisted)
      assert still_listed.unlisted_at == nil
    end

    test "an unlisted media keeps its processing status" do
      media = insert(:media, book: build(:book), status: :error)

      {:ok, unlisted} = Media.unlist_media(media)
      assert unlisted.status == :error

      {:ok, relisted} = Media.relist_media(unlisted)
      assert relisted.status == :error
    end
  end

  describe "browsing hides unlisted media" do
    test "get_recent_media/2 skips unlisted media" do
      %{id: listed_id} = insert(:media, book: build(:book), status: :ready)

      insert(:media,
        book: build(:book),
        status: :ready,
        unlisted_at: DateTime.utc_now(:second)
      )

      {media, false} = Media.get_recent_media()

      assert Enum.map(media, & &1.id) == [listed_id]
    end

    test "an unlisted part cannot represent its set" do
      book = insert(:book)
      group = insert(:recording_group, book: book)

      insert(:media,
        book: book,
        recording_group: group,
        part_number: 1,
        status: :ready,
        unlisted_at: DateTime.utc_now(:second)
      )

      %{id: part_two_id} =
        insert(:media, book: book, recording_group: group, part_number: 2, status: :ready)

      {media, false} = Media.get_recent_media()

      assert Enum.map(media, & &1.id) == [part_two_id]
    end

    test "get_narrated_media/3 skips unlisted media" do
      narrator = insert(:narrator, person: build(:person))

      %{id: listed_id} =
        insert(:media,
          book: build(:book),
          status: :ready,
          media_narrators: [build(:media_narrator, narrator: narrator)]
        )

      insert(:media,
        book: build(:book),
        status: :ready,
        unlisted_at: DateTime.utc_now(:second),
        media_narrators: [build(:media_narrator, narrator: narrator)]
      )

      {media, false} = Media.get_narrated_media(narrator)

      assert Enum.map(media, & &1.id) == [listed_id]
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

      assert %{id: ^book_id} = searched_book(narrator_name)

      {:ok, _media} = Media.delete_media(media)

      assert is_nil(searched_book(narrator_name))
    end

    test "deletes all related files from disk using a background job" do
      media =
        :media
        |> build(book: build(:book))
        |> with_source_files()
        |> with_image()
        |> insert()
        |> with_output_files()

      source_disk_path = Media.Media.source_path(media)

      assert File.dir?(source_disk_path)
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
                        "folder_paths" => [source_disk_path]
                      }
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

      assert description == "#{book.title} by #{author.name} read by #{narrator.name}"
    end

    test "uses the display-title override when present" do
      book = insert(:book, title: "Philosopher's Stone")
      media = insert(:media, book: book, title: "Sorcerer's Stone")

      description = media.id |> Media.get_media!() |> Media.get_media_description()

      assert description =~ "Sorcerer's Stone"
      refute description =~ "Philosopher's Stone"
    end
  end

  describe "problem_counts/0" do
    test "an empty library has no problems" do
      assert %{missing: 0, errored: 0, streaming_only: 0, awaiting_switch: 0} =
               Media.problem_counts()
    end

    test "counts recordings whose files couldn't be read" do
      media(%{missing_since: DateTime.utc_now(:second)})
      media(%{})

      assert %{missing: 1} = Media.problem_counts()
    end

    test "counts recordings that failed processing" do
      media(%{status: :error})

      assert %{errored: 1} = Media.problem_counts()
    end

    test "a recording with no tracks can only be streamed" do
      media(%{}, tracks: false)
      media(%{}, tracks: true)

      assert %{streaming_only: 1} = Media.problem_counts()
    end

    test "awaiting the switch is exactly what publishing would release" do
      # Direct-play and pending: held back by the operator switch.
      media(%{status: :pending}, tracks: true)
      # Pending with legacy artifacts is waiting on transcoding, not the
      # switch, and publishing it would hand clients an unplayable recording.
      media(%{status: :pending, mp4_path: "/uploads/media/x.mp4"}, tracks: true)
      # Missing files, so publishing it would be worse than leaving it.
      media(%{status: :pending, missing_since: DateTime.utc_now(:second)}, tracks: true)
      # Already published.
      media(%{status: :ready}, tracks: true)

      assert %{awaiting_switch: 1} = Media.problem_counts()
    end
  end

  defp media(attrs, opts \\ []) do
    media = build(:media, Map.to_list(Map.put_new(attrs, :book, build(:book))))
    media = if Keyword.get(opts, :tracks, false), do: with_tracks(media), else: media

    insert(media)
  end

  # Whether a narrator's name reaches the *book*. Their person always matches
  # it — a person is indexed the moment they exist — so a bare result count
  # would be asking a different question.
  defp searched_book(query), do: Ambry.Search.find_first(query, Book)
end
