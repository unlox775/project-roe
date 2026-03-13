defmodule Pidge.Harness.CommandLine do
  @moduledoc """
  A module to execute steps in a Pidge script.
  """

  alias Pidge.Runtime.{ SessionState, RunState }
  alias Pidge.App.Loft
  alias Pidge.FlightControl

  def run(args) do
    opts = parse_opts(args)
    opts = ensure_pipe_input_for_resume(opts)
    private__run(opts, "release")
  end

  def continue(_args) do
    # Read in an eval the next command to run
    next_command_txt = File.read!("release/next_command.exs")
    {[_|_] = opts, []} = Code.eval_string(next_command_txt)
    private__run(opts, "release")
  end

  def private__run(opts, get_from) do
    {:ok, flightcontrol_pid} = FlightControl.start_link()
    {:ok, runstate_pid} = RunState.start_link()
    RunState.init_session(opts)
    {:ok, sessionstate_pid} = SessionState.start_link(opts.session)
    {:ok, loft_pid} = Loft.start_link()

    :ok = Loft.register_app(:local, get_from)

    run_payload = {:local, :main, opts}
    bug(4, [label: "[harness] run_payload built", from_step: opts[:from_step], human_input_present: Map.has_key?(opts, :human_input), opts_keys: Map.keys(opts)])

    return =
      case run_loop(run_payload) do
        # Human-in-the-loop: output context and rejoin command, then exit
        {:required_input_callback, step, from_step} ->
          __MODULE__.print_rejoin_and_halt(step, from_step, opts)

        x -> x
      end

    Loft.stop(loft_pid)
    SessionState.stop(sessionstate_pid)
    RunState.stop(runstate_pid)
    FlightControl.stop(flightcontrol_pid)

    case return do
      {:halt} -> System.halt(0)
      {:halt_optional_input} -> System.halt(0)
      {:human_input_required} -> System.halt(0)
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

    return
  end

  defp parse_opts_debug(msg), do: IO.puts(:stderr, "[pidge:parse_opts] #{msg}")

  # When resuming with --from-step, pipe input comes from file only (never from --input).
  # We ignore --input and load from the file written when we halted.
  # If no file (e.g. --from-step bard/01 to start fresh), leave opts without input.
  defp ensure_pipe_input_for_resume(opts) do
    cond do
      is_nil(opts[:from_step]) or opts[:session] in [nil, ""] ->
        opts

      true ->
        opts = Map.delete(opts, :input)
        case read_pipe_input(opts[:session]) do
          {:ok, content} ->
            parse_opts_debug("loaded pipe input from file (#{String.length(content)} chars)")
            Map.put(opts, :input, content)

          {:error, _} ->
            opts
        end
    end
  end

  defp pipe_input_path(session) do
    s = session || "default"
    "release/#{s}_pipe_input.txt"
  end

  defp write_pipe_input(session, content) when is_binary(content) do
    path = pipe_input_path(session)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  defp write_pipe_input(_, _), do: :ok

  defp read_pipe_input(session) do
    path = pipe_input_path(session)
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, _} = err -> err
    end
  end

  def parse_opts(args) do
    parse_opts_debug("raw args (#{length(args)}): #{inspect(args, limit: 20)}")

    switches = [
      input: :string,
      from_step: :string,
      human_input: :string,
      session: :string,
      verbose: :boolean,
      help: :boolean
      ]
    {parsed, remaining, invalid} = OptionParser.parse(args, switches: switches)
    parse_opts_debug("OptionParser result: parsed=#{inspect(parsed)}, remaining=#{inspect(remaining, limit: 5)}, invalid=#{inspect(invalid)}")

    case {parsed, remaining, invalid} do
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
        result = Enum.into(opts, %{})
        parse_opts_debug("final opts keys: #{inspect(Map.keys(result))} from_step=#{inspect(result[:from_step])}")
        result

      error ->
        IO.puts("Options Read Error: #{inspect(error)}")
        System.halt(1)
    end
  end

  def run_loop(run_payload) do
    result = fly_and_wait(run_payload)

    case result do
      {:required_input_callback, step, from_step} ->
        opts = elem(run_payload, 2)
        __MODULE__.print_rejoin_and_halt(step, from_step, opts)

      {:send_api_message, {conv, message}, meta} ->
        %{opts: next_runtime_opts, human_input_mode: human_input_mode} = meta
        halt_after = Map.get(meta, :halt_after_for_optional_input, false)
        loopback_to = Map.get(meta, :loopback_allowed_to)
        bug(4, [label: "[harness] send_api_message", halt_after: halt_after, meta_keys: Map.keys(meta)])

        case __MODULE__.push_to_api_and_wait_for_response(human_input_mode, conv, message) do
          {:ok, response} ->
            input = response["body"]
            current_opts = elem(run_payload, 2)

            cond do
              halt_after ->
                # Only halt if user did NOT provide human input upfront. When
                # --human-input was passed, the user wants to cascade through.
                human_input_provided =
                  case Map.get(current_opts, :human_input) do
                    nil -> false
                    "-" -> false
                    s when is_binary(s) -> String.trim(s) != ""
                    _ -> false
                  end

                if human_input_provided do
                  next_command = next_runtime_opts ++ [input: input]
                  new_opts = Map.merge(current_opts, Enum.into(next_command, %{}))
                  IO.puts("\n\nAuto-running next command: pidge run #{inspect(next_runtime_opts)} --input RESPONSE-BODY\n\n")
                  File.write!("release/next_command.exs", inspect(next_command, limit: :infinity, printable_limit: :infinity))
                  bug(4, [label: "next_command_opts", opts: next_command])
                  new_payload = {:local, :main, new_opts}
                  run_loop(new_payload)
                else
                  __MODULE__.print_optional_input_rejoin_and_halt(
                    current_opts,
                    input,
                    next_runtime_opts,
                    loopback_to
                  )
                end

              human_input_mode == :optional ->
                # Next step has optional human input: halt and print continuation (do NOT auto-run)
                __MODULE__.print_next_step_optional_input_halt(
                  current_opts,
                  input,
                  next_runtime_opts
                )

              true ->
                # Normal: recurse to next step
                next_command = next_runtime_opts ++ [input: input]
                new_opts = Map.merge(current_opts, Enum.into(next_command, %{}))
                IO.puts("\n\nAuto-running next command: pidge run #{inspect(next_runtime_opts)} --input RESPONSE-BODY\n\n")
                File.write!("release/next_command.exs", inspect(next_command, limit: :infinity, printable_limit: :infinity))
                bug(4, [label: "next_command_opts", opts: next_command])
                new_payload = {:local, :main, new_opts}
                run_loop(new_payload)
            end
          {:error, reason} ->
            {:error, reason}
        end

      other ->
        other
    end
  end

  def fly_and_wait(run_payload) do
    bug(4, [label: "[harness] fly_and_wait calling new_flight", script: run_payload, from_step: elem(run_payload, 2)[:from_step]])
    flight_no = FlightControl.new_flight(run_payload)

    wait(flight_no)
  end

  def wait(flight_no) do
    receive do
      {:landed, ^flight_no, payload} ->
        payload
      {:crashed, ^flight_no, error} ->
        raise "Flight crashed: \n\n#{error}\n\n"
    after
      2_000 ->
        case FlightControl.check_flight_status(flight_no) do
          {:landed, payload} ->
            IO.puts("WARNING: Flight says it landed, but it didn't send message: #{inspect(flight_no)}")
            payload
          {:crashed, error} ->
            raise "Flight crashed, but did not send :crashed message.  Error: \n\n#{inspect(error)}\n\n"
          :in_flight ->
            IO.puts("Still in flight... (#{flight_no})")
            wait(flight_no)
        end
    end
  end

  def push_to_api_and_wait_for_response(_human_input_mode, conv, message) do
    session = RunState.get_opt(:session)
    past_count = Pidge.LLMConversationStore.get_messages(session, to_string(conv)) |> length()
    IO.puts("Sending to LLM (conversation: #{conv}, session: #{session}, past_messages: #{past_count})")
    IO.puts("\n--- Prompt being sent (first 1600 chars) ---\n")
    IO.puts(String.slice(message, 0, 1600))
    if String.length(message) > 1600, do: IO.puts("\n... [#{String.length(message) - 1600} more chars]")
    IO.puts("\n--- End prompt preview ---\n")

    case Pidge.LLMClient.send_and_wait_for_response(session, conv, message) do
      {:ok, response_data} ->
        IO.puts("Response received: #{String.length(response_data["body"] || "")} bytes")
        bug(2, [response_data: response_data, label: "Response Data"])
        {:ok, response_data}
      {:error, reason} ->
        IO.puts("LLM error: #{inspect(reason)}")
        bug(2, [reason: reason, label: "Error"])
        {:error, reason}
      error ->
        bug(2, [error: error, label: "Unknown error"])
        {:error, "Unknown error"}
    end
  end

  def print_optional_input_rejoin_and_halt(current_opts, input, next_runtime_opts, loopback_to) do
    session = Map.get(current_opts, :session) || RunState.get_opt(:session)
    next_step = Keyword.get(next_runtime_opts, :from_step)

    if loopback_to && is_binary(input), do: write_pipe_input(session, input)

    IO.puts("\n--- Optional human input: step finished. You may continue or loop back. ---\n")
    if next_step do
      IO.puts("To continue to next step (#{next_step}):\n")
      IO.puts("  pidge run --session #{session} --from-step #{next_step}\n")
      IO.puts("(Pipe input is stored; no --input needed.)\n")
    else
      IO.puts("To continue: you're done. No further action needed.\n")
    end
    if loopback_to do
      IO.puts("To loop back to #{loopback_to} for another critique round:\n")
      IO.puts("  pidge run --session #{session} --from-step #{loopback_to}\n")
      IO.puts("(Pipe input is stored; no --input needed.)\n")
    end
    {:halt_optional_input}
  end

  def print_next_step_optional_input_halt(current_opts, input, next_runtime_opts) do
    session = Map.get(current_opts, :session) || RunState.get_opt(:session)
    from_step = Keyword.get(next_runtime_opts, :from_step)
    has_human_input_flag = Keyword.has_key?(next_runtime_opts, :human_input)

    # Persist pipe input so resume does not require --input
    write_pipe_input(session, input)

    IO.puts("\n--- Next step has optional human input. Halting (no auto-run). ---\n")
    base = ["pidge", "run", "--session", session, "--from-step", from_step]
    args_no_input = if has_human_input_flag, do: base ++ ["--human-input", "-"], else: base
    IO.puts("To continue (no human input): #{Enum.join(args_no_input, " ")}\n")
    IO.puts("To continue with human input: #{Enum.join(base ++ ["--human-input", "YOUR_INPUT"], " ")}\n")
    IO.puts("(Pipe input from previous step is stored; no --input needed.)\n")
    {:halt_optional_input}
  end

  def print_rejoin_and_halt(step, from_step, opts) do
    session = Map.get(opts, :session) || RunState.get_opt(:session)

    # Resuming to a later step (e.g. bard/03) but pipe input is missing – step that failed
    # is the previous pipe step (e.g. whip/02) which needs the prior output
    if opts[:from_step] && to_string(opts[:from_step]) != to_string(from_step) && step.method == :ai_pipethru do
      path = pipe_input_path(session)
      IO.puts("\n--- Pipe input required to resume at #{opts[:from_step]} ---\n")
      IO.puts("No stored pipe input found (expected: #{path}).\n")
      IO.puts("Run the pipeline from the start. When it halts before #{opts[:from_step]}, the pipe input")
      IO.puts("is saved. Then run: pidge run --session #{session} --from-step #{opts[:from_step]} --human-input -\n")
      IO.puts("(No --input needed; pipe input is loaded from the stored file.)\n")
      {:human_input_required}
    else
      base = ["pidge", "run", "--session", session, "--from-step", from_step]
      {flag, placeholder} =
        if Map.has_key?(step.params || %{}, :human_input) do
          {"--human-input", "YOUR_INPUT_HERE"}
        else
          {"--input", "YOUR_RESPONSE_HERE"}
        end

      IO.puts("\n--- Human input required for step: #{step.id} (#{step.method}) ---\n")
      IO.puts("To continue, run:\n")
      IO.puts("  " <> Enum.join(base ++ [flag, "\"#{placeholder}\""], " ") <> "\n")
      IO.puts("Replace #{inspect(placeholder)} with your actual input.\n")
      {:human_input_required}
    end
  end

  def print_help do
    IO.puts("""
    Usage: pidge run [OPTIONS]

    Options:
      --input              Define input for the script
      --from-step          Start from a specific step in the program
      --human-input        Provide human input for the program
      --verbose / -v       Enable verbose mode. This option can be used multiple times to increase verbosity level
      --help / -h          Display this help message

    Examples:
      pidge run --input "This is text to ask the AI.  Why is the sky blue?"
      pidge run -vv --human-input "Hello, world!"
    """)
  end

  # debug function passed level of debugging, and list of things to print
  def bug(level, [label: label_only]), do: if( RunState.get_verbosity() >= level, do: IO.puts(label_only))
  def bug(level, stuff_to_debug),      do: if( RunState.get_verbosity() >= level, do: IO.inspect(stuff_to_debug))

  def read_stdin_input(step, opts) do
    # If input is provided, read from stdin
    IO.puts("Reading stdin input for step: #{step.id} / #{step.method}")
    input = IO.read(:stdio, :all)
    Map.put(opts, :input, input)
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
