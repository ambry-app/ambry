defmodule AmbrySchema.Media do
  @moduledoc false

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  import Absinthe.Resolution.Helpers, only: [dataloader: 1, dataloader: 2]

  alias AmbrySchema.Resolvers

  enum :media_processing_status do
    value :pending
    value :processing
    value :error
    value :ready
  end

  object :chapter do
    field :id, non_null(:id)
    field :title, :string
    field :start_time, non_null(:float)
    field :end_time, :float
  end

  object :supplemental_file do
    field :filename, non_null(:string)
    field :label, :string
    field :mime, non_null(:string)
    field :path, non_null(:string)
  end

  node object(:media) do
    field :status, non_null(:media_processing_status)

    field :full_cast, non_null(:boolean)
    field :abridged, non_null(:boolean)

    @desc "Display-title override for this recording (translated/regional/retail title); null means the book's title applies"
    field :title, :string

    @desc "For multi-part recordings: this recording's position in its part set"
    field :part_number, :integer
    field :parts_total, :integer

    field :recording_group, :recording_group, resolve: dataloader(Resolvers)

    field :duration, :float, resolve: Resolvers.resolve_decimal(:duration)
    field :mpd_path, :string
    field :hls_path, :string
    field :mp4_path, :string

    field :chapters, non_null(list_of(non_null(:chapter))), resolve: &Resolvers.chapters/3

    field :book, non_null(:book), resolve: dataloader(Resolvers)

    field :narrators, non_null(list_of(non_null(:narrator))),
      resolve: dataloader(Resolvers, args: %{order: {:asc, :name}})

    field :published, :date
    field :published_format, non_null(:date_format)
    field :publisher, :string

    field :notes, :string

    field :description, :string
    field :thumbnails, :thumbnails

    field :supplemental_files, non_null(list_of(non_null(:supplemental_file)))

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)

    field :image_path, :string, deprecate: "use `thumbnails` instead"
  end

  node object(:recording_group) do
    @desc "Admin-only organizational label; clients should not display it"
    field :name, :string

    @desc "Wording for one release in this set; null means \"part\""
    field :part_word, :string

    @desc "Wording for several releases; null means \"parts\""
    field :part_word_plural, :string

    field :media, non_null(list_of(non_null(:media))),
      resolve: dataloader(Resolvers, args: %{order: {:asc, :part_number}})

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end

  node object(:media_narrator) do
    field :media, non_null(:media), resolve: dataloader(Resolvers, args: %{allow_all_media: true})
    field :narrator, non_null(:narrator), resolve: dataloader(Resolvers)

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end

  connection(node_type: :media)
end
