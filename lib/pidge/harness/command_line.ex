defmodule Pidge.Harness.CommandLine do
  @moduledoc """
  A module to execute steps in a Pidge script.
  """

  alias Pidge.Runtime.{ SessionState, RunState }
  alias Pidge.Run

  def run(args) do
    opts = parse_opts(args)

    with 1 <- 1,
      {:ok, pidge_ast} <- __MODULE__.read_ast(),
      {:halt} <- run(opts, pidge_ast)
    do
      System.halt(0)
    else
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
        System.halt(1)
      {:last} ->
        IO.puts("Pidge Execution complete.")
        System.halt(0)
      error ->
        IO.puts("Unknown error in #{__MODULE__}.run: #{inspect(error)}")
        System.halt(1)
    end
  end

  def continue(_args) do
    # Read in an eval the next command to run
    next_command_txt = File.read!("release/next_command.exs")
    {[_|_] = opts, []} = Code.eval_string(next_command_txt)

    with 1 <- 1,
      {:ok, pidge_ast} <- __MODULE__.read_ast(),
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

    return =
      case run_loop(pidge_ast) do
        #  The engine barfed, becauase we didn't give it the input it needed
        {:error, :required_input, step} ->
          # Read input from STDIN, then try again
          __MODULE__.read_stdin_input(step)
          run_loop(pidge_ast)

        x -> x
      end

    RunState.stop(runstate_pid)
    SessionState.stop(sessionstate_pid)
    return
  end

  def run_loop(pidge_ast) do
    with 1 <- 1,
      {:send_api_message, {conv, message}, %{
        opts: next_runtime_opts,
        human_input_mode: human_input_mode
      }} <- Run.private__run(pidge_ast),
      {:ok, response} <- __MODULE__.push_to_api_and_wait_for_response(human_input_mode, conv, message)
    do
      input = response["body"]

      # cmd = get_next_command_to_run(pidge_ast, index, id)
      IO.puts "\n\nAuto-running next command: pidge run #{inspect(next_runtime_opts)} --input RESPONSE-BODY\n\n"
      next_command = next_runtime_opts ++ [input: input]

      # Save the next command to run in release/next_command.txt
      File.write!("release/next_command.exs", inspect(next_command, limit: :infinity, printable_limit: :infinity))

      RunState.reset_for_new_run()
      Enum.each(next_command, fn {key, value} -> RunState.set_opt(key, value) end)
      bug(4, [label: "next_command_opts", opts: RunState.get_opts()])
      run_loop(pidge_ast)
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

  def push_to_api_and_wait_for_response(human_input_mode, conv, message) do
    data = %{ "message" => message, "human_input_mode" => to_string(human_input_mode) }

    channel = "session:#{conv}-#{RunState.get_opt(:session)}" |> String.downcase()
    IO.puts("Pushing message to web browser on channel: #{channel}")

    case Pidge.WebClient.send_and_wait_for_response(data, channel) do
      {:ok, response_data} ->
        IO.puts("Response recieved: #{inspect(response_data, limit: :infinity, printable_limit: :infinity) |> String.length()} bytes")
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

  def print_help do
    IO.puts("""
    Usage: pidge run [OPTIONS]

    Options:
      --input              Define input for the script
      --from_step          Start from a specific step in the program
      --human_input        Provide human input for the program
      --verbose / -v       Enable verbose mode. This option can be used multiple times to increase verbosity level
      --help / -h          Display this help message

    Examples:
      pidge run --input "This is text to ask the AI.  Why is the sky blue?"
      pidge run -vv --human_input "Hello, world!"
    """)
  end

  # debug function passed level of debugging, and list of things to print
  def bug(level, [label: label_only]), do: if( RunState.get_verbosity() >= level, do: IO.puts(label_only))
  def bug(level, stuff_to_debug),      do: if( RunState.get_verbosity() >= level, do: IO.inspect(stuff_to_debug))

  def read_stdin_input(step) do
    # If input is provided, read from stdin
    IO.puts("Reading stdin input for step: #{step.id} / #{step.method}")
    input = IO.read(:stdio, :all)
    RunState.set_opt(:input, input)
    {:ok}
  end

  # Note, this is quick and dirty, and will go away.  Do not use on inputs you don't trust (from user input)
  def escape_shell_arg_basic(arg) do
    cond do
      String.contains?(arg,"[") -> "\"#{arg}\""
      String.contains?(arg," ") -> "\"#{arg}\""
      true -> arg
    end
  end
end
