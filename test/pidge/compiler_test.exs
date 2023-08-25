defmodule Pidge.CompilerTest do
  use ExUnit.Case, async: true

  alias Pidge.Compiler.CompileState
  alias Pidge.Compiler.PidgeScript

  @example_pidge_code """
  Context.add_conversation(:elmer)
  Context.add_conversation(:wilbur)
  test = ai_object_extract(:elmer, "elmer/read_json_example", :json, schema: Plot)
  foreach(test.bots, fn {bot,i} ->
    if ! site.parser_js || (i > 10 && test.bots[sub.key] == bot["pizza-foo"]) do
      continue
    end
    bots_copy.nested = test["bots"]
    bot_clone = test.bots[i]
    bot_clone_too = bot
    bot_clone = test.bots[sub.key]
  end)
  """

  test "compiles the provided code into the correct AST" do
    expected_ast = [
      %{id: nil, seq: "00001", params: %{conversation_id: :elmer}, method: :context_create_conversation},
      %{id: nil, seq: "00002", params: %{conversation_id: :wilbur}, method: :context_create_conversation},
      %{id: "elmer/read_json_example", seq: "00003", params: %{format: "json", prompt: "elmer/read_json_example", conversation_id: "elmer", schema: {:__aliases__, [line: 3], [:Plot]}}, method: :ai_object_extract},
      %{id: nil, seq: "00004", params: %{object_name: "test"}, method: :store_object},
      %{id: nil, seq: "00005", method: :foreach, params: %{instance_variable_name: "bot", iter_variable_name: "i", loop_on_variable_name: ["test", "bots"], sub_pidge_ast: [
        %{
          id: nil,
          method: :if,
          params: %{
            expression: {
              :||,
              [line: 5],
              [
                {
                  :!,
                  [line: 5],
                  [
                    {
                      {
                        :.,
                        [line: 5],
                        [
                          {
                            :__aliases__,
                            [line: 5],
                            [:Pidge, :Runtime, :CallStack]
                          },
                          :get_variable
                        ]
                      },
                      [line: 5],
                      [["site", "parser_js"]]
                    }
                  ]
                },
                {
                  :&&,
                  [line: 5],
                  [
                    {
                      :>,
                      [line: 5],
                      [{:i, [line: 5], nil}, 10]
                    },
                    {
                      :==,
                      [line: 5],
                      [
                        {
                          {
                            :.,
                            [line: 5],
                            [
                              {:__aliases__, [line: 5], [:Pidge, :Runtime, :CallStack]},
                              :get_variable
                            ]
                          },
                          [line: 5],
                          [
                            [[{{:., [line: 5], [{:__aliases__, [line: 5], [:Pidge, :Runtime, :CallStack]}, :get_variable]}, [line: 5], [["test", "bots"]]}, {{{{:., [line: 5], [{:__aliases__, [line: 5], [:Pidge, :Runtime, :CallStack]}, :get_variable]}, [line: 5], [["sub", "key"]]}, :expr}}]]
                          ]
                        },
                        {
                          {
                            :.,
                            [line: 5],
                            [
                              {:__aliases__, [line: 5], [:Pidge, :Runtime, :CallStack]},
                              :get_variable
                            ]
                          },
                          [line: 5],
                          [["bot", "pizza-foo"]]
                        }
                      ]
                    }
                  ]
                }
              ]
            },
            sub_pidge_ast: [
              %{
                id: nil,
                method: :continue,
                params: %{},
                seq: "00001"
              }
            ]
          },
          seq: "00001"
        },
        %{id: nil, seq: "00002", params: %{object_name: ["bots_copy", "nested"], clone_from_object_name: ["test", "bots"]}, method: :clone_object},
        %{id: nil, seq: "00003", params: %{object_name: "bot_clone", clone_from_object_name: ["test", {:i}, "bots"]}, method: :clone_object},
        %{id: nil, seq: "00004", params: %{object_name: "bot_clone_too", clone_from_object_name: "bot"}, method: :clone_object},
        %{id: nil, seq: "00005", params: %{clone_from_object_name: ["test", {["sub", "key"]}, "bots"], object_name: "bot_clone"}, method: :clone_object}
      ]}}
    ]

    {:ok, compilestate_pid} = CompileState.start_link(%{})
    {:ok, result_ast} = PidgeScript.compile_source(@example_pidge_code)
    CompileState.stop(compilestate_pid)

    assert expected_ast == result_ast
  end
end
