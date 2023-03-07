defprotocol Ambry.PubSub.Publishable do
  @fallback_to_any true

  @doc "Returns the topics that should be published to for the given struct"
  def topics(data)
end

defimpl Ambry.PubSub.Publishable, for: Any do
  def topics(%mod{id: id}) do
    type = Ambry.PubSub.type(mod)

    [
      "#{type}:#{id}",
      "#{type}:*"
    ]
  end

  def topics(not_a_struct) do
    raise "Ambry.PubSub.Publishable.topics/1 requires a struct with an `:id` field, got #{inspect(not_a_struct)}"
  end
end
