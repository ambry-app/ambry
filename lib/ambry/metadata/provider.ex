defmodule Ambry.Metadata.Provider do
  @moduledoc """
  Behaviour for metadata providers.

  Providers are split by which level of Ambry's data model they can speak to:

    * `:work` — the abstract side: books, authors, series. These providers
      know about works and their editions but nothing about narrators or
      audiobook releases.
    * `:recording` — the concrete side: audiobook releases with narrators,
      square cover art, chapters. ASIN is the natural key at this level.
    * `:person` — the humans behind author and narrator identities: bios
      and profile photos, keyed on real people rather than published-as
      names (covers narrate-only people and the halves of composite pen
      names that book catalogs can't see).

  All callbacks return normalized structs defined in this module, so the web
  layer never depends on any provider's upstream payload shape. Capabilities
  declare which optional callbacks a provider implements; callers must check
  capabilities (via `Ambry.Metadata.Registry`) before invoking optional
  callbacks.

  Providers are pure fetch-and-normalize modules: no caching (see
  `Ambry.Metadata.Cache`) and no persistence. Configuration (base URL, API
  token, …) is passed into every call as a map, sourced from the provider
  registry so operators can change it at runtime.
  """

  defmodule PublishedDate do
    @moduledoc """
    A date with display granularity, since providers report anything from a
    full date to just a year.
    """
    defstruct [:date, :display_format]

    @type t :: %__MODULE__{date: Date.t(), display_format: :full | :year_month | :year}

    @doc "Builds from an ISO8601-ish string (`2020-09-21`, `2020-09`, `2020`)."
    def from_string(nil), do: nil
    def from_string(""), do: nil

    def from_string(string) when is_binary(string) do
      case String.split(string, "-") do
        [year, month, day] -> new(year, month, day, :full)
        [year, month] -> new(year, month, "01", :year_month)
        [year] -> new(year, "01", "01", :year)
        _else -> nil
      end
    end

    @doc """
    Demotes a full January-1st date to year-only display.

    Goodreads-shaped sources (and Hardcover) encode "we only know the
    year" as a literal `YYYY-01-01`, indistinguishable in the payload
    from a real date — so a full Jan-1 date is far more likely year-only
    knowledge than a genuine release day. The underlying date is kept;
    the operator can flip the display format back per book when a
    release really was January 1st.
    """
    def assume_jan1_is_year_only(nil), do: nil

    def assume_jan1_is_year_only(
          %__MODULE__{display_format: :full, date: %Date{month: 1, day: 1}} = published
        ), do: %{published | display_format: :year}

    def assume_jan1_is_year_only(%__MODULE__{} = published), do: published

    defp new(year, month, day, display_format) do
      case Date.from_iso8601("#{year}-#{pad(month)}-#{pad(day)}") do
        {:ok, date} -> %__MODULE__{date: date, display_format: display_format}
        {:error, _reason} -> nil
      end
    end

    defp pad(string), do: String.pad_leading(string, 2, "0")
  end

  defmodule Contributor do
    @moduledoc "A person credit on a book or recording, as reported by a provider."
    defstruct [:id, :name, :role]

    @type t :: %__MODULE__{id: String.t() | nil, name: String.t(), role: String.t()}
  end

  defmodule Series do
    @moduledoc "A series membership, with the position kept as a string (\"10.5\")."
    defstruct [:id, :name, :number]

    @type t :: %__MODULE__{id: String.t() | nil, name: String.t(), number: String.t() | nil}
  end

  defmodule Edition do
    @moduledoc "One edition of a work, offered as a source for covers/descriptions/facts."
    defstruct [
      :id,
      :title,
      :asin,
      :description,
      :language,
      :format,
      :publisher,
      :published,
      :cover_url
    ]

    @type t :: %__MODULE__{}
  end

  defmodule Book do
    @moduledoc """
    A normalized book result — a work (work-level providers) or an audiobook
    release (recording-level providers). Recording-level results carry
    narrators and an ASIN; work-level results may carry an editions list.

    `duration_seconds` is how long the *recording* is, and it is nil on a
    work: a novel has no runtime, a reading of it does. It is the field that
    tells two recordings of the same book apart when everything else about
    them agrees — abridged from unabridged, one cast from another — which is
    why an audiobook library carries it and a book catalogue would not.
    """
    defstruct [
      :provider,
      :id,
      :title,
      :description,
      :cover_url,
      :published,
      :publisher,
      :language,
      :format,
      :asin,
      :duration_seconds,
      authors: [],
      narrators: [],
      series: [],
      editions: []
    ]

    @type t :: %__MODULE__{}
  end

  defmodule Author do
    @moduledoc """
    A normalized author (or narrator) profile.

    `image_urls` is every photo the provider has of this person, best first;
    `image_url` is the first of them, kept because most callers want one
    picture and shouldn't have to say so.

    Several matters because a profile photo has to survive a **circular
    crop**. The obvious portrait — Wikipedia's lead image, TMDB's primary
    headshot — is frequently the one that doesn't: a head at the edge of a
    wide shot, a group photo, a book jacket with the face bottom-left. The
    alternative three rows down is often the one that works, and a picker
    showing one image per provider can't offer it.
    """
    defstruct [:provider, :id, :name, :description, :image_url, image_urls: []]

    @type t :: %__MODULE__{}

    @doc """
    Every photo this profile has, best first.

    Falls back to `image_url` because `image_urls` is additive: a provider
    that only ever had one photo per person still builds the struct the old
    way, and must keep contributing that photo.
    """
    def images(%__MODULE__{image_urls: [_ | _] = urls}), do: urls
    def images(%__MODULE__{image_url: url}) when is_binary(url) and url != "", do: [url]
    def images(%__MODULE__{}), do: []

    @doc """
    Builds a profile, keeping `image_url` and `image_urls` consistent.
    """
    def new(attrs) do
      urls = attrs |> Map.get(:image_urls, []) |> List.wrap() |> Enum.uniq()
      urls = if attrs[:image_url], do: Enum.uniq([attrs[:image_url] | urls]), else: urls

      struct!(__MODULE__, Map.merge(attrs, %{image_url: List.first(urls), image_urls: urls}))
    end
  end

  defmodule Chapter do
    @moduledoc "A single chapter: title plus offsets in milliseconds."
    defstruct [:title, :start_offset_ms, :length_ms]

    @type t :: %__MODULE__{}
  end

  defmodule Chapters do
    @moduledoc "A chapter list for a recording, keyed by ASIN."
    defstruct [:provider, :asin, chapters: []]

    @type t :: %__MODULE__{}
  end

  defmodule ConfigField do
    @moduledoc "Describes one operator-editable provider setting for the admin UI."
    defstruct [:key, :label, :type, :default, :help]

    @type t :: %__MODULE__{key: atom, label: String.t(), type: :string | :secret, default: term}
  end

  defmodule Query do
    @moduledoc """
    A book search expressed as the fields it's actually made of.

    A single concatenated string is lossy in a way that silently breaks
    providers: Audible's catalog endpoint takes `title`, `author` and
    `narrator` as separate parameters, so handing it `"Neuromancer William
    Gibson"` searched for a book *titled* that and returned nothing at all —
    which is why the inbox's whole recording level came up empty.

    Providers that only do free text can call `to_string/1` (or interpolate,
    via `String.Chars`) and lose nothing. Providers that can be precise get to
    be precise. `narrator` is the field that distinguishes two recordings of
    one work, so it exists here even though only recording-level providers
    have any use for it.
    """

    @enforce_keys []
    defstruct [:title, :author, :narrator, :keywords]

    @type t :: %__MODULE__{
            title: String.t() | nil,
            author: String.t() | nil,
            narrator: String.t() | nil,
            keywords: String.t() | nil
          }

    @doc "Whether there is anything here to search for."
    def blank?(%__MODULE__{} = query), do: to_string(query) == ""

    @doc """
    A query from operator-typed fields — string keys, blanks dropped.

    This is the shape every "search again" form submits, inbox or not.
    """
    def from_fields(fields) when is_map(fields) do
      %__MODULE__{
        title: blank_to_nil(fields["title"]),
        author: blank_to_nil(fields["author"]),
        narrator: blank_to_nil(fields["narrator"]),
        keywords: blank_to_nil(fields["keywords"])
      }
    end

    @doc """
    The non-blank fields as a string-keyed map — the storable/displayable
    inverse of `from_fields/1`, used to show "what did you even search for".
    """
    def non_blank_fields(%__MODULE__{} = query) do
      %{
        "title" => query.title,
        "author" => query.author,
        "narrator" => query.narrator,
        "keywords" => query.keywords
      }
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()
    end

    defp blank_to_nil(nil), do: nil
    defp blank_to_nil(value) when is_binary(value), do: with("" <- String.trim(value), do: nil)

    defimpl String.Chars do
      @doc """
      The free-text rendering, which is also what the metadata cache keys on —
      so two structurally different queries can never collide.
      """
      def to_string(query) do
        [query.keywords, query.title, query.author, query.narrator]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join(" ")
      end
    end
  end

  @type config :: %{optional(atom) => term}
  @type capability ::
          :book_search
          | :book_details
          | :author_search
          | :author_details
          | :chapters
          | :editions
          | :editions_bulk

  @doc "Stable machine identifier, used in cache keys and settings rows."
  @callback id() :: String.t()

  @doc "Human-readable name for the admin UI."
  @callback display_name() :: String.t()

  @doc "Which level of the data model this provider speaks to."
  @callback level() :: :work | :recording | :person

  @doc "The optional callbacks this provider actually implements."
  @callback capabilities() :: [capability()]

  @doc "Operator-editable settings, with defaults giving a zero-config working setup."
  @callback config_fields() :: [ConfigField.t()]

  @type notice :: {:info | :warning | :error, String.t()}

  @doc """
  Whether the provider can be used with the given config — e.g. a provider
  requiring an API token is unavailable until one is configured. Unavailable
  providers stay visible in the admin settings (with notices explaining why)
  but are not offered in import forms. Optional; defaults to `true`.
  """
  @callback available?(config()) :: boolean

  @doc """
  Operator-facing notices about the provider's configuration — token
  expiry warnings, setup hints. Shown on the admin settings page.
  Optional; defaults to `[]`.
  """
  @callback config_notices(config()) :: [notice()]

  # `{:partial, …}` is for a provider that is more than one source behind one
  # name — Audible's regional catalogs — where some of them answered and some
  # did not. The results are usable and incomplete, and a provider that says
  # only the first half turns an unreachable region into an empty one.
  @callback search_books(query :: String.t() | Query.t(), config()) ::
              {:ok, [Book.t()]} | {:partial, [Book.t()], term} | {:error, term}
  @callback book_details(id :: String.t(), config()) :: {:ok, Book.t()} | {:error, term}
  @callback search_authors(query :: String.t(), config()) :: {:ok, [Author.t()]} | {:error, term}
  @callback author_details(id :: String.t(), config()) :: {:ok, Author.t()} | {:error, term}
  @callback chapters(asin :: String.t(), config()) :: {:ok, Chapters.t()} | {:error, term}

  @doc """
  The audiobook editions of a work this provider already identified.

  A third key, alongside "search for a work" and "search for a recording":
  once the work is matched, its own edition list is the most direct route to
  the recordings that exist — including ones a storefront has since delisted
  and can no longer be searched for at all.
  """
  @callback editions(work_id :: String.t(), config()) :: {:ok, [Book.t()]} | {:error, term}

  @doc """
  The audiobook editions of several works at once, keyed by work id.

  Declared separately from `editions/2` because whether a provider can answer
  for many works in one round trip is a real difference in what it can do, not
  an optimization a caller may assume. A provider that can say so is asked
  once instead of once per work — which is the difference between opening
  every candidate work and opening only the first few.
  """
  @callback editions_bulk(work_ids :: [String.t()], config()) ::
              {:ok, %{String.t() => [Book.t()]}} | {:error, term}

  @optional_callbacks available?: 1,
                      config_notices: 1,
                      search_books: 2,
                      book_details: 2,
                      search_authors: 2,
                      author_details: 2,
                      chapters: 2,
                      editions: 2,
                      editions_bulk: 2

  @doc "The default config for a provider module, derived from its config fields."
  def default_config(provider_module) do
    Map.new(provider_module.config_fields(), fn field -> {field.key, field.default} end)
  end

  @doc "Whether a provider module is usable with the given config (default true)."
  def available?(provider_module, config) do
    not function_exported?(provider_module, :available?, 1) or provider_module.available?(config)
  end

  @doc "Operator-facing config notices for a provider module (default none)."
  def config_notices(provider_module, config) do
    if function_exported?(provider_module, :config_notices, 1) do
      provider_module.config_notices(config)
    else
      []
    end
  end
end
