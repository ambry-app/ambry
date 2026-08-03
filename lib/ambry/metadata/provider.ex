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
        ),
        do: %{published | display_format: :year}

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
      authors: [],
      narrators: [],
      series: [],
      editions: []
    ]

    @type t :: %__MODULE__{}
  end

  defmodule Author do
    @moduledoc "A normalized author (or narrator) profile."
    defstruct [:provider, :id, :name, :description, :image_url]

    @type t :: %__MODULE__{}
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

  @type config :: %{optional(atom) => term}
  @type capability :: :book_search | :book_details | :author_search | :author_details | :chapters

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

  @callback search_books(query :: String.t(), config()) :: {:ok, [Book.t()]} | {:error, term}
  @callback book_details(id :: String.t(), config()) :: {:ok, Book.t()} | {:error, term}
  @callback search_authors(query :: String.t(), config()) :: {:ok, [Author.t()]} | {:error, term}
  @callback author_details(id :: String.t(), config()) :: {:ok, Author.t()} | {:error, term}
  @callback chapters(asin :: String.t(), config()) :: {:ok, Chapters.t()} | {:error, term}

  @optional_callbacks available?: 1,
                      config_notices: 1,
                      search_books: 2,
                      book_details: 2,
                      search_authors: 2,
                      author_details: 2,
                      chapters: 2

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
