defmodule Pidge.Run do
  @moduledoc """
  A module to execute steps in a Pidge script.
  """

  import Pidge.Util

  alias Pidge.Runtime.{ SessionState, RunState, CallStack }

  alias Pidge.Run.{ AIObjectExtract, LocalFunction }

  # @transit_tmp_dir "/tmp/roe/transit"
  @input_required_methods [:ai_pipethru, :store_object, :ai_object_extract, :ai_codeblock_extract]
  @blocking_methods [:ai_prompt, :ai_pipethru, :ai_object_extract, :ai_codeblock_extract]
  @allowed_methods [:context_create_conversation, :ai_prompt, :ai_pipethru, :ai_object_extract, :ai_codeblock_extract, :store_object, :clone_object, :merge_into_object, :foreach, :if, :pipe_from_variable, :local_function_call, :store_simple_value, :case]

  def run(args) do
    opts = parse_opts(args)

    with 1 <- 1,
      {:ok, pidge_ast} <- read_ast(),
      {:halt} <- run(opts, pidge_ast)
    do
      System.halt(0)
    else
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
        System.halt(1)
      {:last, _} ->
        IO.puts("Pidge Execution complete.")
        System.halt(0)
      error ->
        IO.puts("Unknown error: #{inspect(error)}")
        System.halt(1)
    end
  end

  def parse_opts(args) do
    switches = [
      input: :string,
      jump_to_step: :string,
      from_step: :string,
      human_input: :string,
      session: :string,
      verbose: :boolean,
      help: :boolean
      ]
    case OptionParser.parse(args, switches: switches) do
      {opts, _remaining, _invalid} ->
        # If --help was passed, print the help and exit
        if opts[:help] do
          print_help()
          System.halt(0)
        end

        # start with a count of times --verbose was passed
        verbosity = opts |> Enum.reduce(0, fn {key, _}, acc ->
          cond do
            key == :verbose -> acc + 1
            true -> acc
          end
        end)

        # now loop[ through the remaining args and count the number of times -v was passed,
        # including options like -vv as 2 and -vvvvv as 5
        verbosity = args |> Enum.reduce(verbosity, fn arg, acc ->
          # Get the number of v's in the argument
          match = Regex.run(~r/^-(v+)$/, arg)
          if match do
            # add 1 to verbosity for the length of the match
            acc + String.length(Enum.at(match,1))
          else
            acc
          end
        end)

        opts = opts ++ [verbosity: verbosity]
        # bug(opts,2,[verbosity_level: verbosity])
        # bug(opts,3,[opts: opts])

        # convert keyword list to map here
        Enum.into(opts, %{})

    error ->
        IO.puts("Options Read Error: #{inspect(error)}")
        System.halt(1)
    end
  end

  def run(opts, pidge_ast) do
    {:ok, runstate_pid} = RunState.start_link(opts)
    {:ok, sessionstate_pid} = SessionState.start_link(RunState.get_opt(:session))

    return = private__run(pidge_ast)

    RunState.stop(runstate_pid)
    SessionState.stop(sessionstate_pid)
    return
  end

  defp private__run(pidge_ast) do
    RunState.set_opt(:base_pidge_ast, pidge_ast)

    with 1 <- 1,
      # Find the step to start at
      {:ok, last_step, step, index} <- find_step(pidge_ast),
      # Run post process on last step if needed
      {:ok} <- post_process(last_step),
      {:ok} <- execute(pidge_ast, step, index)
    do
      # end the state process
      {:ok}
    end
  end

  def print_help do
    IO.puts("""
    Usage: pidge run [OPTIONS]

    Options:
      --input              Define input for the script
      --jump_to_step       Jump to a specific step in the program
      --from_step          Start from a specific step in the program
      --human_input        Provide human input for the program
      --verbose / -v       Enable verbose mode. This option can be used multiple times to increase verbosity level
      --help / -h          Display this help message

    Examples:
      pidge run --input "This is text to ask the AI.  Why is the sky blue?"
      pidge run --jump_to_step step3 --verbose
      pidge run -vv --human_input "Hello, world!"
    """)
  end


  # debug function passed level of debugging, and list of things to print
  def bug(level, [label: label_only]), do: if( RunState.get_verbosity() >= level, do: IO.puts(label_only))
  def bug(level, stuff_to_debug),      do: if( RunState.get_verbosity() >= level, do: IO.inspect(stuff_to_debug))

  def post_process(nil), do: {:ok}
  def post_process(step) do
    bug(2, [label: "post_process", step: step])

    {:ok} = optional_read_stdin_input(step)

    # AI Object Extract. Take the input and store it as an object
    cond do
      step.method == :ai_object_extract -> AIObjectExtract.object_extract_post_process(step)
      step.method == :ai_codeblock_extract -> AIObjectExtract.codeblock_extract_post_process(step)
      true -> {:ok}
    end
  end

  # Execute the step, catch it's output, and if it is not :halt, call the next step
  def execute(pidge_ast, step, index) do
    # start with the step at index, and keep going until we get a :halt
    case run_step(pidge_ast, step, index) do
      {:halt, cli_prompt} ->
        IO.puts("Runtime Finshed.\n\n#{cli_prompt}")
        {:halt}
      {:halt} -> {:halt}
      {:error, reason} ->
        {:error, reason}
      {:next} ->
        # Check to see if we are at the end
        if index == length(pidge_ast) - 1 do
          {:last}
        else
          # Run the next step
          execute(pidge_ast, pidge_ast |> Enum.at(index + 1), index + 1)
        end
    end
  end

  # Run the step, and return the result
  def run_step(pidge_ast, step, index) do
    bug(2, [label: "run_step", step: step])

    with 1 <- 1,
      # Depending on the input options, it will need to read input from stdin
      {:ok} <- optional_read_stdin_input(step),
      # Validate the step, and the options
      {:ok} <- validate_step(step),
      # Run the step
      {:next} <- apply(__MODULE__, step.method, [pidge_ast, step, index])
    do
      {:next}
    else
      {:halt} -> {:halt}
      {:error, reason} -> {:error, reason}
      error -> {:error, "Error running step: #{inspect(error)}"}
    end
  end

  def validate_step(step) do
    cond do
      !Enum.member?(@allowed_methods, step.method) ->
        bug(2, [label: "validate_step 1", step: step])
        {:error, "Method #{step.method} is not allowed"}
      Map.has_key?(step.params, :human_input) && (RunState.get_opt(:human_input) == nil || RunState.get_opt(:human_input) == "-") ->
        bug(2, [label: "validate_step 2", step: step])
        {:error, "Human input required for step: #{step.id} / #{step.method}"}
      true -> {:ok}
    end
  end

  def optional_read_stdin_input(step) do
    # If the step requires input, read it from stdin
    case Enum.member?(@input_required_methods, step.method) do
      true ->
        # If the input is not provided, then read stdin
        case RunState.get_opt(:input) do
          nil ->
            # If input is provided, read from stdin
            IO.puts("Reading stdin input for step: #{step.id} / #{step.method}")
            input = IO.read(:stdio, :all)
            RunState.set_opt(:input, input)
            {:ok}
          _ -> {:ok}
        end
      false -> {:ok}
    end
  end

  def context_create_conversation(_, %{params: %{ conversation_id: _conversation_id }}, _) do
    {:next}
  end

  def ai_prompt(pidge_ast, %{id: id, method: method, params: %{ prompt: prompt, conversation_id: conv}}, index) do
    case RunState.get_opt(:session) do
      nil ->
        with {:ok, message} <- compile_template(prompt),
              {:ok} <- push_to_api(conv, message) do
          next_command = get_next_command_to_run(pidge_ast, index, id)
          cli_prompt = "Your Message has been pushed to the #{conv} conversation.  Please go to that window and submit now.\n\nAfer submitting, run the following (copied to clipboard):\n\n    #{next_command}\n\nThen it will pause for input.  Paste in the response from the AI at that point.  When you are done, type enter, and then hit ctrl-d to continue."
          push_next_command_to_clipboard(next_command)
          {:halt, cli_prompt}
        else
          error -> {:error, "Error in #{method}: #{inspect(error)}"}
        end

      _ ->
        with {:ok, message} <- compile_template(prompt),
              {:ok, response} <- push_to_api_and_wait_for_response(pidge_ast, index, id, conv, message) do
          {opts,args,human_input_args,human_input_mode} = get_next_command_args_to_run(pidge_ast, index, id)
          input = response["body"]
          bug(3, [human_input_mode: human_input_mode])
          bug(3, [response: response])
          human_input_args =
            case {human_input_mode,response} do
              {:optional, %{"human_input" => human_input}} -> [human_input: human_input]
              _ -> human_input_args
            end
          bug(3, [human_input_args: human_input_args])

          cmd = get_next_command_to_run(pidge_ast, index, id)
          IO.puts "\n\nAuto-running next command: #{cmd} --input RESPONSE-BODY\n\n"
          next_command = args ++ human_input_args ++ ["--session",RunState.get_opt(:session), "--input", input]

          # Save the next command to run in release/next_command.txt
          File.write!("release/next_command.exs", inspect(next_command, limit: :infinity))

          base_pidge_ast = RunState.get_opt(:base_pidge_ast)
          RunState.reset_for_new_run()
          Enum.each(opts ++ human_input_args, fn {key, value} -> RunState.set_opt(key, value) end)
          bug(4, [label: "next_command_opts", opts: RunState.get_opts()])
          private__run(base_pidge_ast)
          System.halt(0)
        else
          error -> {:error, "Error in #{method}: #{inspect(error)}"}
        end
    end
  end

  def continue(_args) do
    # Read in an eval the next command to run
    next_command_txt = File.read!("release/next_command.exs")
    {[_|_] = next_command, []} = Code.eval_string(next_command_txt)
    run(next_command)
  end

  # behaves the same as ai_prompt, but @input_required_methods is true
  def ai_pipethru(pidge_ast, step, index), do: ai_prompt(pidge_ast, step, index)
  # behaves the same as ai_prompt, but has post_process
  def ai_object_extract(pidge_ast, step, index), do: ai_prompt(pidge_ast, step, index)
  # behaves the same as ai_prompt, but has post_process
  def ai_codeblock_extract(pidge_ast, step, index), do: ai_prompt(pidge_ast, step, index)

  def store_object(_, %{params: %{ object_name: object_name }}, _) do
    CallStack.set_variable(object_name, RunState.get_opt(:input))
    {:next}
  end

  def store_simple_value(_, %{params: %{ object_name: object_name, value: value }}, _) do
    CallStack.set_variable(object_name, value)
    {:next}
  end

  def clone_object(_, %{params: %{ clone_from_object_name: clone_from_object_name, object_name: object_name }}, _) do
    CallStack.clone_variable(clone_from_object_name, object_name)
    {:next}
  end

  def pipe_from_variable(_, %{params: %{ variable: variable }}, _) do
    RunState.set_opt(:input, CallStack.get_variable(variable))
    {:next}
  end

  def merge_into_object(_, %{params: %{ object_name: merge_into_object_name, clone_from_object_name: clone_from_object_name }}, _) do
    CallStack.merge_into_variable(clone_from_object_name, merge_into_object_name)
    {:next}
  end

  def foreach(pidge_ast, %{params: %{sub_pidge_ast: sub_pidge_ast}} = foreach_step, ast_index) do
    # If we just finished the commands for a loop, this func will be re-called, passing an opt on what the next loop index should be
    #   This can also be set by a prior find_step
    foreach_loop_index =
      case RunState.get_meta_key(:foreach_loop_index) do
        nil -> 0
        x -> x
      end

    # If we are restarting from the middle of our loop, find the command number mid-AST to start from (signalled by prior find_step)
    {sub_step, sub_ast_index, last_step} =
      case RunState.get_meta_key(:sub_from_step) do
        nil -> {Enum.at(sub_pidge_ast,0), 0, nil}
        sub_from_step ->
          RunState.set_opt(:from_step, sub_from_step)
          case find_step(sub_pidge_ast) do
            {:ok, last_step, sub_step, sub_ast_index} -> {sub_step, sub_ast_index, last_step}
            _ -> raise "Error in foreach: could not find step #{inspect(sub_from_step)}"
          end
      end
    bug(2, [label: "foreach #{foreach_step.seq} settings", foreach_loop_index: foreach_loop_index, sub_ast_index: sub_ast_index])


    # Enter a closure, to keep sub-variables private
    #  This also reads in the current loop item into scope
    case enter_foreach_closure(foreach_loop_index, foreach_step) do
      # OK, we are in a closure, and loop vars are loaded, now start executing commands
      {:ok, _closure_state} ->
        # Run post_process on the last_step if it is not nil
        post_process(last_step)

        bug(3, [label: "foreach #{foreach_step.seq} entered closure"])
        case execute(sub_pidge_ast, sub_step, sub_ast_index) do
          # execute has told us it finshed the last command in the foreach block
          {:last} ->
            # So increment to the next loop item and call it again
            bug(2, [label: "foreach #{foreach_step.seq}", moving_to_next_index: foreach_loop_index + 1])
            RunState.set_meta_key(:foreach_loop_index, foreach_loop_index + 1)
            CallStack.leave_closure()
            foreach(pidge_ast, foreach_step, ast_index)

          # Otherwise, return whatever it returns as our step return
          {_, _} = x -> x

          error ->
            {:error, "Error in foreach: #{inspect(error)}"}
        end

      # We have finished looping thru the foreach'd list
      {:last} ->
        bug(3, [label: "foreach #{foreach_step.seq} ended"])
        # So effectively our foreach function has completely concluded, say Next!
        {:next}
    end
  end

  def enter_foreach_closure(foreach_loop_index, %{seq: seq, params: %{
    loop_on_variable_name: loop_on_variable_name,
    instance_variable_name: instance_variable_name,
    iter_variable_name: iter_variable_name,
    }}) do
    # Get the list to iterate on
    state = CallStack.get_complete_variable_namespace()
    list = state |> get_nested_key(loop_on_variable_name, nil)
    bug(2, label: "foreach looped list", list: list)
    bug(5, label: "foreach loop", state: state)

    # If no list then raise
    case list do
      nil -> raise "foreach looped list is nil: #{inspect(loop_on_variable_name)}"
      ""<>_ -> raise "foreach looped list is a string: #{inspect(loop_on_variable_name)}: #{inspect(list)}"
      _ -> nil
    end

    # If the list is empty, or foreach_loop_index is past the end, return :last
    bug(4, label: "foreach loop stats", foreach_loop_index: foreach_loop_index, list_count: Enum.count(list))
    bug(4, label: "END?", test: (foreach_loop_index > (Enum.count(list) - 1)))
    if foreach_loop_index > (Enum.count(list) - 1) do
      bug(4, label: "END", test: (foreach_loop_index > (Enum.count(list) - 1)))
      {:last}
    # Otherwise, set the instance variable to the Nth item in the list
    else
      closure_state =
        %{}
        |> Map.put(instance_variable_name, Enum.at(list, foreach_loop_index))
        |> Map.put(iter_variable_name, foreach_loop_index)
      {:ok, CallStack.enter_closure(closure_state, :foreach, seq, foreach_loop_index) }
    end
  end

  def if(_pidge_ast, %{params: %{expression: expression_ast, sub_pidge_ast: sub_pidge_ast}} = if_step, _ast_index) do
    # If we are restarting from the middle of our loop, find the command number mid-AST to start from (signalled by prior find_step)
    direction =
      case RunState.get_meta_key(:sub_from_step) do
        nil ->
          # Generate an AST loading the state in and evaluating the expression
          # state = CallStack.get_complete_variable_namespace()
          # bug(5, [label: "if expr state", state: state])
          # sets = state |> Enum.map(fn {k,v} ->
          #   {:=, [line: 1], [
          #     {String.to_atom(k), [line: 1], nil},
          #     Code.string_to_quoted!(inspect(v, limit: :infinity))
          #     ]}
          # end)
          # expr_ast = {:__block__, [], sets ++ [expression_ast]}
          expr_ast = {:__block__, [], [expression_ast]}
          # bug(5, [label: "if expr ast", expr_ast: expr_ast])
          {return, _} = Code.eval_quoted(expr_ast, [])

          if return do
            {Enum.at(sub_pidge_ast,0), 0, nil}
          else
            {:if_expression_false}
          end

        # If you are restarting from some step inside our if block, don't re-evaluate the expression
        sub_from_step ->
          RunState.set_opt(:from_step, sub_from_step)
          case find_step(sub_pidge_ast) do
            {:ok, last_step, sub_step, sub_ast_index} -> {sub_step, sub_ast_index, last_step}
            _ -> raise "Error in if: could not find step #{inspect(sub_from_step)}"
          end
      end

    case direction do
      {sub_step,sub_ast_index,last_step} ->
        # Run post_process on the last_step if it is not nil
        post_process(last_step)

        bug(2, [label: "if #{if_step.seq} settings", sub_ast_index: sub_ast_index])
        CallStack.enter_closure(%{}, :if, sub_step.seq, nil)
        case execute(sub_pidge_ast, sub_step, sub_ast_index) do
          # execute has told us it finshed the last command in the if block
          {:last} ->
            CallStack.leave_closure()
            # So effectively our if function has completely concluded, say Next!
            {:next}

          # Otherwise, return whatever it returns as our step return
          {_, _} = x -> x

          error ->
            {:error, "Error in if: #{inspect(error)}"}
        end

      {:if_expression_false} ->
        # The expression evaluated to false, so skip the if block
        {:next}
    end
  end


  def case(_pidge_ast, %{params: %{expression: expression_ast, cases: cases}} = case_step, _ast_index) do

    # If we are restarting from the middle of our loop, find the command number mid-AST to start from (signalled by prior find_step)
    direction =
      case RunState.get_meta_key(:sub_from_step) do
        nil ->
          expr_ast = {:__block__, [], [expression_ast]}
          bug(5, [label: "case expr ast", expr_ast: expr_ast])
          {return, _} = Code.eval_quoted(expr_ast, [])

          {matched_case_ast, case_expression_index} =
            cases
            |> Enum.with_index()
            |> Enum.reduce({:no_match}, fn {case,i}, acc ->
              case {acc, case.case_expression} do
                {{:no_match},^return} -> {case.sub_pidge_ast,i}
                _ -> acc
              end
            end)

          case matched_case_ast do
            {:no_match} -> {:case_expression_no_match}
            _ -> {matched_case_ast, Enum.at(matched_case_ast,0), 0, case_expression_index, nil}
          end

        # If you are restarting from some step inside our case block, don't re-evaluate the expression
        sub_from_step ->
          case_expression_index = RunState.get_meta_key(:case_expression_index)
          sub_pidge_ast = Enum.at(cases, case_expression_index)

          RunState.set_opt(:from_step, sub_from_step)
          case find_step(sub_pidge_ast) do
            {:ok, last_step, sub_step, sub_ast_index} -> {sub_pidge_ast, sub_step, sub_ast_index, case_expression_index, last_step}
            _ -> raise "Error in case: could not find step #{inspect(sub_from_step)}"
          end
      end

    case direction do
      {sub_pidge_ast,sub_step,sub_ast_index,case_expression_index, last_step} ->
        # Run post_process on the last_step if it is not nil
        post_process(last_step)

        bug(2, [label: "case #{case_step.seq} settings", sub_ast_index: sub_ast_index])
        CallStack.enter_closure(%{}, :case, sub_step.seq, case_expression_index)
        case execute(sub_pidge_ast, sub_step, sub_ast_index) do
          # execute has told us it finshed the last command in the case block
          {:last} ->
            CallStack.leave_closure()
            # So effectively our case function has completely concluded, say Next!
            {:next}

          # Otherwise, return whatever it returns as our step return
          {_, _} = x -> x

          error ->
            {:error, "Error in case: #{inspect(error)}"}
        end

      {:case_expression_no_match} ->
        # The expression evaluated to false, so skip the case block
        {:next}
    end
  end

  def local_function_call(_pidge_ast, %{params: %{
    alias_path: alias_path,
    function_name: function_name,
    args: args,
    }}, _ast_index) do
    evaluated_args = Enum.map(args, fn arg ->
      case arg do
        [_|_] -> CallStack.get_variable(arg)
        _ -> arg
      end
    end)

    bug(2, [label: "local_function_call", alias_path: alias_path, function_name: function_name, args: args, evaluated_args: evaluated_args])
    result = LocalFunction.function_call(alias_path, function_name, evaluated_args)
    bug(2, [label: "local_function_call", result: result])
    RunState.set_opt(:input, result)
    bug(5, [input_with_result_in_it: RunState.get_opt(:input)])
    {:next}
  end

  def get_next_command_to_run(pidge_ast, index, from_id) do
    {_opts,args,_human_input_args,human_input_mode} = get_next_command_args_to_run(pidge_ast, index, from_id)
    bug(4,[get_next_command_to_run: args])
    human_input_args =
      case human_input_mode do
        :required -> ["--human-input", "your input here"]
        :optional -> ["--human-input", "-"]
        _ -> []
      end

    full_args = ["pidge", "run"] ++ args ++ human_input_args
    bug(4,[full_args: full_args])
    full_args
    |> Enum.map(fn arg -> escape_shell_arg_basic(arg) end)
    |> Enum.join(" ")
  end

  # Note, this is quick and dirty, and will go away.  Do not use on inputs you don't trust (from user input)
  def escape_shell_arg_basic(arg) do
    cond do
      String.contains?(arg,"[") -> "\"#{arg}\""
      String.contains?(arg," ") -> "\"#{arg}\""
      true -> arg
    end
  end

  def get_next_command_args_to_run(pidge_ast, index, from_id) do
     # If the next blocking step has human_input or optional_human_input, add a human-input flag
     {human_input_args, human_input_mode} =
      case next_blocking_step(pidge_ast, index+1) do
        {:last} -> {[],:none}
        {:ok, %{params: %{human_input: _}}} -> {[human_input: "your input here"],:required}
        {:ok, %{params: %{optional_human_input: _}}} -> {[human_input: "-"],:optional}
        _ -> {[],:none}
      end

    # "echo \"{}\" | pidge run --from-step \"#{get_from_step(from_id)}\"#{human_input_args}"
    from_step_id = get_from_step(from_id)
    {[from_step: from_step_id], ["--from-step", from_step_id], human_input_args, human_input_mode}
  end

  def get_from_step(from_id) do
    stack_address = CallStack.get_stack_address(:list)

    case stack_address do
      [] -> "#{from_id}"
      _ -> "#{Enum.join(stack_address, ".")}.#{from_id}"
    end
  end

  def push_next_command_to_clipboard(next_command) do
    bug(2, [label: "push_next_command_to_clipboard", next_command: next_command])
    case System.cmd("bash", ["-c","echo '#{next_command}' | pbcopy"]) do
      {"", 0} -> {:next}
      {:error, reason} -> {:error, "Error pushing next command to clipboard: #{inspect(reason)}"}
    end
  end

  def compile_template(prompt) do
    state = CallStack.get_complete_variable_namespace()

    keys_to_add_from_opts = [:input, :human_input, :optional_human_input]
    # Add the keys if they are present
    state = Enum.reduce(keys_to_add_from_opts, state, fn key, state ->
      case RunState.get_opt(key) do
        nil -> state
        value -> Map.put(state, to_string(key), value)
      end
    end)
    bug(5, [label: "compile_template", state: state])

    # Read in the template file from /release/prompts
    template = File.read!("release/prompts/#{prompt}.pjt")
    bug(3, [label: "compile_template", template: template])

    # Use Solid to parse the template
    with(
      {:ok, template} <- Solid.parse(template),
      [_|_] = rendered <- Solid.render(template, state),
      content when is_binary(content) <- rendered |> to_string()
    ) do
      bug(3, [label: "compile_template", compiled_content: content])
      {:ok, content}
    else
      error ->
        {:error, "Error compiling template: #{inspect(error)}"}
    end
  end

  def read_ast() do
    # bug(1, [label: "Reading AST..."])
    # Read and evaluate release/main.pc with a with() error handling
    with {:ok, contents} <- File.read("release/main.pjc"),
         {[%{} | _] = pidge_ast, []} <- Code.eval_string(contents) do
      # bug(3, [ast_content: pidge_ast])
      {:ok, pidge_ast}
    else
      {:error, reason} ->
        {:error, "Error reading main.pjc: #{inspect(reason)}"}
      error ->
        IO.puts("Unknown error reading AST: #{inspect(error)}")
        System.halt(1)
    end
  end

  def find_step(pidge_ast) do

    # Remove the :sub_from_step opt key if it exists
    RunState.delete_meta_key(:sub_from_step)

    # if step is provided, find it in the pidge file, otherwise we start at the beginning
    cond do
      RunState.get_opt(:jump_to_step) ->
        # the :id on each pidge entry is the step name
        match = pidge_ast |> Enum.with_index() |> Enum.find(&(elem(&1,0).id == RunState.get_opt(:jump_to_step)))
        if match == nil do
          {:error, "Step not found: #{RunState.get_opt(:jump_to_step)}"}
        else
          {step, index} = match
          {:ok, nil, step, index}
        end

      RunState.get_opt(:from_step) ->
        # Check for steps that start with "foreach-00003[2]." and enter closure re-calling find_step
        case Regex.run(~r/^(foreach|case)-(\d+)\[(\d+)\]\.(.+)$/, RunState.get_opt(:from_step)) do
          [_,"foreach",seq,foreach_loop_index,sub_from_step] ->
            bug(4, [label: "find_step", sub_from_step: sub_from_step, seq: seq, foreach_loop_index: foreach_loop_index])
            # Get the step with the :seq key that matches
            # Our goal here: we need to kick the index to the foreach, then, set :sub_from_step, so when that function runs, it can correctly find the step its on within the loop
            match = pidge_ast |> Enum.with_index() |> Enum.find(&(elem(&1,0).seq == seq))
            RunState.set_meta_key(:sub_from_step, sub_from_step)
            RunState.set_meta_key(:foreach_loop_index, String.to_integer(foreach_loop_index))
            if match == nil do
              {:error, "Foreach Step not found: #{RunState.get_opt(:from_step)}"}
            else
              {step, index} = match
              RunState.set_meta_key(:sub_from_step, sub_from_step)
              {:ok, nil, step, index}
            end

          [_,"case",seq,case_expression_index,sub_from_step] ->
            bug(4, [label: "find_step", sub_from_step: sub_from_step, seq: seq, case_expression_index: case_expression_index])
            # Get the step with the :seq key that matches
            # Our goal here: we need to kick the index to the case, then, set :sub_from_step, so when that function runs, it can correctly find the step its on within the expression
            match = pidge_ast |> Enum.with_index() |> Enum.find(&(elem(&1,0).seq == seq))
            RunState.set_meta_key(:sub_from_step, sub_from_step)
            RunState.set_meta_key(:case_expression_index, String.to_integer(case_expression_index))
            if match == nil do
              {:error, "Case Step not found: #{RunState.get_opt(:from_step)}"}
            else
              {step, index} = match
              RunState.set_meta_key(:sub_from_step, sub_from_step)
              {:ok, nil, step, index}
            end

          no_match ->
            bug(5, [label: "find_step no_match", no_match: no_match])

            # the :id on each pidge entry is the step name
            match = pidge_ast |> Enum.with_index() |> Enum.find(fn {step, _} -> step.id == RunState.get_opt(:from_step) end)
            if match == nil do
              {:error, "Step not found: #{RunState.get_opt(:from_step)}"}
            else
              {last_step, index} = match
              # If this is the last step in the AST, return :last
              cond do
                index == length(pidge_ast) - 1 ->
                  {:last, last_step, nil, nil}
                true ->
                  {:ok, last_step, Enum.at(pidge_ast, index + 1), index + 1}
              end
            end
        end

      true -> {:ok, nil, Enum.at(pidge_ast, 0), 0}
    end
  end

  def next_blocking_step(pidge_ast, index) do
    # If the method of the current ste is in @blocking_methods, return this step
    step =
      cond do
        Enum.member?(@blocking_methods, Enum.at(pidge_ast, index).method) ->
          Enum.at(pidge_ast, index)
        Enum.at(pidge_ast, index + 1) == nil ->
          :last
        true -> next_blocking_step(pidge_ast, index + 1)
      end

    # If the step is not found, error out
    case step do
      :last -> {:last}
      _ -> {:ok, step}
    end
  end

  def push_to_api(conv,message) do
    # Prepare the data
    data = %{ "message" => message }

    # Send a POST request
    case HTTPoison.post("https://abandoned-scared-halibut.gigalixirapp.com/api/#{conv}", Poison.encode!(data), [{"Content-Type", "application/json"}]) do
      {:ok, output} ->
        bug(2, [label: "Pushed to API", output: output])
        {:ok}
      {:error, error} -> {:error, error}
    end
  end

  def push_to_api_and_wait_for_response(pidge_ast, index, from_id,conv,message) do
    {_opts,_args,_human_input_args,human_input_mode} = get_next_command_args_to_run(pidge_ast, index, from_id)

    data = %{ "message" => message, "human_input_mode" => to_string(human_input_mode) }

    channel = "session:#{conv}-#{RunState.get_opt(:session)}" |> String.downcase()
    IO.puts("Pushing message to web browser on channel: #{channel}")

    case Pidge.WebClient.send_and_wait_for_response(data, channel) do
      {:ok, response_data} ->
        IO.puts("Response recieved: #{inspect(response_data, limit: :infinity) |> String.length()} bytes")
        bug(2, [response_data: response_data, label: "Response Data"])
        {:ok, response_data}
      {:error, reason} ->
        bug(2, [reason: reason, label: "Error"])
        {:error, reason}
      error ->
        bug(2, [error: error, label: "Unknown error"])
        {:error, "Unknown error"}
    end
  end
end
