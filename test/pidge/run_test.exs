defmodule Pidge.RunTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Pidge.Compiler.{CompileState,PidgeScript}
  alias Pidge.App.Loft
  alias Pidge.Run
  alias Pidge.FlightControl
  alias Pidge.Runtime.{RunState, SessionState}

  @step_name "elmer/read_json_example"
  @json_input """
  This is some pre-amble text.  Laa dee dah...

  <pre>
  {
    "kids": [
      {
        "name": "elmer",
        "hobby": "pizza eating",
        "age": 12
      },
      {
        "name": "wilbur",
        "hobby": "pizza making",
        "age": 14
      }
    ]
  }
  </pre>
  """

  describe "run/2" do
    test "it handles a simple, but general case" do
      code = """
        Context.add_conversation(:elmer)
        test = ai_object_extract(:elmer, "elmer/read_json_example", :json, schema: Plot)
        foreach(test.kids, fn {kid,i} ->
          kids_copy.nested.kids = kid
        end)
      """

      {:ok, ast} = compile_ast(code, quiet: true)
      {:ok, {:last}, global, stack_state} = run_ast("simple-general", ast, @step_name, @json_input, verbosity: -5)

      {:ok, test} = Jason.decode(global["json"]["test"], keys: :atoms)
      [kid|_] = test.kids
      assert kid.name == "elmer"
      assert stack_state["foreach-00004[1]"]["kids_copy"]["nested"]["kids"]["hobby"] == "pizza making"
    end

    test "various assignment operations" do
      code = """
        test = ai_object_extract(:elmer, "elmer/read_json_example", :json, schema: Plot)
        george = test.kids[0]
        george.name = "george"
        george.age = 13
        george.hobby = test.kids[1].hobby

        bob = george
        bob.a.b.c.d.e.f.g = 1
        george <~ bob

        test.kids <~ george
      """

      {:ok, ast} = compile_ast(code, quiet: false)
      {:ok, {:last}, global, _stack_state} = run_ast("various-assignments", ast, @step_name, @json_input, verbosity: -3)

      {:ok, test} = Jason.decode(global["json"]["test"], keys: :atoms)
      george = Enum.at(test.kids,2)
      assert george.name == "george"
      assert george.age == 13
      assert george.hobby == "pizza making"
      assert george.a.b.c.d.e.f.g == 1
    end

    test "various variable access patterns" do
      code = """
        test = ai_object_extract(:elmer, "elmer/read_json_example", :json, schema: Plot)
        a = test["kids"][0].name
        b = test.nonexistant.b.c.d.e.f.g
      """

      {:ok, ast} = compile_ast(code, quiet: false)
      {:ok, {:last}, global, _stack_state} = run_ast("var-access", ast, @step_name, @json_input, verbosity: -3)

      assert global["a"] == "elmer"
      assert global["b"] == nil
    end

    test "various basic variable access inside of if expressions" do
      code = """
        test = ai_object_extract(:elmer, "elmer/read_json_example", :json, schema: Plot)
        pass.a = 1
        fail.z = 1
        key = "kids"
        if test do
          pass.b = 1
        end
        if test[kids] do
          fail.y = 1
        end
        if test[key] do
          pass.c = 1
        end
        if test["kids"] do
          pass.d = 1
        end
        if test.kids do
          pass.e = 1
        end
        if test.kids[0] do
          pass.f = 1
        end
        if test.kids[0].name do
          pass.g = 1
        end
        if test.kids[0].name.nonexistant do
          fail.x = 1
        end

        global_scope_foo = 0
        if test["kids"][0].name == "elmer" do
          pass.h = 1
          global_scope_foo = 10
          sub_scope_b = 5
        end
        if (test.kids[0].name == "elmer") && (test.kids[1].name == "wilbur") do
          pass.i = 1
          if (global_scope_foo == 10) && !sub_scope_b do
            pass.j = 1
          end
        end
      """

      {:ok, ast} = compile_ast(code, quiet: true)
      {:ok, {:last}, global, _stack_state} = run_ast("vars-in-if", ast, @step_name, @json_input, verbosity: -3)
      # IO.inspect(global, label: "global")

      pass_letters = "abcdefgij"
      # split string into list of chars
      pass_list = String.graphemes(pass_letters)
      Enum.each(pass_list, fn letter ->
        assert %{^letter => 1} = global["pass"]
      end)
      assert Map.keys(global["fail"]) == ["z"]
    end

    test "various if expression formats and operators" do
      code = """
        test.foo = 10
        test.bar.baz = "handy"
        test.bar.bip = "20"
        test.bar.bop = 30

        pass.a = 1
        fail.z = 1

        if test.foo > test["bar"].bop do
          fail.y = 1
        end
        if ( test.blip && test.bar.bip > 3 )
           || (
                !(
                  !(test.foo < test.bar.bop)
                  || test.bar["bop"]<=29.95
                )
                && !nonexistant
              ) do
          pass.b = 1
        end
      """

      {:ok, ast} = compile_ast(code, quiet: true)
      {:ok, {:last}, global, _stack_state} = run_ast("expr-formats", ast, nil, @json_input, verbosity: -3)
      # IO.inspect(global, label: "global")

      pass_letters = "b"
      # split string into list of chars
      pass_list = String.graphemes(pass_letters)
      Enum.each(pass_list, fn letter ->
        assert %{^letter => 1} = global["pass"]
      end)
      assert Map.keys(global["fail"]) == ["z"]
    end

    test "local functions" do
      code = """
        one = 1
        list = []
        list <~ one
        new_list = Local.add_two(list)
      """

      function_code = """
      def function(list) do
        list ++ [2]
      end
      """

      {:ok, function_ast} = Pidge.Compiler.LocalFunction.ElixirSyntax.validate_function(function_code)
      {:ok, compiled_function} = Pidge.Compiler.LocalFunction.ElixirSyntax.compile_function(function_ast)
      {:ok, ast} = compile_ast(code, quiet: true)
      {:ok, {:last}, global, _stack_state} = run_ast(
        "local-functions",
        ast,
        nil,
        @json_input,
        verbosity: -3,
        local_functions: %{"add_two.ex.pjf" => compiled_function}
      )
      # IO.inspect(global, label: "global")

      assert global["new_list"] == [1,2]
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
          {:compile_ast, {:ok, _} = result} -> result
          {:compile_ast, result} ->
            IO.puts("Compile failed [#{inspect(result)}], output:")
            IO.puts(out)
            result
        end
      false -> PidgeScript.compile_source(code)
    end
    CompileState.stop(compilestate_pid)
    result
  end

  def run_ast(test_session, ast, from_step, input, opts \\ []) do
    session_id = "test/run_test-#{test_session}"

    {:ok, sessionstate_pid} = SessionState.start_link(session_id)
    SessionState.wipe()
    SessionState.stop(sessionstate_pid)

    runtime_opts = %{
      verbosity: Keyword.get(opts, :verbosity, -5),
      input: input,
      session: session_id
    }
    runtime_opts = if from_step != nil do
      Map.put(runtime_opts, :from_step, from_step)
    else
      runtime_opts
    end

    {:ok, flightcontrol_pid} = FlightControl.start_link()
    {:ok, runstate_pid} = RunState.start_link()
    RunState.init_session(runtime_opts)
    {:ok, sessionstate_pid} = SessionState.start_link(RunState.get_opt(:session))
    {:ok, loft_pid} = Loft.start_link()

    Loft.register_app(:local, %{
      pidge_code: %{main: ast},
      local_function_files: Keyword.get(opts, :local_functions, %{}),
      prompt_files: Keyword.get(opts, :prompt_files, %{})
    })

    run_result = Run.private__run(:local, :main)

    Loft.stop(loft_pid)
    RunState.stop(runstate_pid)
    SessionState.stop(sessionstate_pid)
    FlightControl.stop(flightcontrol_pid)

    {:ok, sessionstate_pid} = SessionState.start_link(session_id)
    global = SessionState.get()
    # IO.inspect(global, label: "global")
    stack_state = SessionState.get_stack_state()
    # IO.inspect(stack_state, label: "stack_state")
    SessionState.stop(sessionstate_pid)

    {:ok, run_result, global, stack_state}
  end
end
