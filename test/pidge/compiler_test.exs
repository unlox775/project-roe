defmodule Pidge.CompilerTest do
  use ExUnit.Case, async: true

  @example_pidge_code """
  Context.add_conversation(:elmer)
  Context.add_conversation(:wilbur)
  test = ai_object_extract(:elmer, "elmer/read_json_example", :json, schema: Plot)
  foreach(test.bots, fn {bot,i} ->
    bots_copy.nested = test.bots
    bot_clone = bot
  end)
  """

  test "compiles the provided code into the correct AST" do
    expected_ast = [
      %{id: nil, seq: "00001", params: %{conversation_id: :elmer}, method: :context_create_conversation},
      %{id: nil, seq: "00002", params: %{conversation_id: :wilbur}, method: :context_create_conversation},
      %{id: "elmer/read_json_example", seq: "00003", params: %{format: "json", prompt: "elmer/read_json_example", conversation_id: "elmer", schema: {:__aliases__, [line: 3], [:Plot]}}, method: :ai_object_extract},
      %{id: nil, seq: "00004", params: %{object_name: "test"}, method: :store_object},
      %{id: nil, seq: "00005", method: :foreach, params: %{instance_variable_name: "bot", iter_variable_name: "i", loop_on_variable_name: ["test", "bots"], sub_pidge_ast: [
        %{id: nil, seq: "00001", params: %{object_name: ["bots_copy", "nested"], clone_from_object_name: ["test", "bots"]}, method: :clone_object},
        %{id: nil, seq: "00002", params: %{object_name: "bot_clone", clone_from_object_name: "bot"}, method: :clone_object}
      ]}}
    ]

    {:ok, result_ast} = Pidge.Compiler.compile_source(@example_pidge_code)

    assert expected_ast == result_ast
  end
end