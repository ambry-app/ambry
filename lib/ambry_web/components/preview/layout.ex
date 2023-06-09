defmodule AmbryWeb.Preview.Layouts do
  @moduledoc false

  use AmbryWeb, :html

  import AmbryWeb.Layouts, only: [ambry_icon: 1, ambry_title: 1]

  embed_templates "layouts/*"
end
