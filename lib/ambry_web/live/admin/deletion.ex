defmodule AmbryWeb.Admin.Deletion do
  @moduledoc """
  The words a delete uses, shared by the two surfaces that offer one: the
  record's row in its list, and its form's sticky footer.

  A reason atom with no wording here is a crash rather than a shrug: a
  refusal that doesn't say why is the thing these messages exist to prevent.
  """

  @doc """
  Turns a delete's result into `{:ok, message}` or `{:error, message}`.

  The verb is the caller's: deleting a book destroys it, while removing a
  source or library root only stops Ambry looking there.
  """
  def outcome(result, name, verb \\ :deleted)

  def outcome({:ok, _record}, name, verb), do: {:ok, worked(verb, name)}

  def outcome({:error, reason}, name, _verb), do: {:error, refusal(reason, name)}

  @doc """
  The success message on its own, for contexts that answer a bare `:ok`.
  """
  def deleted(name), do: worked(:deleted, name)

  defp worked(:deleted, name), do: "Deleted #{name}."
  defp worked(:detached, name), do: "Removed #{name}. Its files were left alone."

  defp refusal(:has_media, name), do: "#{name} has audiobooks in the library. Delete those first."

  defp refusal(:has_authored_books, name),
    do: "#{name} has authored books in the library. Delete those first."

  defp refusal(:has_narrated_media, name),
    do: "#{name} has narrated audiobooks in the library. Delete those first."

  defp refusal({:referenced, %{inbox_items: items}}, name),
    do:
      "#{name} still has #{items} inbox item#{plural(items)} resolving through it. " <>
        "Import or remove them first."

  # A root can be held by loose tracks with no recording of their own, so
  # name whichever count is non-zero.
  defp refusal({:referenced, %{media: media, media_tracks: tracks}}, name),
    do:
      "#{name} still holds #{held(media, tracks)}. " <>
        "The library serves them from there, so the root has to outlive them."

  defp held(media, tracks) do
    [
      media > 0 && "#{media} recording#{plural(media)}",
      tracks > 0 && "#{tracks} audio file#{plural(tracks)}"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" and ")
  end

  defp plural(1), do: ""
  defp plural(_count), do: "s"
end
