defmodule AmbryWeb.HeaderLive.SearchForm do
  @moduledoc false

  use AmbryWeb, :component

  alias AmbryWeb.Endpoint

  alias Surface.Components.Form
  alias Surface.Components.Form.{Field, TextInput}

  prop change, :event, required: true
  prop close, :event, required: true
  prop query, :string, required: true
end
