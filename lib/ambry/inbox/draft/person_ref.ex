defmodule Ambry.Inbox.Draft.PersonRef do
  @moduledoc """
  One human behind a credit: either somebody already in the library, or
  somebody to create with it.

  Two or more of these on one credit is a shared pen name — that is the whole
  of the composite-author case as far as an import is concerned. There is no
  separate composite mode, because "how many people" is a number, not a kind.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    # set = an existing Person; nil = create one with this name
    field :person_id, :id
    field :name, :string

    # What a *new* person will be created with. 3b's promise is that the
    # operator never has to leave the inbox to finish a leaf entity, and a
    # person with no face is unfinished — every credit imported without these
    # was a trip to the person form afterwards.
    field :description, :string
    field :image_url, :string
    # which provider the photo and bio came from, for 1d provenance
    field :image_source, :string
    field :description_source, :string
  end

  # Deliberately permissive: a draft has to be *storable* while it's still
  # being made up, or the operator couldn't add a second person and then name
  # them. Whether it's finished is `complete?/1`'s job, reported through
  # `Draft.unresolved/1` — validation gates saving, the invariant gates
  # importing, and conflating the two makes the form unusable.
  @doc false
  def changeset(person_ref, attrs) do
    cast(person_ref, attrs, [
      :person_id,
      :name,
      :description,
      :image_url,
      :image_source,
      :description_source
    ])
  end

  @doc "Whether this reference actually says who it means."
  def complete?(%__MODULE__{person_id: id}) when not is_nil(id), do: true
  def complete?(%__MODULE__{name: name}) when is_binary(name), do: String.trim(name) != ""
  def complete?(%__MODULE__{}), do: false

  @doc "Whether this reference means 'create somebody new'."
  def new?(%__MODULE__{person_id: nil}), do: true
  def new?(%__MODULE__{}), do: false
end
