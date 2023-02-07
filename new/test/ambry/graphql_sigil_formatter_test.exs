defmodule Ambry.GraphqlSigilFormatterTest do
  use ExUnit.Case

  alias Ambry.GraphQLSigilFormatter

  describe "features/1" do
    test "returns the features" do
      assert [sigils: [:G], extensions: []] = GraphQLSigilFormatter.features([])
    end
  end

  describe "format/1" do
    test "formats graphql documents" do
      assert """
             query FooQuery {
               foo {
                 bar
               }
             }
             """ = GraphQLSigilFormatter.format("query FooQuery { foo { bar } }")
    end
  end
end
