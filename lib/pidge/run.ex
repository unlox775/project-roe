defmodule Pidge.Run do
  @moduledoc """
  A module to execute steps in a Pidge script.
  """

  alias Pidge.State
  alias Pidge.Run.AIObjectExtract

  # @transit_tmp_dir "/tmp/roe/transit"
  @input_required_methods [:ai_pipethru, :store_object, :ai_object_extract]
  @blocking_methods [:ai_prompt, :ai_pipethru, :ai_object_extract]
  @allowed_methods [:context_create_conversation, :ai_prompt, :ai_pipethru, :ai_object_extract, :store_object, :clone_object, :merge_into_object, :foreach]

  def run(args) do
    opts = parse_opts(args)

    with(
      # Read the step from the pjc file
      {:ok, pidge_ast} <- read_ast(opts),
      # Find the step to start at
      {:ok, opts, last_step, step, index} <- find_step(pidge_ast, opts),
      # Run post process on last step if needed
      {:ok, opts} <- post_process(last_step, opts),
      # Execute the step
      {:halt, _} <- execute(pidge_ast, step, index, opts)
    ) do
      System.halt(0)
    else
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
        System.halt(1)
      {:last} ->
        IO.puts("Excution complete.")
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
        bug(opts,2,[verbosity_level: verbosity])
        bug(opts,3,[opts: opts])

        opts

    error ->
        IO.puts("Options Read Error: #{inspect(error)}")
        System.halt(1)
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


  # debug function passed the opts, level of debugging, and list of things to print
  def bug(opts, level, [label: label_only]) do
    # if the verbosity is greater than or equal to the level of debugging
    if opts[:verbosity] >= level do
      # print the label
      IO.puts(label_only)
    end
  end
  def bug(opts, level, stuff_to_debug) do
    # if the verbosity is greater than or equal to the level of debugging
    if opts[:verbosity] >= level do
      # print the list of things to print
      IO.inspect(stuff_to_debug)
    end
  end

  def post_process(nil, opts), do: {:ok, opts}
  def post_process(step, opts) do
    bug(opts, 2, [label: "post_process", step: step])

    opts = optional_read_stdin_input(opts, step)

    # AI Object Extract. Take the input and store it as an object
    if step.method == :ai_object_extract do
      AIObjectExtract.post_process(step, opts)
    else
      {:ok, opts}
    end
  end

  # Execute the step, catch it's output, and if it is not :halt, call the next step
  def execute(pidge_ast, step, index, opts) do
    # start with the step at index, and keep going until we get a :halt
    case run_step(pidge_ast, step, index, opts) do
      {:halt, opts} ->
        cond do
          opts[:cli_prompt] -> IO.puts("Runtime Finshed.\n\n#{opts[:cli_prompt]}")
          true -> nil
        end
        {:halt, opts}
      {:error, reason} ->
        {:error, reason}
      {:next, opts} ->
        # Check to see if we are at the end
        if index == length(pidge_ast) - 1 do
          {:last, opts}
        else
          # Run the next step
          execute(pidge_ast, pidge_ast |> Enum.at(index + 1), index + 1, opts)
        end
    end
  end

  # Run the step, and return the result
  def run_step(pidge_ast, step, index, opts) do
    bug(opts, 2, [label: "run_step", step: step])
    # Depending on the opts, it will need to read input from stdin
    opts = optional_read_stdin_input(opts, step)

    # Validate the step, and the options
    with 1 <- 1,
      {:ok} <- validate_step(step, opts),
      # Run the step
      {:next, opts} <- apply(__MODULE__, step.method, [pidge_ast, step, index, opts])
    do
      {:next, opts}
    else
      {:halt, opts} ->
        {:halt, opts}
      {:error, reason} ->
        {:error, reason}
      error ->
        {:error, "Error running step: #{inspect(error)}"}
    end
  end

  def validate_step(step, opts) do
    cond do
      !Enum.member?(@allowed_methods, step.method) ->
        bug(opts, 2, [label: "validate_step 1", step: step])
        {:error, "Method #{step.method} is not allowed"}
      Map.has_key?(step.params, :human_input) && (! Keyword.has_key?(opts, :human_input) || opts[:human_input == "-"]) ->
        bug(opts, 2, [label: "validate_step 2", step: step])
        {:error, "Human input required for step: #{step.id} / #{step.method}"}
      true -> {:ok}
    end
  end

  def optional_read_stdin_input(opts, step) do
    # If the step requires input, read it from stdin
    if Enum.member?(@input_required_methods, step.method) do
      # If the input is provided, use it
      if opts[:input] do
        opts
      # Otherwise, read it from stdin
      else
        # If input is provided, read from stdin
        IO.puts("Reading stdin input for step: #{step.id} / #{step.method}")
        input = IO.read(:stdio, :all)
        opts ++ [input: input]
      end
    # If the step does not require input, just return the opts
    else
      opts
    end
  end

  def context_create_conversation(_, %{params: %{ conversation_id: _conversation_id }}, _, opts) do
    {:next, opts}
  end

  def ai_prompt(pidge_ast, %{id: id, method: method, params: %{ prompt: prompt, conversation_id: conv}}, index, opts) do
    case opts[:session] do
      nil ->
        with {:ok, message} <- compile_template(prompt, opts),
              {:ok} <- push_to_api(conv, message, opts) do
          next_command = get_next_command_to_run(pidge_ast, index, id, opts)
          cli_prompt = "Your Message has been pushed to the #{conv} conversation.  Please go to that window and submit now.\n\nAfer submitting, run the following (copied to clipboard):\n\n    #{next_command}\n\nThen it will pause for input.  Paste in the response from the AI at that point.  When you are done, type enter, and then hit ctrl-d to continue."
          push_next_command_to_clipboard(next_command, opts)
          {:halt, opts ++ [cli_prompt: cli_prompt]}
        else
          error -> {:error, "Error in #{method}: #{inspect(error)}"}
        end

      _ ->
        with {:ok, message} <- compile_template(prompt, opts),
              {:ok, response} <- push_to_api_and_wait_for_response(pidge_ast, index, id, conv, message, opts) do
          {args,human_input_args,human_input_mode} = get_next_command_args_to_run(pidge_ast, index, id, opts)
          input = response["body"]
          IO.inspect(human_input_mode, label: "human_input_mode")
          IO.inspect(response, label: "response")
          human_input_args =
            case {human_input_mode,response} do
              {:optional, %{"human_input" => human_input}} -> ["--human-input", human_input]
              _ -> human_input_args
            end
          IO.inspect(human_input_args, label: "human_input_args")

          cmd = get_next_command_to_run(pidge_ast, index, id, opts)
          IO.puts "\n\nAuto-running next command: #{cmd} --input RESPONSE-BODY\n\n"
          run(["-vvv"] ++ args ++ human_input_args ++ ["--session",opts[:session],"--input",input])
          System.halt(0)
        else
          error -> {:error, "Error in #{method}: #{inspect(error)}"}
        end
    end
  end

  # behaves the same as ai_prompt, but @input_required_methods is true
  def ai_pipethru(pidge_ast, step, index, opts), do: ai_prompt(pidge_ast, step, index, opts)
  # behaves the same as ai_prompt, but has post_process
  def ai_object_extract(pidge_ast, step, index, opts), do: ai_prompt(pidge_ast, step, index, opts)

  def store_object(_, %{params: %{ object_name: object_name }}, _, opts) do
    State.store_object(opts[:input], object_name)
    {:next, opts}
  end

  def clone_object(_, %{params: %{ clone_from_object_name: clone_from_object_name, object_name: object_name }}, _, opts) do
    State.clone_object(clone_from_object_name, object_name)
    {:next, opts}
  end

  def merge_into_object(_, %{params: %{ object_name: object_name }}, _, opts) do
    State.merge_into_object(opts[:input], object_name)
    {:next, opts}
  end

  def foreach(pidge_ast, %{params: %{sub_pidge_ast: sub_pidge_ast}} = foreach_step, ast_index, opts) do
    # If we just finished the commands for a loop, this func will be re-called, passing an opt on what the next loop index should be
    #   This can also be set by a prior find_step
    foreach_loop_index =
      case opts[:foreach_loop_index] do
        nil -> 0
        x -> x
      end

    # If we are restarting from the middle of our loop, find the command number mid-AST to start from (signalled by prior find_step)
    {sub_step,sub_ast_index,opts} =
      case opts[:sub_from_step] do
        nil -> {Enum.at(sub_pidge_ast,0), 0, opts}
        sub_from_step ->
          opts = Keyword.put(opts, :from_step, sub_from_step)
          case find_step(sub_pidge_ast, opts) do
            {:last, opts, _, _, _} -> {:next, leave_closure(opts)}
            {:ok, opts, _, sub_step, sub_ast_index} -> {sub_step, sub_ast_index, opts}
          end
      end
    bug(opts, 2, [label: "foreach #{foreach_step.seq} settings", foreach_loop_index: foreach_loop_index, sub_ast_index: sub_ast_index])


    # Enter a closure, to keep sub-variables private
    #  This also reads in the current loop item into scope
    case enter_foreach_closure(opts, foreach_loop_index, foreach_step) do
      # OK, we are in a closure, and loop vars are loaded, now start executing commands
      {:ok, opts} ->
        bug(opts, 3, [label: "foreach #{foreach_step.seq} entered closure"])
        case execute(sub_pidge_ast, sub_step, sub_ast_index, opts) do
          # execute has told us it finshed the last command in the foreach block
          {:last, opts} ->
            # So increment to the next loop item and call it again
            bug(opts, 2, [label: "foreach #{foreach_step.seq}", moving_to_next_index: foreach_loop_index + 1])
            opts = Keyword.put(opts, :foreach_loop_index, foreach_loop_index + 1)
            opts = leave_closure(opts)
            foreach(pidge_ast, foreach_step, ast_index, opts)

          # Otherwise, return whatever it returns as our step return
          {_, _} = x -> x

          error ->
            {:error, "Error in foreach: #{inspect(error)}"}
        end

      # We have finished looping thru the foreach'd list
      {:last, opts} ->
        bug(opts, 3, [label: "foreach #{foreach_step.seq} ended"])
        # So effectively our foreach function has completely concluded, say Next!
        {:next, opts}
    end
  end

  def enter_foreach_closure(opts, foreach_loop_index, %{seq: seq, params: %{
    loop_on_variable_name: loop_on_variable_name,
    instance_variable_name: instance_variable_name,
    iter_variable_name: iter_variable_name,
    }}) do
    # Get the list to iterate on
    state = State.get_current_state()
    list = state |> get_nested_key(loop_on_variable_name)
    bug(opts, 2, label: "foreach looped list", list: list)
    bug(opts, 5, label: "foreach loop", state: state)

    # If no list then raise
    case list do
      nil -> raise "foreach looped list is nil: #{inspect(loop_on_variable_name)}"
      ""<>_ -> raise "foreach looped list is a string: #{inspect(loop_on_variable_name)}: #{inspect(list)}"
      _ -> nil
    end

    # If the list is empty, or foreach_loop_index is past the end, return :last
    bug(opts, 4, label: "foreach loop stats", foreach_loop_index: foreach_loop_index, list_count: Enum.count(list))
    bug(opts, 4, label: "END?", test: (foreach_loop_index > (Enum.count(list) - 1)))
    if foreach_loop_index > (Enum.count(list) - 1) do
      bug(opts, 4, label: "END", test: (foreach_loop_index > (Enum.count(list) - 1)))
      {:last, opts}
    # Otherwise, set the instance variable to the Nth item in the list
    else
      closure_state =
        %{
          __foreach_loop_index: foreach_loop_index,
          __foreach_seq: seq,
        }
        |> Map.put(instance_variable_name, Enum.at(list, foreach_loop_index))
        |> Map.put(iter_variable_name, foreach_loop_index)
      {:ok, enter_closure(opts, closure_state) }
    end
  end

  def get_nested_key(state, keys_list) do
    Enum.reduce(keys_list, state, fn key, acc ->
      # silently handle non-existant keys as nil
      if is_map(acc) && Map.has_key?(acc, key) do
        Map.get(acc, key)
      else
        nil
      end
    end)
  end

  def enter_closure(opts, closure_state) do
    if opts[:closure_states] do
      Keyword.put(opts, :closure_states, opts[:closure_states] ++ [closure_state])
    else
      opts ++ [closure_states: [closure_state]]
    end
  end

  def leave_closure(opts) do
    # drop the last closure
    Keyword.put(opts, :closure_states, Enum.drop(opts[:closure_states], -1))
  end

  def get_next_command_to_run(pidge_ast, index, from_id, opts) do
    {args,human_input_args,_human_input_mode} = get_next_command_args_to_run(pidge_ast, index, from_id, opts)
    IO.inspect(args, label: "get_next_command_to_run")
    full_args = ["pidge", "run"] ++ args ++ human_input_args
    IO.inspect(full_args, label: "full_args")
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

  def get_next_command_args_to_run(pidge_ast, index, from_id, opts) do
     # If the next blocking step has human_input or optional_human_input, add a human-input flag
     {human_input_args, human_input_mode} =
      case next_blocking_step(pidge_ast, index+1) do
        {:last} -> {[],:none}
        {:ok, %{params: %{human_input: _}}} -> {["--human-input","your input here"],:required}
        {:ok, %{params: %{optional_human_input: _}}} -> {["--human-input","-"],:optional}
        _ -> {[],:none}
      end

    # "echo \"{}\" | pidge run --from-step \"#{get_from_step(from_id, opts)}\"#{human_input_args}"
    {["--from-step", get_from_step(from_id, opts)], human_input_args, human_input_mode}
  end

  def get_from_step(from_id, opts) do
    closure_trail_list =
      cond do
        opts[:closure_states] == nil -> []
        true ->
          opts[:closure_states]
          |> Enum.map(fn %{__foreach_loop_index: foreach_loop_index, __foreach_seq: seq} ->
            "foreach-#{seq}[#{foreach_loop_index}]"
          end)
      end

    case closure_trail_list do
      [] -> "#{from_id}"
      _ -> "#{Enum.join(closure_trail_list, ".")}.#{from_id}"
    end
  end

  def push_next_command_to_clipboard(next_command, opts) do
    bug(opts, 2, [label: "push_next_command_to_clipboard", next_command: next_command])
    case System.cmd("bash", ["-c","echo '#{next_command}' | pbcopy"]) do
      {"", 0} -> {:next}
      {:error, reason} -> {:error, "Error pushing next command to clipboard: #{inspect(reason)}"}
    end
  end

  def compile_template(prompt, opts) do
    state =
      State.get_current_state()

    # merge each of the closures into the state
    state =
      cond do
        opts[:closure_states] == nil -> state
        true ->
          Enum.reduce(opts[:closure_states], state, fn closure_state, state ->
            bug(opts, 2, [label: "compile_template", closure_state: closure_state])
            Map.merge(state, closure_state)
          end)
      end

    keys_to_add_from_opts = [:input, :human_input, :optional_human_input]
    # Add the keys if they are present
    state = Enum.reduce(keys_to_add_from_opts, state, fn key, state ->
      if Keyword.has_key?(opts, key) do
        Map.put(state, to_string(key), opts[key])
      else
        state
      end
    end)
    bug(opts, 2, [label: "compile_template", state: state])

    # Read in the template file from /release/prompts
    template = File.read!("release/prompts/#{prompt}.pjt")
    bug(opts, 3, [label: "compile_template", template: template])

    # Use Solid to parse the template
    with(
      {:ok, template} <- Solid.parse(template),
      [_|_] = rendered <- Solid.render(template, state),
      content when is_binary(content) <- rendered |> to_string()
    ) do
      bug(opts, 3, [label: "compile_template", compiled_content: content])
      {:ok, content}
    else
      error ->
        {:error, "Error compiling template: #{inspect(error)}"}
    end
  end

  def read_ast(opts) do
    bug(opts, 1, [label: "Reading AST..."])
    # Read and evaluate release/main.pc with a with() error handling
    with {:ok, contents} <- File.read("release/main.pjc"),
         {[%{} | _] = pidge_ast, []} <- Code.eval_string(contents) do
      bug(opts, 3, [ast_content: pidge_ast])
      {:ok, pidge_ast}
    else
      {:error, reason} ->
        {:error, "Error reading main.pjc: #{inspect(reason)}"}
      error ->
        IO.puts("Unknown error reading AST: #{inspect(error)}")
        System.halt(1)
    end
  end

  def find_step(pidge_ast, opts) do
    # Remove the opts[:sub_from_step] key if it exists
    opts = Keyword.delete(opts, :sub_from_step)

    # if step is provided, find it in the pidge file, otherwise we start at the beginning
    cond do
      opts[:jump_to_step] ->
        # the :id on each pidge entry is the step name
        match = pidge_ast |> Enum.with_index() |> Enum.find(&(elem(&1,0).id == opts[:jump_to_step]))
        if match == nil do
          {:error, "Step not found: #{opts[:jump_to_step]}"}
        else
          {step, index} = match
          {:ok, opts, nil, step, index}
        end

      opts[:from_step] ->
        # Check for steps that start with "foreach-00003[2]." and enter closure re-calling find_step
        case Regex.run(~r/^foreach-(\d+)\[(\d+)\]\.(.+)$/, opts[:from_step]) do
          [_,seq,foreach_loop_index,sub_from_step] ->
            bug(opts, 4, [label: "find_step", sub_from_step: sub_from_step, seq: seq, foreach_loop_index: foreach_loop_index])
            # Get the step with the :seq key that matches
            # Our goal here: we need to kick the index to the foreach, then, set :sub_from_step, so when that function runs, it can correctly find the step its on within the loop
            match = pidge_ast |> Enum.with_index() |> Enum.find(&(elem(&1,0).seq == seq))
            opts =
              opts
              |> Keyword.put(:sub_from_step, sub_from_step)
              |> Keyword.put(:foreach_loop_index, String.to_integer(foreach_loop_index))
            if match == nil do
              {:error, "Foreach Step not found: #{opts[:from_step]}"}
            else
              {step, index} = match
              {:ok, Keyword.put(opts, :sub_from_step, sub_from_step), nil, step, index}
            end

          _ ->
            # the :id on each pidge entry is the step name
            match = pidge_ast |> Enum.with_index() |> Enum.find(fn {step, _} -> step.id == opts[:from_step] end)
            if match == nil do
              {:error, "Step not found: #{opts[:from_step]}"}
            else
              {step, index} = match
              {:ok, opts, step, Enum.at(pidge_ast, index + 1), index + 1}
            end
        end

      true -> {:ok, opts, nil, Enum.at(pidge_ast, 0), 0}
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

  def push_to_api(conv,message,opts) do
    # Prepare the data
    data = %{ "message" => message }

    # Send a POST request
    case HTTPoison.post("https://abandoned-scared-halibut.gigalixirapp.com/api/#{conv}", Poison.encode!(data), [{"Content-Type", "application/json"}]) do
      {:ok, output} ->
        bug(opts, 2, [label: "Pushed to API", output: output])
        {:ok}
      {:error, error} -> {:error, error}
    end
  end

  def push_to_api_and_wait_for_response(pidge_ast, index, from_id,conv,message,opts) do
    {_args,_human_input_args,human_input_mode} = get_next_command_args_to_run(pidge_ast, index, from_id, opts)

    data = %{ "message" => message, "human_input_mode" => to_string(human_input_mode) }

    channel = "session:#{conv}-#{opts[:session]}" |> String.downcase()
    IO.inspect(channel, label: "Channel")

    case Pidge.WebClient.send_and_wait_for_response(data, channel) do
      {:ok, response_data} ->
        IO.inspect(response_data, label: "Response Data")
        {:ok, response_data}
      {:error, reason} ->
        IO.inspect(reason, label: "Error")
        {:error, reason}
      error ->
        IO.inspect(error, label: "Unknown error")
        {:error, "Unknown error"}
    end
  end
end
