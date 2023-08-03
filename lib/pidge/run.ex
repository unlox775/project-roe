defmodule Pidge.Run do
  @moduledoc """
  A module to execute steps in a Pidge script.
  """

  # @transit_tmp_dir "/tmp/roe/transit"
  @input_required_methods [:ai_pipethru]
  @blocking_methods [:ai_prompt, :ai_pipethru, :ai_object_extract]
  @allowed_methods [:context_create_conversation, :ai_prompt, :ai_pipethru, :ai_object_extract]

  def run(args) do
    opts = parse_opts(args)

    with(
      # Read the step from the pjc file
      {:ok, pidge_ast} <- read_ast(opts),
      # Find the step to start at
      {:ok, step, index} <- find_step(pidge_ast, opts),
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

        new_opts = opts ++ [verbosity: verbosity]
        bug(new_opts,2,[verbosity_level: verbosity])

        new_opts

    error ->
        IO.puts("Options Read Error: #{inspect(error)}")
        System.halt(1)
    end
  end

  def print_help do
    IO.puts("""
    Usage: ./bin/run [OPTIONS]

    Options:
      --input              Define input for the script
      --jump_to_step       Jump to a specific step in the program
      --from_step          Start from a specific step in the program
      --human_input        Provide human input for the program
      --verbose / -v       Enable verbose mode. This option can be used multiple times to increase verbosity level
      --help / -h          Display this help message

    Examples:
      ./bin/run --input "This is text to ask the AI.  Why is the sky blue?"
      ./bin/run --jump_to_step step3 --verbose
      ./bin/run -vv --human_input "Hello, world!"
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

  # Execute the step, catch it's output, and if it is not :halt, call the next step
  def execute(pidge_ast, step, index, opts) do
    # start with the step at index, and keep going until we get a :halt
    case run_step(pidge_ast, step, index, opts) do
      {:halt, opts} ->
        cond do
          opts[:cli_prompt] -> IO.puts("Runtime Finshed.\n\n#{opts[:cli_prompt]}")
          true -> nil
        end
        {:halt, "Done"}
      {:error, reason} ->
        {:error, reason}
      {:next, new_opts} ->
        execute(pidge_ast, pidge_ast |> Enum.at(index + 1), index + 1, new_opts)
    end
  end

  # Run the step, and return the result
  def run_step(pidge_ast, step, index, raw_opts) do
    bug(raw_opts, 2, [label: "run_step", step: step])
    # Depending on the opts, it will need to read input from stdin
    opts = optional_read_stdin_input(raw_opts, step)

    # Validate the step, and the options
    with 1 <- 1,
      {:ok} <- validate_step(step, opts),
      # Run the step
      {:next} <- apply(__MODULE__, step.method, [pidge_ast, step, index, opts])
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
        {:error, "Human input required for step: #{step.method}"}
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
        IO.puts("Reading stdin input for step: #{step.method}")
        input = IO.read(:stdio, :all)
        opts ++ [input: input]
      end
    # If the step does not require input, just return the opts
    else
      opts
    end
  end

  def context_create_conversation(_, %{params: %{ conversation_id: _conversation_id }}, _, _) do
    {:next}
  end

  def ai_prompt(pidge_ast, %{id: id, method: method, params: %{ prompt: prompt, conversation_id: conv}}, index, opts) do
    with {:ok, message} <- compile_template(prompt, opts),
          {:ok} <- push_to_api(conv, message, opts) do
      # If the next blocking step has human_input or optional_human_input, add a human-input flag
      human_input =
        case next_blocking_step(pidge_ast, index+1) do
          {:last} -> ""
          {:ok, %{params: %{human_input: _}}} -> " --human-input \"your input here\""
          {:ok, %{params: %{optional_human_input: _}}} -> " --human-input \"-\""
          _ -> ""
        end

      cli_prompt = "Your Message has been pushed to the #{conv} conversation.  Please go to that window and submit now.\n\nAfer submitting, run the following:\n\n    ./bin/run --from-step #{id}#{human_input}\n\nThen it will pause for input.  Paste in the response from the AI at that point.  When you are done, type enter, and then hit ctrl-d to continue."
      {:halt, opts ++ [cli_prompt: cli_prompt]}
    else
      error -> {:error, "Error in #{method}: #{inspect(error)}"}
    end
  end

  # behaves the same as ai_prompt, but @input_required_methods is true
  def ai_pipethru(pidge_ast, step, index, opts), do: ai_prompt(pidge_ast, step, index, opts)

  def compile_template(_, _opts) do
    {:ok, "This is a test"}
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
    # if step is provided, find it in the pidge file, otherwise we start at the beginning
    cond do
      opts[:jump_to_step] ->
        # the :id on each pidge entry is the step name
        match = pidge_ast |> Enum.with_index() |> Enum.find(&(Enum.at(&1,0).id == opts[:jump_to_step]))
        if match == nil do
          {:error, "Step not found: #{opts[:jump_to_step]}"}
        else
          {:ok} ++ match
        end

      opts[:from_step] ->
        # the :id on each pidge entry is the step name
        match = pidge_ast |> Enum.with_index() |> Enum.find(fn {step, _} -> step.id == opts[:from_step] end)
        if match == nil do
          {:error, "Step not found: #{opts[:from_step]}"}
        else
          {_, done_index} = match
          if Enum.at(pidge_ast, done_index + 1) == nil do
            {:last, nil}
          else
            {:ok, Enum.at(pidge_ast, done_index + 1), done_index + 1}
          end
        end

      true -> {:ok, pidge_ast |> Enum.at(0), 0}
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

    # shell_command = "./bin/send_to_#{conv}_input"
    # # Run the shell command from elixir and pipe input to it, like this, but as cleanly as possible as the message can sometimes be large and have special characters:
    # with(
    #   # Make /tmp/roe/transmit directory
    #   {:make_dir, :ok} <- {:make_dir, File.mkdir_p(@transit_tmp_dir)},
    #   # come up with a random filename
    #   filename <- Base.encode64(:crypto.strong_rand_bytes(16)),
    #   # Write the message to that file
    #   {:write_tmp_file, :ok }<- {:write_tmp_file, File.write("#{@transit_tmp_dir}/#{filename}", message)},
    #   # Call Systen.cmd, piping the message to the shell command
    #   bash_args = ["-c","cat #{@transit_tmp_dir}/#{filename} | #{shell_command}"],
    #   {output, 0} <- System.cmd("bash", bash_args)
    #   # ,
    #   # # remove the file
    #   # :ok <- File.rm("#{@transit_tmp_dir}/#{filename}")
    # ) do
    #   bug(opts, 2, [label: "Pushed to API", output: output])
    #   bug(opts, 3, [label: "Message that was pushed:", message: message])
    #   bug(opts, 4, [label: "Bash args for the command that was run:", bash_args: bash_args])
    #   bug(opts, 4, [label: "Temp Filename:", filename: "#{@transit_tmp_dir}/#{filename}"])
    #   {:ok}
    # else
    #   {:make_dir, {:error, reason}} ->
    #     {:error, "Error making directory: #{inspect(reason)}"}
    #   {:write_tmp_file, {:error, reason}} ->
    #     {:error, "Error writing to temp file: #{inspect(reason)}"}
    #   error ->
    #     {:error, "Error pushing to API: #{inspect(error)}"}
    # end
  end
end