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

  @desc "How accurately a player can seek within a track"
  enum :seek_accuracy do
    @desc "Seeking lands where it says it does"
    value :exact

    @desc "The file carries no seek index (e.g. VBR mp3 with no Xing header); positions may drift"
    value :approximate
  end

  node object(:media) do
    field :status, non_null(:media_processing_status)

    field :full_cast, non_null(:boolean)
    field :abridged, non_null(:boolean)

    @desc "Display-title override for this recording (translated/regional/retail title); null means the book's title applies"
    field :title, :string

    @desc "For multi-part recordings: this recording's position in its part set; the set's total lives on the recording group"
    field :part_number, :integer

    field :recording_group, :recording_group, resolve: dataloader(Resolvers)

    field :duration, :float, resolve: Resolvers.resolve_decimal(:duration)

    # kept as-is, not deprecated: until direct-play publishing is switched on
    # these are still the only way to play anything, and every deployed client
    # queries them
    field :mpd_path, :string
    field :hls_path, :string
    field :mp4_path, :string

    field :chapters, non_null(list_of(non_null(:chapter))), resolve: &Resolvers.chapters/3

    field :book, non_null(:book), resolve: dataloader(Resolvers)

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
    @desc "This set's name, shown to readers only when `show_label` says so"
    field :name, non_null(:string)

    @desc "Whether to show `name` on this set's tile; an operator choice, never inferred"
    field :show_label, non_null(:boolean)

    @desc "How many releases the set has, when known (\"Part 2 of 3\")"
    field :parts_total, :integer

    @desc "The work this set covers, same as its members'"
    field :book, non_null(:book), resolve: dataloader(Resolvers)

    @desc "Wording for one release in this set; null means \"part\""
    field :part_word, :string

    @desc "Wording for several releases; null means \"parts\""
    field :part_word_plural, :string

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end

  @desc "One audio file of a recording, played directly by the client"
  node object(:media_track) do
    field :media, non_null(:media), resolve: dataloader(Resolvers, args: %{allow_all_media: true})

    @desc "Position in the recording's ordered track list, 0-based"
    field :index, non_null(:integer)

    @desc "Where to fetch the file; requires the same authentication as any other media URL"
    field :path, non_null(:string), resolve: &Resolvers.media_track_path/3

    @desc "Size in bytes. A float because audiobook files routinely exceed what GraphQL's 32-bit Int can hold"
    field :size, non_null(:float), resolve: fn track, _, _ -> {:ok, track.size / 1} end

    @desc "Media type of the file, e.g. \"audio/mp4\""
    field :mime, :string

    @desc "Container as probed, e.g. \"mov,mp4,m4a,3gp,3g2,mj2\""
    field :format, :string

    @desc "Audio codec as probed, e.g. \"aac\". Clients decide playability from this and `mime`; nothing here is assumed playable"
    field :codec, :string

    field :duration, non_null(:float), resolve: Resolvers.resolve_decimal(:duration)

    @desc "Where this track starts on the book's continuous timeline, in seconds. Playback positions are always absolute book-seconds"
    field :start_offset, non_null(:float), resolve: Resolvers.resolve_decimal(:start_offset)

    field :seek_accuracy, non_null(:seek_accuracy)

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end

  node object(:media_narrator) do
    # Billing order: position 0 is the recording's lead narrator.
    field :position, non_null(:integer)

    field :media, non_null(:media), resolve: dataloader(Resolvers, args: %{allow_all_media: true})
    field :narrator, non_null(:narrator), resolve: dataloader(Resolvers)

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end
end
