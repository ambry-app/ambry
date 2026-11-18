defmodule Ambry.Media.EditionsTest do
  use Ambry.DataCase

  alias Ambry.Media.Editions
  alias Ambry.Media.Editions.Edition

  describe "from_media/2" do
    test "partitions media into editions: singles pass through, groups collapse" do
      book = insert(:book)
      group = insert(:recording_group)

      solo = insert(:media, book: book, status: :ready, published: ~D[2020-01-01])

      [part_two, part_one] =
        for n <- [2, 1] do
          insert(:media,
            book: book,
            part_number: n,
            recording_group: group,
            status: :ready,
            published: ~D[2021-01-01]
          )
        end

      assert [group_edition, single_edition] = Editions.from_media([solo, part_two, part_one])

      # newest first: the group's date is its first part's date (2021)
      assert %Edition{kind: :group, representative: %{id: rep_id}, media: parts} = group_edition
      assert rep_id == part_one.id
      assert Enum.map(parts, & &1.id) == [part_one.id, part_two.id]

      assert %Edition{kind: :single, representative: %{id: solo_id}} = single_edition
      assert solo_id == solo.id
    end

    test "only ready media count unless all_statuses" do
      book = insert(:book)
      group = insert(:recording_group)

      pending_first =
        insert(:media, book: book, part_number: 1, recording_group: group, status: :pending)

      ready_second =
        insert(:media, book: book, part_number: 2, recording_group: group, status: :ready)

      media_list = [pending_first, ready_second]

      # the group has one visible part → presents as a single edition,
      # represented by the first READY part
      assert [%Edition{kind: :single, representative: %{id: rep_id}}] =
               Editions.from_media(media_list)

      assert rep_id == ready_second.id

      # admin surfaces see everything: two parts, pending part represents
      assert [%Edition{kind: :group, representative: %{id: admin_rep_id}}] =
               Editions.from_media(media_list, all_statuses: true)

      assert admin_rep_id == pending_first.id
    end

    test "unlisted media are filtered like non-ready, unless all_statuses" do
      book = insert(:book)

      listed = insert(:media, book: book, status: :ready)

      unlisted =
        insert(:media, book: book, status: :ready, unlisted_at: DateTime.utc_now(:second))

      assert [%Edition{representative: %{id: rep_id}}] =
               Editions.from_media([unlisted, listed])

      assert rep_id == listed.id

      assert length(Editions.from_media([unlisted, listed], all_statuses: true)) == 2
    end

    test "a book with nothing ready yields no editions" do
      book = insert(:book)
      insert(:media, book: book, status: :pending)

      assert Editions.from_media([insert(:media, book: book, status: :processing)]) == []
    end

    test "editions order newest first, nulls last, id tiebreak" do
      book = insert(:book)

      old = insert(:media, book: book, status: :ready, published: ~D[2010-01-01])
      new = insert(:media, book: book, status: :ready, published: ~D[2022-01-01])
      undated_a = insert(:media, book: book, status: :ready, published: nil)
      undated_b = insert(:media, book: book, status: :ready, published: nil)

      editions = Editions.from_media([undated_a, old, new, undated_b])

      assert Enum.map(editions, & &1.representative.id) ==
               [new.id, old.id, undated_b.id, undated_a.id]
    end
  end

  describe "from_representative/1" do
    test "a grouped listing row becomes a group edition; a lone row a single" do
      book = insert(:book)
      group = insert(:recording_group)

      parts =
        for n <- 1..2 do
          insert(:media, book: book, part_number: n, recording_group: group, status: :ready)
        end

      [part_one, _part_two] = parts
      loaded = Ambry.Repo.preload(part_one, recording_group: :media)

      assert %Edition{kind: :group, representative: %{id: rep_id}} =
               Editions.from_representative(loaded)

      assert rep_id == part_one.id

      solo = insert(:media, book: book, status: :ready)

      assert %Edition{kind: :single} =
               solo |> Ambry.Repo.preload(:recording_group) |> Editions.from_representative()
    end
  end
end
