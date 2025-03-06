defmodule Ambry.PeopleTest do
  use Ambry.DataCase

  alias Ambry.Paths
  alias Ambry.People
  alias Ambry.PubSub.AsyncBroadcast
  alias Ambry.Search.IndexFactory
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
    test "accepts a 'search' filter that searches by person name" do
      [_, _, %{id: id, name: name}, _, _] = insert_list(5, :person)

      {[matched], has_more?} = People.list_people(0, 10, %{search: name})

      refute has_more?
      assert matched.id == id
    end

    test "accepts an 'is_author' filter" do
      %{person: %{id: id}} = insert(:author)

      {[%{id: ^id}], false} = People.list_people(0, 10, %{is_author: true})
      {[], false} = People.list_people(0, 10, %{is_author: false})
    end

    test "accepts an 'is_narrator' filter" do
      %{person: %{id: id}} = insert(:narrator)

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
      params = Map.put(person_params, :authors, [author_params])

      assert {:ok, person} = People.create_person(params)

      assert %{name: ^person_name, authors: [%{name: ^author_name}]} = person
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
      %{web_path: web_path} = valid_image()
      params = params_for(:person, image_path: web_path)

      assert {:ok, person} = People.create_person(params)

      assert_enqueued worker: GenerateThumbnails,
                      args: %{"person_id" => person.id, "image_path" => web_path}
    end

    test "schedules a job to broadcast a PubSub message" do
      params = params_for(:person, image_path: nil)

      assert {:ok, person} = People.create_person(params)

      assert_enqueued worker: AsyncBroadcast,
                      args: %{
                        "module" => "Elixir.Ambry.PubSub.PersonCreated",
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
      new_name = Faker.Person.name()

      {:ok, updated_person} = People.update_person(person, %{name: new_name})

      assert updated_person.name == new_name
    end

    test "updates nested authors" do
      %{id: author_id, person: person} = insert(:author)
      new_name = Faker.Person.name()

      {:ok, updated_person} =
        People.update_person(person, %{
          name: new_name,
          authors: [%{id: author_id, name: new_name}]
        })

      assert %{
               name: ^new_name,
               authors: [
                 %{
                   name: ^new_name
                 }
               ]
             } = updated_person
    end

    test "deletes nested authors" do
      %{id: author_id, person: person} = insert(:author)

      {:ok, updated_person} =
        People.update_person(person, %{authors_drop: [0], authors: %{0 => %{id: author_id}}})

      assert %{authors: []} = updated_person
    end

    @tag :skip
    test "cannot delete a nested author if they have authored a book" do
      %{book_authors: [%{author: %{id: author_id, person: person}} | _]} = insert(:book)

      {:error, changeset} =
        People.update_person(person, %{authors_drop: [0], authors: %{0 => %{id: author_id}}})

      assert %{
               authors: [
                 %{
                   id: [
                     "This author is in use by one or more books. You must first remove them as an author from any associated books."
                   ]
                 }
               ]
             } = errors_on(changeset)
    end

    test "updates nested narrators" do
      %{id: narrator_id, person: person} = insert(:narrator)
      new_name = Faker.Person.name()

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
      %{id: narrator_id, person: person} = insert(:narrator)

      {:ok, updated_person} =
        People.update_person(person, %{narrators_drop: [0], narrators: %{0 => %{id: narrator_id}}})

      assert %{narrators: []} = updated_person
    end

    @tag :skip
    test "cannot delete a nested narrator if they have narrated media" do
      %{media_narrators: [%{narrator: %{id: narrator_id, person: person}} | _]} = insert(:media)

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
      %{id: person_id, name: original_name} = person = insert(:person)
      new_name = Faker.Person.name()

      IndexFactory.insert_index!(person)

      assert [%{id: ^person_id}] = Ambry.Search.search(original_name)
      assert [] = Ambry.Search.search(new_name)

      {:ok, _updated_person} = People.update_person(person, %{name: new_name})

      assert [] = Ambry.Search.search(original_name)
      assert [%{id: ^person_id}] = Ambry.Search.search(new_name)
    end

    test "schedules a job to delete files that are no longer needed" do
      %{web_path: web_path1} = valid_image()
      %{web_path: web_path2} = valid_image()
      person = insert(:person, image_path: web_path1)

      image_disk_path = Paths.web_to_disk(person.image_path)

      {:ok, _updated_person} = People.update_person(person, %{image_path: web_path2})

      assert_enqueued worker: DeleteFiles, args: %{"disk_paths" => [image_disk_path]}
    end

    test "schedules a job to generate thumbnails if a valid image_path is given" do
      %{web_path: web_path} = valid_image()
      person = insert(:person, image_path: nil)

      assert {:ok, person} = People.update_person(person, %{image_path: web_path})

      assert_enqueued worker: GenerateThumbnails,
                      args: %{"person_id" => person.id, "image_path" => web_path}
    end

    test "schedules a job to broadcast a PubSub message" do
      person = insert(:person)

      assert {:ok, _updated_person} = People.update_person(person, %{})

      assert_enqueued worker: AsyncBroadcast,
                      args: %{
                        "module" => "Elixir.Ambry.PubSub.PersonUpdated",
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
      person = %{id: person_id, name: name} = insert(:person)

      IndexFactory.insert_index!(person)

      assert [%{id: ^person_id}] = Ambry.Search.search(name)

      {:ok, _person} = People.delete_person(person)

      assert [] = Ambry.Search.search(name)
    end

    test "schedules a job to delete files that are no longer needed" do
      %{web_path: web_path} = valid_image()
      person = insert(:person, image_path: web_path)

      image_disk_path = Paths.web_to_disk(person.image_path)

      {:ok, _person} = People.delete_person(person)

      assert_enqueued worker: DeleteFiles, args: %{"disk_paths" => [image_disk_path]}
    end

    test "schedules a job to broadcast a PubSub message" do
      person = insert(:person)

      assert {:ok, _person} = People.delete_person(person)

      assert_enqueued worker: AsyncBroadcast,
                      args: %{
                        "module" => "Elixir.Ambry.PubSub.PersonDeleted",
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
      %{book_authors: [%{author: %{person: person}} | _]} = insert(:book)

      {:error, :has_authored_books} = People.delete_person(person)
    end

    test "cannot delete a person if they have narrated media" do
      %{media_narrators: [%{narrator: %{person: person}} | _]} = insert(:media)

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

      changeset = People.change_person(person, %{name: Faker.Person.name()})

      assert %Ecto.Changeset{valid?: true} = changeset
    end
  end

  describe "generate_thumbnails_async/1" do
    test "schedules a job to generate thumbnails if they're missing" do
      %{web_path: web_path} = valid_image()

      person = insert(:person, image_path: web_path)

      assert {:ok, %Oban.Job{}} = People.generate_thumbnails_async(person)

      assert_enqueued worker: GenerateThumbnails,
                      args: %{"person_id" => person.id, "image_path" => web_path}
    end

    test "doesn't schedule a job if the thumbnails are already there" do
      %{web_path: web_path} = valid_image()
      person = insert(:person, image_path: web_path)
      {:ok, person} = People.update_person_thumbnails!(person.id, web_path)

      assert {:ok, :noop} = People.generate_thumbnails_async(person)
      refute_enqueued worker: GenerateThumbnails
    end
  end

  describe "update_person_thumbnails!/2" do
    test "generates thumbnails and updates the person" do
      %{web_path: web_path} = valid_image()

      person = insert(:person, image_path: web_path)

      assert person.thumbnails == nil
      assert {:ok, person} = People.update_person_thumbnails!(person.id, web_path)
      assert person.thumbnails != nil

      assert File.exists?(Paths.web_to_disk(person.thumbnails.extra_small))
      assert File.exists?(Paths.web_to_disk(person.thumbnails.small))
      assert File.exists?(Paths.web_to_disk(person.thumbnails.medium))
      assert File.exists?(Paths.web_to_disk(person.thumbnails.large))
      assert File.exists?(Paths.web_to_disk(person.thumbnails.extra_large))
    end

    test "doesn't update the person if the image given doesn't match what's saved and deletes any files created" do
      %{web_path: web_path1} = valid_image()
      %{web_path: web_path2} = valid_image()

      person = insert(:person, image_path: web_path1)

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
      %{id: id} = insert(:narrator)

      assert %People.Narrator{id: ^id} = People.get_narrator!(id)
    end
  end

  describe "narrators_for_select/0" do
    test "returns all narrator names and ids only" do
      insert_list(3, :narrator)

      list = People.narrators_for_select()

      assert [
               {_, _},
               {_, _},
               {_, _}
             ] = list
    end
  end

  describe "get_author!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        People.get_author!(-1)
      end
    end

    test "returns the author with the given id" do
      %{id: id} = insert(:author)

      assert %People.Author{id: ^id} = People.get_author!(id)
    end
  end

  describe "authors_for_select/0" do
    test "returns all author names and ids only" do
      insert_list(3, :author)

      list = People.authors_for_select()

      assert [
               {_, _},
               {_, _},
               {_, _}
             ] = list
    end
  end
end
