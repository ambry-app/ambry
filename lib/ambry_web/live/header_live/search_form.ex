defmodule AmbryWeb.HeaderLive.SearchForm do
  use AmbryWeb, :component

  alias Surface.Components.Form
  alias Surface.Components.Form.{Field, TextInput}

  prop change, :event, required: true
  prop toggle, :event, required: true
  prop query, :string, required: true
  prop expanded, :boolean, required: true
end
