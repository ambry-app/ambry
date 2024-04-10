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
      Accounts,
      Accounts.User,
      Authors,
      Authors.Author,
      Books,
      Books.Book,
      DataCase,
      Factory,
      FileBrowser,
      FileBrowser.File,
      FileBrowser.FolderNode,
      FileUtils,
      FirstTimeSetup,
      Hashids,
      Media,
      Media.Audit,
      Media.Chapters,
      Media.Media,
      Media.PlayerState,
      Media.Processor,
      Media.ProcessorJob,
      Metadata.Audible,
      Metadata.GoodReads,
      Narrators,
      Narrators.Narrator,
      Paths,
      People,
      People.Person,
      PubSub,
      PubSub.Message,
      Repo,
      Search,
      Search.IndexManager,
      Series,
      Series.Series,
      Series.SeriesBook,
      SupplementalFile
    ]
end
