defmodule Pidge.RunTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Pidge.Run
  alias Pidge.Compiler.{CompileState,PidgeScript}
  alias Pidge.Runtime.SessionState

  @step_name "elmer/read_json_example"
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

  describe "run/2" do
    test "run test" do
      code = """
      Context.add_conversation(:elmer)
      test = ai_object_extract(:elmer, "elmer/read_json_example", :json, schema: Plot)
      foreach(test.bots, fn {bot,i} ->
        bots_copy.nested.bots = bot
      end)
      """

      {:ok, ast} = compile_ast(code, quiet: false)
      {:ok, {:last}, global, stack_state} = run_ast(ast, @step_name, @json_input, verbosity: -5)

      assert "{\n  \"bots\": [\n    {\n      \"hobby\": \"pizza eating\",\n      \"name\": \"elmer\"\n    },\n    {\n      \"hobby\": \"pizza making\",\n      \"name\": \"wilbur\"\n    }\n  ]\n}" = global["json"]["test"]
      assert %{
        "hobby" => "pizza making",
        "name" => "wilbur"
      } = stack_state["foreach-00004[1]"]["bots_copy"]["nested"]["bots"]
    end
  end

  def compile_ast(code, opts \\ []) do
    {:ok, compilestate_pid} = CompileState.start_link(%{})
    result = case Keyword.get(opts, :quiet, true) do
      true ->
        out = capture_io(fn ->
          send(self(), {:compile_ast, PidgeScript.compile_source(code)})
        end)
        receive do
          {:compile_ast, {:ok, _} = result} ->
            IO.puts(out)
            result
          {:compile_ast, result} -> result
        end
      false -> PidgeScript.compile_source(code)
    end
    CompileState.stop(compilestate_pid)
    result
  end

  def run_ast(ast, from_step, input, opts \\ []) do
    session_id = "test/run_test"

    {:ok, sessionstate_pid} = SessionState.start_link(session_id)
    SessionState.wipe()
    SessionState.stop(sessionstate_pid)

    opts = %{
      from_step: from_step,
      verbosity: Keyword.get(opts, :verbosity, -5),
      input: input,
      session: session_id
    }
    run_result = Run.run(opts, ast)

    {:ok, sessionstate_pid} = SessionState.start_link(session_id)
    global = SessionState.get()
    # IO.inspect(global, label: "global")
    stack_state = SessionState.get_stack_state()
    # IO.inspect(stack_state, label: "stack_state")
    SessionState.stop(sessionstate_pid)

    {:ok, run_result, global, stack_state}
  end
end
