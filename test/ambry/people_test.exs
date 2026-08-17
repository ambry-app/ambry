defmodule Ambry.PeopleTest do
  use Ambry.DataCase

  alias Ambry.Fake
  alias Ambry.Paths
  alias Ambry.People
  alias Ambry.PubSub.BroadcastAsync
  alias Ambry.Thumbnails.GenerateThumbnails
  alias Ambry.Utils.DeleteFiles

  describe "list_people/0" do
    test "returns the first 10 people sorted by name" do
      insert_list(11, :person)

      {returned_people, has_more?} = People.list_people()

      assert has_more?
      assert length(returned_people) == 10
    end
  end

  describe "list_people/1" do
    test "accepts an offset" do
      insert_list(11, :person)

      {returned_people, has_more?} = People.list_people(10)

      refute has_more?
      assert length(returned_people) == 1
    end
  end

  describe "list_people/2" do
    test "accepts a limit" do
      insert_list(6, :person)

      {returned_people, has_more?} = People.list_people(0, 5)

      assert has_more?
      assert length(returned_people) == 5
    end
  end

  describe "list_people/3" do
    # Named explicitly rather than via the faker: the search is trigram-based,
    # so two randomly generated names that happen to look alike both match and
    # the test fails for reasons that have nothing to do with the search.
    test "accepts a 'search' filter that searches by person name" do
      for name <- ["Wodehouse", "Zamyatin", "Kobayashi"], do: insert(:person, name: name)
      %{id: id} = insert(:person, name: "Quetzalcoatl")

      {[matched], has_more?} = People.list_people(0, 10, %{search: "Quetzalcoatl"})

      refute has_more?
      assert matched.id == id
    end

    test "accepts an 'is_author' filter" do
      %{id: id} = insert(:person, authors: [build(:author)])

      {[%{id: ^id}], false} = People.list_people(0, 10, %{is_author: true})
      {[], false} = People.list_people(0, 10, %{is_author: false})
    end

    test "accepts an 'is_narrator' filter" do
      %{id: id} = insert(:person, narrators: [build(:narrator)])

      {[%{id: ^id}], false} = People.list_people(0, 10, %{is_narrator: true})
      {[], false} = People.list_people(0, 10, %{is_narrator: false})
    end
  end

  describe "list_people/4" do
    test "allows sorting results by any field on the schema" do
      %{id: person1_id} = insert(:person, name: "Apple")
      %{id: person2_id} = insert(:person, name: "Banana")
      %{id: person3_id} = insert(:person, name: "Carrot")

      {people, false} = People.list_people(0, 10, %{}, :name)

      assert [
               %{id: ^person1_id},
               %{id: ^person2_id},
               %{id: ^person3_id}
             ] = people

      {people, false} = People.list_people(0, 10, %{}, {:desc, :name})

      assert [
               %{id: ^person3_id},
               %{id: ^person2_id},
               %{id: ^person1_id}
             ] = people
    end
  end

  describe "count_people/0" do
    test "returns the number of people in the database" do
      insert_list(3, :person)

      assert %{authors: 0, narrators: 0, total: 3} = People.count_people()
    end
  end

  describe "get_person!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        People.get_person!(-1)
      end
    end

    test "returns the person with the given id" do
      %{id: id} = insert(:person)

      assert %People.Person{id: ^id} = People.get_person!(id)
    end
  end

  describe "create_person/1" do
    test "requires name to be set" do
      {:error, changeset} = People.create_person(%{})

      assert %{
               name: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates name when given" do
      {:error, changeset} = People.create_person(%{name: ""})

      assert %{
               name: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "creates a person when given valid attributes" do
      %{name: name} = params = params_for(:person, image_path: nil)

      assert {:ok, person} = People.create_person(params)

      assert %{name: ^name} = person
    end

    test "can create nested authors" do
      %{name: person_name} = person_params = params_for(:person, image_path: nil)
      %{name: author_name} = author_params = params_for(:author)
      params = Map.put(person_params, :author_people, [%{author: author_params}])

      assert {:ok, person} = People.create_person(params)

      assert %{name: ^person_name, author_people: [%{author: %{name: ^author_name}}]} = person
    end

    test "can create nested narrators" do
      %{name: person_name} = person_params = params_for(:person, image_path: nil)
      %{name: narrator_name} = narrator_params = params_for(:narrator)
      params = Map.put(person_params, :narrators, [narrator_params])

      assert {:ok, person} = People.create_person(params)

      assert %{name: ^person_name, narrators: [%{name: ^narrator_name}]} = person
    end

    test "updates the search index" do
      %{name: person_name} = params = params_for(:person, image_path: nil)

      assert [] = Ambry.Search.search(person_name)

      assert {:ok, %{id: person_id}} = People.create_person(params)

      assert [%{id: ^person_id}] = Ambry.Search.search(person_name)
    end

    test "schedules a job to generate thumbnails if a valid image_path is given" do
      %{web_path: web_path} = valid_image(:person)
      params = params_for(:person, image_path: web_path)

      assert {:ok, person} = People.create_person(params)

      assert_enqueued worker: GenerateThumbnails,
                      args: %{"person_id" => person.id, "image_path" => web_path}
    end

    test "schedules a job to broadcast a PubSub message" do
      params = params_for(:person, image_path: nil)

      assert {:ok, person} = People.create_person(params)

      assert_enqueued worker: BroadcastAsync,
                      args: %{
                        "module" => "Elixir.Ambry.People.PubSub.PersonCreated",
                        "message" => %{
                          "broadcast_topics" => ["person-created:*"],
                          "id" => person.id
                        }
                      }
    end
  end

  describe "update_person/2" do
    test "updates a person" do
      person = insert(:person)
      new_name = Fake.full_name()

      {:ok, updated_person} = People.update_person(person, %{name: new_name})

      assert updated_person.name == new_name
    end

    test "updates nested authors" do
      person = insert(:person, authors: [build(:author)])
      [%{id: join_id, author: %{id: author_id}}] = person.author_people
      new_name = Fake.full_name()

      {:ok, updated_person} =
        People.update_person(person, %{
          name: new_name,
          author_people: [%{id: join_id, author: %{id: author_id, name: new_name}}]
        })

      assert %{
               name: ^new_name,
               author_people: [
                 %{
                   author: %{name: ^new_name}
                 }
               ]
             } = updated_person
    end

    test "links an existing author to another person (composite pen name)" do
      author = insert(:author, person: build(:person))
      other_person = insert(:person)

      {:ok, updated_person} =
        People.update_person(other_person, %{author_people: [%{author_id: author.id}]})

      assert %{author_people: [%{author_id: author_id}]} = updated_person
      assert author_id == author.id

      assert %{people: people} = People.get_author!(author.id)
      assert length(people) == 2
    end

    test "unlinking a shared author keeps the author" do
      author = insert(:author, person: build(:person))
      other_person = insert(:person)

      {:ok, other_person} =
        People.update_person(other_person, %{author_people: [%{author_id: author.id}]})

      [%{id: join_id}] = other_person.author_people

      {:ok, updated_person} =
        People.update_person(other_person, %{
          author_people_drop: [0],
          author_people: %{0 => %{id: join_id}}
        })

      assert %{author_people: []} = updated_person
      assert %{people: [_person]} = People.get_author!(author.id)
    end

    test "deletes nested authors" do
      person = insert(:person, authors: [build(:author)])
      [%{id: join_id, author: %{id: author_id}}] = person.author_people

      {:ok, updated_person} =
        People.update_person(person, %{
          author_people_drop: [0],
          author_people: %{0 => %{id: join_id}}
        })

      assert %{author_people: []} = updated_person

      # the author lost its last person link, so it was deleted entirely
      assert_raise Ecto.NoResultsError, fn -> People.get_author!(author_id) end
    end

    test "cannot delete a nested author if they have authored a book" do
      book =
        insert(:book,
          book_authors: [build(:book_author, author: build(:author, person: build(:person)))]
        )

      %{book_authors: [%{author: %{id: author_id, author_people: [%{person: person}]}}]} = book

      %{author_people: [%{id: join_id}]} = person = People.get_person!(person.id)

      {:error, changeset} =
        People.update_person(person, %{
          author_people_drop: [0],
          author_people: %{0 => %{id: join_id}}
        })

      assert %{author_people: [message]} = errors_on(changeset)
      assert message =~ "This author is in use by one or more books."

      # the author and its link both survive
      assert %{author_people: [%{author_id: ^author_id}]} = People.get_person!(person.id)
    end

    test "updates nested narrators" do
      person = insert(:person, narrators: [build(:narrator)])
      [%{id: narrator_id}] = person.narrators
      new_name = Fake.full_name()

      {:ok, updated_person} =
        People.update_person(person, %{
          name: new_name,
          narrators: [%{id: narrator_id, name: new_name}]
        })

      assert %{
               name: ^new_name,
               narrators: [
                 %{
                   name: ^new_name
                 }
               ]
             } = updated_person
    end

    test "deletes nested narrators" do
      person = insert(:person, narrators: [build(:narrator)])
      [%{id: narrator_id}] = person.narrators

      {:ok, updated_person} =
        People.update_person(person, %{narrators_drop: [0], narrators: %{0 => %{id: narrator_id}}})

      assert %{narrators: []} = updated_person
    end

    @tag :skip
    test "cannot delete a nested narrator if they have narrated media" do
      media =
        insert(:media,
          media_narrators: [
            build(:media_narrator, narrator: build(:narrator, person: build(:person)))
          ]
        )

      %{media_narrators: [%{narrator: %{id: narrator_id, person: person}}]} = media

      {:error, changeset} =
        People.update_person(person, %{narrators_drop: [0], narrators: %{0 => %{id: narrator_id}}})

      assert %{
               narrators: [
                 %{
                   delete: [
                     "This narrator is in use by one or more media. You must first remove them as a narrator from any associated media."
                   ]
                 }
               ]
             } = errors_on(changeset)
    end

    test "updates the search index" do
      %{id: person_id, name: original_name} = person = :person |> insert() |> with_search_index()
      new_name = Fake.full_name()

      assert [%{id: ^person_id}] = Ambry.Search.search(original_name)
      assert [] = Ambry.Search.search(new_name)

      {:ok, _updated_person} = People.update_person(person, %{name: new_name})

      assert [] = Ambry.Search.search(original_name)
      assert [%{id: ^person_id}] = Ambry.Search.search(new_name)
    end

    test "schedules a job to delete files that are no longer needed" do
      person = :person |> build() |> with_image() |> insert()
      %{web_path: web_path2} = valid_image(:person)

      image_disk_path = Paths.web_to_disk(person.image_path)

      {:ok, _updated_person} = People.update_person(person, %{image_path: web_path2})

      assert_enqueued worker: DeleteFiles, args: %{"disk_paths" => [image_disk_path]}
    end

    test "schedules a job to generate thumbnails if a valid image_path is given" do
      %{web_path: web_path} = valid_image(:person)
      person = insert(:person, image_path: nil)

      assert {:ok, person} = People.update_person(person, %{image_path: web_path})

      assert_enqueued worker: GenerateThumbnails,
                      args: %{"person_id" => person.id, "image_path" => web_path}
    end

    test "schedules a job to broadcast a PubSub message" do
      person = insert(:person)

      assert {:ok, _updated_person} = People.update_person(person, %{})

      assert_enqueued worker: BroadcastAsync,
                      args: %{
                        "module" => "Elixir.Ambry.People.PubSub.PersonUpdated",
                        "message" => %{
                          "broadcast_topics" => [
                            "person-updated:#{person.id}",
                            "person-updated:*"
                          ],
                          "id" => person.id
                        }
                      }
    end
  end

  describe "delete_person/1" do
    test "deletes a person" do
      person = insert(:person, image_path: nil)

      {:ok, _person} = People.delete_person(person)

      assert_raise Ecto.NoResultsError, fn ->
        People.get_person!(person.id)
      end
    end

    test "updates the search index" do
      person = %{id: person_id, name: name} = :person |> insert() |> with_search_index()

      assert [%{id: ^person_id}] = Ambry.Search.search(name)

      {:ok, _person} = People.delete_person(person)

      assert [] = Ambry.Search.search(name)
    end

    test "schedules a job to delete files that are no longer needed" do
      person = :person |> build() |> with_image() |> insert()

      image_disk_path = Paths.web_to_disk(person.image_path)

      {:ok, _person} = People.delete_person(person)

      assert_enqueued worker: DeleteFiles, args: %{"disk_paths" => [image_disk_path]}
    end

    test "schedules a job to broadcast a PubSub message" do
      person = insert(:person)

      assert {:ok, _person} = People.delete_person(person)

      assert_enqueued worker: BroadcastAsync,
                      args: %{
                        "module" => "Elixir.Ambry.People.PubSub.PersonDeleted",
                        "message" => %{
                          "broadcast_topics" => [
                            "person-deleted:#{person.id}",
                            "person-deleted:*"
                          ],
                          "id" => person.id
                        }
                      }
    end

    test "cannot delete a person if they have authored a book" do
      person =
        insert(:person,
          authors: [
            build(:author,
              book_authors: [build(:book_author, book: build(:book))]
            )
          ]
        )

      {:error, :has_authored_books} = People.delete_person(person)
    end

    test "cannot delete a person if they have narrated media" do
      person =
        insert(:person,
          narrators: [
            build(:narrator,
              media_narrators: [build(:media_narrator, media: build(:media, book: build(:book)))]
            )
          ]
        )

      {:error, :has_narrated_media} = People.delete_person(person)
    end
  end

  describe "change_person/1" do
    test "returns an unchanged changeset for a person" do
      person = insert(:person)

      changeset = People.change_person(person)

      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "change_person/2" do
    test "returns a changeset for a person" do
      person = insert(:person)

      changeset = People.change_person(person, %{name: Fake.full_name()})

      assert %Ecto.Changeset{valid?: true} = changeset
    end
  end

  describe "generate_thumbnails_async/1" do
    test "schedules a job to generate thumbnails if they're missing" do
      person = :person |> build() |> with_image() |> insert()
      web_path = person.image_path

      assert {:ok, %Oban.Job{}} = People.generate_thumbnails_async(person)

      assert_enqueued worker: GenerateThumbnails,
                      args: %{"person_id" => person.id, "image_path" => web_path}
    end

    test "doesn't schedule a job if the thumbnails are already there" do
      person = :person |> build() |> with_thumbnails() |> insert()

      assert {:ok, :noop} = People.generate_thumbnails_async(person)
      refute_enqueued worker: GenerateThumbnails
    end
  end

  describe "update_person_thumbnails!/2" do
    test "generates thumbnails and updates the person" do
      person = :person |> build() |> with_image() |> insert()

      assert person.thumbnails == nil
      assert {:ok, person} = People.update_person_thumbnails!(person.id, person.image_path)
      assert person.thumbnails != nil

      assert File.exists?(Paths.web_to_disk(person.thumbnails.extra_small))
      assert File.exists?(Paths.web_to_disk(person.thumbnails.small))
      assert File.exists?(Paths.web_to_disk(person.thumbnails.medium))
      assert File.exists?(Paths.web_to_disk(person.thumbnails.large))
      assert File.exists?(Paths.web_to_disk(person.thumbnails.extra_large))
    end

    test "doesn't update the person if the image given doesn't match what's saved and deletes any files created" do
      person = :person |> build() |> with_image() |> insert()
      %{web_path: web_path2} = valid_image(:person)

      assert person.thumbnails == nil

      assert {:error, changeset} = People.update_person_thumbnails!(person.id, web_path2)

      thumbnails =
        changeset |> Ecto.Changeset.get_change(:thumbnails) |> Ecto.Changeset.apply_changes()

      refute File.exists?(Paths.web_to_disk(thumbnails.extra_small))
      refute File.exists?(Paths.web_to_disk(thumbnails.small))
      refute File.exists?(Paths.web_to_disk(thumbnails.medium))
      refute File.exists?(Paths.web_to_disk(thumbnails.large))
      refute File.exists?(Paths.web_to_disk(thumbnails.extra_large))
    end
  end

  describe "get_narrator!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        People.get_narrator!(-1)
      end
    end

    test "returns the narrator with the given id" do
      person = insert(:person, narrators: [build(:narrator)])
      [%{id: id}] = person.narrators

      assert %People.Narrator{id: ^id} = People.get_narrator!(id)
    end
  end

  describe "search_narrators/2" do
    test "returns rich options: name, portrait, backing person when it adds something" do
      insert(:person, narrators: build_list(3, :narrator))

      assert [
               %{id: _, label: _, image: _, detail: _},
               %{id: _, label: _, image: _, detail: _},
               %{id: _, label: _, image: _, detail: _}
             ] = People.search_narrators("", 10)
    end

    test "matches on the name and stops at the limit" do
      insert(:person, narrators: [build(:narrator, name: "Michael Kramer")])
      insert(:person, narrators: [build(:narrator, name: "Kate Reading")])

      assert [%{label: "Michael Kramer"}] = People.search_narrators("kramer", 10)
      assert length(People.search_narrators("", 1)) == 1
    end

    # The library's "Patricia Rodríguez" and a file's "Patricia Rodriguez" are
    # one narrator; a picker that couldn't find her by the second spelling is
    # how a second person of the same name gets created.
    test "folds accents" do
      insert(:person, narrators: [build(:narrator, name: "Patricia Rodríguez")])

      assert [%{label: "Patricia Rodríguez"}] = People.search_narrators("Rodriguez", 10)
    end
  end

  describe "narrator_option/1" do
    test "names one narrator, and nothing for one that is gone" do
      person = insert(:person, narrators: [build(:narrator)])
      [narrator] = person.narrators

      assert %{id: id, label: label} = People.narrator_option(narrator.id)
      assert {id, label} == {narrator.id, narrator.name}

      refute People.narrator_option(nil)
    end
  end

  describe "get_author!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        People.get_author!(-1)
      end
    end

    test "returns the author with the given id" do
      person = insert(:person, authors: [build(:author)])
      [%{author: %{id: id}}] = person.author_people

      assert %People.Author{id: ^id} = People.get_author!(id)
    end
  end

  describe "search_authors/2" do
    test "returns rich options: name, portrait, backing people when they add something" do
      insert(:person, authors: build_list(3, :author))

      assert [
               %{id: _, label: _, image: _, detail: _},
               %{id: _, label: _, image: _, detail: _},
               %{id: _, label: _, image: _, detail: _}
             ] = People.search_authors("", 10)
    end

    test "matches on the name" do
      insert(:person, authors: [build(:author, name: "Brandon Sanderson")])
      insert(:person, authors: [build(:author, name: "Andy Weir")])

      assert [%{label: "Brandon Sanderson"}] = People.search_authors("sanderson", 10)
    end
  end

  describe "author_option/1" do
    # The `detail` is who is really behind the identity, which is what the
    # credit row prints beside a linked pen name — it used to come from a map
    # of every author in the library.
    test "names one author, and says who is behind a pen name" do
      person =
        insert(:person, name: "Jason Pargin", authors: [build(:author, name: "David Wong")])

      [%{author: author}] = person.author_people

      assert %{id: id, label: "David Wong", detail: "Jason Pargin"} =
               People.author_option(author.id)

      assert id == author.id
      refute People.author_option(nil)
    end
  end

  describe "search_people/2" do
    test "matches on the name" do
      insert(:person, name: "Brandon Sanderson")
      insert(:person, name: "Andy Weir")

      assert [%{label: "Brandon Sanderson"}] = People.search_people("sanderson", 10)
    end
  end

  describe "person_option/1" do
    test "names one person, and nothing for one that is gone" do
      person = insert(:person)

      assert %{id: id, label: label} = People.person_option(person.id)
      assert {id, label} == {person.id, person.name}

      refute People.person_option(nil)
    end
  end
end
