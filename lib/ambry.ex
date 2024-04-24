defmodule Ambry do
  @moduledoc """
  Ambry keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  use Boundary,
    deps: [AmbryScraping],
    exports: [
      {Accounts, []},
      {Books, []},
      {FileBrowser, []},
      {Hashids, []},
      {Media, []},
      {Metadata, []},
      {Paths, []},
      {People, []},
      {PubSub, []},
      {Repo, []},
      {Search, []},
      {Utils, []}
    ]
end
