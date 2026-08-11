defmodule Ambry.ProvenanceTest do
  use Ambry.DataCase

  alias Ambry.Books
  alias Ambry.Media
  alias Ambry.People
  alias Ambry.Provenance

  describe "recording provenance through context create/update" do
    test "changed fields without a source hint are manual edits — locked" do
      {:ok, person} = People.create_person(%{name: "Ty Franck"})

      assert %{"source" => "manual", "locked" => true, "at" => at} =
               Provenance.entry(person, :name)

      assert {:ok, _at, 0} = DateTime.from_iso8601(at)
      assert Provenance.locked?(person, :name)
    end

    test "changed fields with a provider hint record that source — unlocked" do
      {:ok, person} =
        People.create_person(
          %{name: "Ty Franck", description: "Half of James S.A. Corey."},
          provenance: %{"description" => "provider:hardcover"}
        )

      # accepted suggestion: provider source, refresh may update it later
      assert %{"source" => "provider:hardcover", "locked" => false} =
               Provenance.entry(person, :description)

      # the name had no hint: typed by the operator, locked
      assert %{"source" => "manual", "locked" => true} = Provenance.entry(person, :name)
    end

    test "unchanged fields keep their existing provenance" do
      {:ok, person} =
        People.create_person(%{name: "Somebody"}, provenance: %{"name" => "provider:audnexus"})

      {:ok, updated} = People.update_person(person, %{description: "New bio."})

      assert %{"source" => "provider:audnexus", "locked" => false} =
               Provenance.entry(updated, :name)

      assert %{"source" => "manual", "locked" => true} = Provenance.entry(updated, :description)
    end

    test "an accepted value records its source even when it equals the stored value" do
      # re-importing the same name must still flip legacy/manual → provider:
      # acceptance is a statement about where the current value comes from
      {:ok, person} = People.create_person(%{name: "Arthur Conan Doyle"})

      {:ok, updated} =
        People.update_person(person, %{name: "Arthur Conan Doyle"},
          provenance: %{"name" => "provider:wikidata"}
        )

      assert %{"source" => "provider:wikidata", "locked" => false} =
               Provenance.entry(updated, :name)
    end

    test "a hint for a field that stays empty records nothing" do
      {:ok, person} =
        People.create_person(%{name: "Somebody"},
          provenance: %{"description" => "provider:hardcover"}
        )

      assert Provenance.entry(person, :description) == nil
    end

    test "a manual edit over a provider value re-records it as manual and locks it" do
      {:ok, person} =
        People.create_person(
          %{name: "Somebody", description: "Provider bio."},
          provenance: %{"description" => "provider:hardcover"}
        )

      {:ok, updated} = People.update_person(person, %{description: "Curated bio."})

      assert %{"source" => "manual", "locked" => true} = Provenance.entry(updated, :description)
    end

    test "books and media track their provider-fillable scalars" do
      author = insert(:author)

      {:ok, book} =
        Books.create_book(
          %{
            title: "Leviathan Wakes",
            published: ~D[2011-06-15],
            published_format: :full,
            book_authors: [%{author_id: author.id}]
          },
          provenance: %{
            "title" => "provider:rreading_glasses",
            "published" => "provider:rreading_glasses",
            "published_format" => "provider:rreading_glasses"
          }
        )

      assert %{"source" => "provider:rreading_glasses", "locked" => false} =
               Provenance.entry(book, :title)

      media = insert(:media, book: book)

      {:ok, updated_media} =
        Media.update_media(
          media,
          %{publisher: "Recorded Books", description: "From Audible."},
          provenance: %{"description" => "provider:audible"}
        )

      assert %{"source" => "manual", "locked" => true} =
               Provenance.entry(updated_media, :publisher)

      assert %{"source" => "provider:audible", "locked" => false} =
               Provenance.entry(updated_media, :description)
    end

    test "structural lists are tracked too — manual when hand-edited, provider when hinted" do
      {:ok, book} =
        Books.create_book(%{
          title: "Some Book",
          published: ~D[2020-01-01],
          book_authors: [%{author_id: insert(:author).id}]
        })

      # a hand-built list is a manual edit like any other
      assert %{"source" => "manual"} = Provenance.entry(book, :book_authors)

      {:ok, hinted} =
        Books.create_book(
          %{
            title: "Other Book",
            published: ~D[2020-01-01],
            book_authors: [%{author_id: insert(:author).id}]
          },
          provenance: %{"book_authors" => "provider:rreading_glasses"}
        )

      assert %{"source" => "provider:rreading_glasses", "locked" => false} =
               Provenance.entry(hinted, :book_authors)
    end

    test "untracked fields never get provenance entries" do
      media = insert(:media, book: build(:book))
      {:ok, updated} = Media.update_media(media, %{notes: "operator note"})

      assert Provenance.entry(updated, :notes) == nil
    end

    test "a source carrying its record ref stores the ref" do
      {:ok, book} =
        Books.create_book(
          %{title: "Reffed Book", published: ~D[2020-01-01]},
          provenance: %{
            "title" => %{"source" => "provider:rreading_glasses", "record" => "76027608"}
          }
        )

      assert %{
               "source" => "provider:rreading_glasses",
               "record" => "76027608",
               "locked" => false
             } = Provenance.entry(book, :title)
    end
  end

  describe "reject_locked/2 — the gate for automated writers" do
    test "drops locked fields from proposed attrs, string or atom keys" do
      {:ok, person} =
        People.create_person(
          %{name: "Somebody", description: "Provider bio."},
          provenance: %{"description" => "provider:hardcover"}
        )

      # name is manual+locked, description is provider+unlocked
      proposed = %{"name" => "Refreshed Name", "description" => "Refreshed bio."}
      assert Provenance.reject_locked(person, proposed) == %{"description" => "Refreshed bio."}

      proposed_atoms = %{name: "Refreshed Name", description: "Refreshed bio."}
      assert Provenance.reject_locked(person, proposed_atoms) == %{description: "Refreshed bio."}
    end

    test "passes everything through for records with no provenance" do
      person = insert(:person)
      proposed = %{"name" => "New Name"}
      assert Provenance.reject_locked(person, proposed) == proposed
    end
  end
end
