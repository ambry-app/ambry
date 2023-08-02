defmodule Ambry.PeopleTest do
  use Ambry.DataCase

  import ExUnit.CaptureLog

  alias Ambry.People

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
      %{name: name} = params = params_for(:person)

      assert {:ok, person} = People.create_person(params)

      assert %{name: ^name} = person
    end

    test "can create nested authors" do
      %{name: person_name} = person_params = params_for(:person)
      %{name: author_name} = author_params = params_for(:author)
      params = Map.put(person_params, :authors, [author_params])

      assert {:ok, person} = People.create_person(params)

      assert %{name: ^person_name, authors: [%{name: ^author_name}]} = person
    end

    test "can create nested narrators" do
      %{name: person_name} = person_params = params_for(:person)
      %{name: narrator_name} = narrator_params = params_for(:narrator)
      params = Map.put(person_params, :narrators, [narrator_params])

      assert {:ok, person} = People.create_person(params)

      assert %{name: ^person_name, narrators: [%{name: ^narrator_name}]} = person
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

      {:ok, updated_person} = People.update_person(person, %{authors_drop: [0], authors: %{0 => %{id: author_id}}})

      assert %{authors: []} = updated_person
    end

    @tag :skip
    test "cannot delete a nested author if they have authored a book" do
      %{book_authors: [%{author: %{id: author_id, person: person}} | _]} = insert(:book)

      {:error, changeset} = People.update_person(person, %{authors_drop: [0], authors: %{0 => %{id: author_id}}})

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

      {:error, changeset} = People.update_person(person, %{narrators_drop: [0], narrators: %{0 => %{id: narrator_id}}})

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
  end

  describe "delete_person/1" do
    test "deletes a person" do
      person = insert(:person, image_path: nil)

      :ok = People.delete_person(person)

      assert_raise Ecto.NoResultsError, fn ->
        People.get_person!(person.id)
      end
    end

    test "deletes the image file from disk used by a person" do
      person = insert(:person)
      create_fake_files!(person)

      assert File.exists?(Ambry.Paths.web_to_disk(person.image_path))

      :ok = People.delete_person(person)

      refute File.exists?(Ambry.Paths.web_to_disk(person.image_path))
    end

    test "does not delete the image file from disk if the same image is used by multiple people" do
      person = insert(:person)
      create_fake_files!(person)
      person2 = insert(:person, image_path: person.image_path)

      assert File.exists?(Ambry.Paths.web_to_disk(person.image_path))

      fun = fn ->
        :ok = People.delete_person(person2)
      end

      assert capture_log(fun) =~ "Not deleting file because it's still in use"

      assert File.exists?(Ambry.Paths.web_to_disk(person.image_path))
    end

    test "warns if the image file from disk used by a person does not exist" do
      person = insert(:person)

      fun = fn ->
        :ok = People.delete_person(person)
      end

      assert capture_log(fun) =~ "Couldn't delete file (enoent)"
    end

    test "cannot delete a person if they have authored a book" do
      %{title: book_title, book_authors: [%{author: %{person: person}} | _]} = insert(:book)

      {:error, {:has_authored_books, [^book_title]}} = People.delete_person(person)
    end

    test "cannot delete a person if they have narrated media" do
      %{book: %{title: book_title}, media_narrators: [%{narrator: %{person: person}} | _]} = insert(:media)

      {:error, {:has_narrated_books, [^book_title]}} = People.delete_person(person)
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

  describe "get_person_with_books!/1" do
    test "gets a person and all of their authored books" do
      %{book_authors: [%{author: %{person: %{id: person_id}}} | _]} = insert(:book)

      person = People.get_person_with_books!(person_id)

      assert %People.Person{
               authors: [
                 %{
                   books: [%{}]
                 }
               ]
             } = person
    end

    test "gets a person and all of their narrated books" do
      %{media_narrators: [%{narrator: %{person: %{id: person_id}}} | _]} = insert(:media)

      person = People.get_person_with_books!(person_id)

      assert %People.Person{
               narrators: [
                 %{
                   books: [%{}]
                 }
               ]
             } = person
    end
  end
end
