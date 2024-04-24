defmodule Ambry.People.PersonName do
  @moduledoc false

  defstruct [:name, :person_name]

  defmodule Type do
    @moduledoc false

    use Ecto.Type

    alias Ambry.People.PersonName

    def type, do: :person_name

    def cast(%PersonName{} = person_name) do
      {:ok, person_name}
    end

    def cast(_person_name), do: :error

    def load({name, person_name}) do
      {:ok, struct!(PersonName, name: name, person_name: person_name)}
    end

    def dump(%PersonName{name: name, person_name: person_name}), do: {:ok, {name, person_name}}
    def dump(_person_name), do: :error
  end
end
