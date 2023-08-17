defmodule Pidge.RunTest do
  use ExUnit.Case, async: true

  alias Pidge.Run
  alias Pidge.State

  @step_name "elmer/read_json_example"
  @simple_ast [
    %{id: nil, seq: "00001", params: %{conversation_id: :elmer}, method: :context_create_conversation},
    %{id: nil, seq: "00002", params: %{conversation_id: :wilbur}, method: :context_create_conversation},
    %{id: @step_name, seq: "00003", params: %{format: "json", prompt: @step_name, conversation_id: "elmer", schema: {:character, [line: 28], nil}}, method: :ai_object_extract},
    %{id: nil, seq: "0004", params: %{object_name: "test"}, method: :store_object},
    %{id: nil, seq: "0005", method: :foreach, params: %{instance_variable_name: "bot", iter_variable_name: "i", loop_on_variable_name: ["test","bots"], sub_pidge_ast: [
      %{id: nil, seq: "00001", params: %{object_name: "bots_copy"}, method: :store_object},
      %{id: nil, seq: "00002", params: %{object_name: "bot_clone", clone_from_object_name: "bot"}, method: :clone_object}
    ]}}
  ]
  @json_input """
  This is some pre-amble text.  Laa dee dah...

  <pre>
  {
    "bots": [
      {
        "name": "elmer",
        "hobby": "pizza eating"
      },
      {
        "name": "wilbur",
        "hobby": "pizza making"
      }
    ]
  }
  </pre>
"""

def get_session_id(line) do
  token = :crypto.hash(:sha256,"#{__MODULE__}_#{line}") |> Base.encode16
  "test/#{String.slice(token, 0, 8)}"
end

  describe "run/2" do
    test "run test" do
      session_id = get_session_id(__ENV__.line)
      State.wipe(session_id)

      opts = %{
        from_step: @step_name,
        verbosity: -5,
        input: @json_input,
        session: session_id
      }
      assert {:last} = Run.run(opts, @simple_ast)

      state = State.get_current_state(session_id)

      assert [%{
        "hobby" => "pizza eating",
        "name" => "elmer"
      }| _] = state["bots_copy"]["bots"]
    end
  end
end
