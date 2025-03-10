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

      %{id: new_narrator_id, name: new_narrator_name} = insert(:narrator, person: build(:person))

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

  describe "get_recent_player_states/1" do
    test "returns the first 10 player_states sorted by inserted_at" do
      user = insert(:user)

      insert_list(11, :player_state,
        status: :in_progress,
        user_id: user.id,
        media: fn ->
          insert(:media,
            book: fn -> build(:book) end,
            duration: Decimal.new(3600)
          )
        end
      )

      {returned_player_states, has_more?} = Media.get_recent_player_states(user.id)

      assert has_more?
      assert length(returned_player_states) == 10
    end
  end

  describe "get_recent_player_states/2" do
    test "accepts an offset" do
      user = insert(:user)

      insert_list(11, :player_state,
        status: :in_progress,
        user_id: user.id,
        media: fn ->
          insert(:media,
            book: build(:book),
            duration: Decimal.new(3600)
          )
        end
      )

      {returned_player_states, has_more?} = Media.get_recent_player_states(user.id, 10)

      refute has_more?
      assert length(returned_player_states) == 1
    end
  end

  describe "get_recent_player_states/3" do
    test "accepts a limit" do
      user = insert(:user)

      insert_list(6, :player_state,
        status: :in_progress,
        user_id: user.id,
        media: fn ->
          insert(:media,
            book: build(:book),
            duration: Decimal.new(3600)
          )
        end
      )

      {returned_player_states, has_more?} = Media.get_recent_player_states(user.id, 0, 5)

      assert has_more?
      assert length(returned_player_states) == 5
    end
  end

  describe "load_player_state!/2" do
    test "creates a new player state and sets it as the user's loaded player state" do
      user = insert(:user)

      %{id: media_id} =
        insert(:media,
          book: build(:book),
          duration: Decimal.new(3600)
        )

      %{id: player_state_id} = Media.load_player_state!(user, media_id)

      assert %{loaded_player_state_id: ^player_state_id} = Ambry.Repo.reload!(user)
    end

    test "gets an existing player state and sets it as the user's loaded player state" do
      user = insert(:user)

      media =
        insert(:media,
          book: build(:book),
          duration: Decimal.new(3600)
        )

      %{id: player_state_id} = insert(:player_state, user_id: user.id, media: media)

      %{id: ^player_state_id} = Media.load_player_state!(user, media.id)

      assert %{loaded_player_state_id: ^player_state_id} = Ambry.Repo.reload!(user)
    end
  end

  describe "get_player_state!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Media.get_player_state!(-1)
      end
    end

    test "returns the player state with the given id" do
      user = insert(:user)

      media =
        insert(:media,
          book: build(:book),
          duration: Decimal.new(3600)
        )

      %{id: id} = insert(:player_state, user_id: user.id, media: media)

      assert %Media.PlayerState{id: ^id} = Media.get_player_state!(id)
    end
  end

  describe "get_player_state!/2" do
    test "creates a new player state if one doesn't yet exist" do
      %{id: user_id} = insert(:user)

      %{id: media_id} =
        insert(:media,
          book: build(:book),
          duration: Decimal.new(3600)
        )

      player_state = Media.get_player_state!(user_id, media_id)

      assert %{user_id: ^user_id, media_id: ^media_id} = player_state
    end

    test "returns an existing player state if one already exists" do
      %{id: user_id} = insert(:user)

      media =
        insert(:media,
          book: build(:book),
          duration: Decimal.new(3600)
        )

      %{id: player_state_id} = insert(:player_state, user_id: user_id, media: media)

      player_state = Media.get_player_state!(user_id, media.id)

      assert %{id: ^player_state_id} = player_state
    end
  end

  describe "update_player_state/2" do
    test "updates position and playback rate" do
      %{id: user_id} = insert(:user)

      media =
        insert(:media,
          book: build(:book),
          duration: Decimal.new(3600)
        )

      player_state = insert(:player_state, user_id: user_id, media: media)

      new_position = Decimal.new(300)
      new_playback_rate = Decimal.new("1.25")

      {:ok, updated_player_state} =
        Media.update_player_state(player_state, %{
          position: new_position,
          playback_rate: new_playback_rate
        })

      assert %{position: ^new_position, playback_rate: ^new_playback_rate} = updated_player_state
    end

    test "status goes from `:not_started` to `:in_progress` to `:finished`" do
      %{id: user_id} = insert(:user)

      media =
        insert(:media,
          book: build(:book),
          duration: Decimal.new(3600)
        )

      player_state =
        insert(:player_state, user_id: user_id, position: Decimal.new(0), media: media)

      assert %{status: :not_started} = player_state

      new_position = Decimal.new(59)

      assert {:ok, %{status: :not_started} = player_state} =
               Media.update_player_state(player_state, %{position: new_position})

      new_position = Decimal.new(60)

      assert {:ok, %{status: :in_progress} = player_state} =
               Media.update_player_state(player_state, %{position: new_position})

      new_position = Decimal.sub(player_state.media.duration, Decimal.new(120))

      assert {:ok, %{status: :in_progress} = player_state} =
               Media.update_player_state(player_state, %{position: new_position})

      new_position = Decimal.sub(player_state.media.duration, Decimal.new(119))

      assert {:ok, %{status: :finished}} =
               Media.update_player_state(player_state, %{position: new_position})
    end
  end

  describe "update_player_state/4" do
    test "sets position and playback rate if player state doesn't yet exist" do
      %{id: user_id} = insert(:user)

      %{id: media_id} =
        insert(:media,
          book: build(:book),
          duration: Decimal.new(3600)
        )

      position = Decimal.new(300)
      playback_rate = Decimal.new("1.25")

      {:ok, player_state} = Media.update_player_state(user_id, media_id, position, playback_rate)

      assert %{position: ^position, playback_rate: ^playback_rate} = player_state
    end

    test "updates position and playback rate if player state already exists" do
      %{id: user_id} = insert(:user)

      media =
        insert(:media,
          book: build(:book),
          duration: Decimal.new(3600)
        )

      %{id: player_state_id} = insert(:player_state, user_id: user_id, media: media)

      new_position = Decimal.new(300)
      new_playback_rate = Decimal.new("1.25")

      {:ok, updated_player_state} =
        Media.update_player_state(user_id, media.id, new_position, new_playback_rate)

      assert %{id: ^player_state_id, position: ^new_position, playback_rate: ^new_playback_rate} =
               updated_player_state
    end

    test "sets status to `:not_started`" do
      %{id: user_id} = insert(:user)

      %{id: media_id} =
        insert(:media,
          book: build(:book),
          duration: Decimal.new(3600)
        )

      assert {:ok, %{status: :not_started}} =
               Media.update_player_state(user_id, media_id, Decimal.new(0), Decimal.new(1))
    end

    test "sets status to `:in_progress`" do
      %{id: user_id} = insert(:user)

      %{id: media_id} =
        insert(:media,
          book: build(:book),
          duration: Decimal.new(3600)
        )

      assert {:ok, %{status: :in_progress}} =
               Media.update_player_state(user_id, media_id, Decimal.new(60), Decimal.new(1))
    end

    test "sets status to `:finished`" do
      %{id: user_id} = insert(:user)

      media =
        %{id: media_id} =
        insert(:media,
          book: build(:book),
          duration: Decimal.new(3600)
        )

      position = Decimal.sub(media.duration, Decimal.new(119))

      assert {:ok, %{status: :finished}} =
               Media.update_player_state(user_id, media_id, position, Decimal.new(1))
    end
  end

  describe "list_bookmarks/2" do
    test "returns all bookmarks for the given user and media" do
      user = insert(:user)
      media = insert(:media, book: build(:book))
      insert_list(10, :bookmark, user_id: user.id, media_id: media.id)

      bookmarks = Media.list_bookmarks(user.id, media.id)

      assert length(bookmarks) == 10
    end
  end

  describe "list_bookmarks/4" do
    test "accepts a limit and an offset" do
      user = insert(:user)
      media = insert(:media, book: build(:book))
      insert_list(10, :bookmark, user_id: user.id, media_id: media.id)

      {bookmarks, has_more?} = Media.list_bookmarks(user.id, media.id, 0, 5)

      assert has_more?
      assert length(bookmarks) == 5
    end
  end

  describe "get_bookmark!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Media.get_bookmark!(-1)
      end
    end

    test "returns the bookmark with the given id" do
      user = insert(:user)
      media = insert(:media, book: build(:book))
      %{id: id} = insert(:bookmark, user_id: user.id, media_id: media.id)

      assert %Media.Bookmark{id: ^id} = Media.get_bookmark!(id)
    end
  end

  describe "create_bookmark/1" do
    test "requires media, user and position to be set" do
      {:error, changeset} = Media.create_bookmark(%{})

      assert %{
               user_id: ["can't be blank"],
               media_id: ["can't be blank"],
               position: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "creates a bookmark when given valid attributes" do
      user = insert(:user)
      media = insert(:media, book: build(:book))
      params = params_for(:bookmark, user_id: user.id, media_id: media.id)

      assert {:ok, _bookmark} = Media.create_bookmark(params)
    end
  end

  describe "update_bookmark/2" do
    test "updates a bookmark" do
      user = insert(:user)
      media = insert(:media, book: build(:book))
      bookmark = insert(:bookmark, user_id: user.id, media_id: media.id)

      %{position: new_position, label: new_label} = params_for(:bookmark)

      {:ok, updated_bookmark} =
        Media.update_bookmark(bookmark, %{position: new_position, label: new_label})

      assert %{position: ^new_position, label: ^new_label} = updated_bookmark
    end
  end

  describe "delete_bookmark/1" do
    test "deletes a bookmark" do
      user = insert(:user)
      media = insert(:media, book: build(:book))
      bookmark = insert(:bookmark, user_id: user.id, media_id: media.id)

      {:ok, _deleted_bookmark} = Media.delete_bookmark(bookmark)

      assert_raise Ecto.NoResultsError, fn ->
        Media.get_bookmark!(bookmark.id)
      end
    end
  end

  describe "change_bookmark/1" do
    test "returns an unchanged changeset for a bookmark" do
      user = insert(:user)
      media = insert(:media, book: build(:book))
      bookmark = insert(:bookmark, user_id: user.id, media_id: media.id)

      changeset = Media.change_bookmark(bookmark)

      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "change_bookmark/2" do
    test "returns a changeset for a bookmark" do
      user = insert(:user)
      media = insert(:media, book: build(:book))
      bookmark = insert(:bookmark, user_id: user.id, media_id: media.id)

      %{position: new_position, label: new_label} = params_for(:bookmark)

      changeset = Media.change_bookmark(bookmark, %{position: new_position, label: new_label})

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
  end
end
