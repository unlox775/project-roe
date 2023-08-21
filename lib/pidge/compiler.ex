defmodule Pidge.Compiler do

  alias Pidge.Compiler.PidgeScript
  alias Pidge.Compiler.CompileState

  def compile(_args) do
    {:ok, compilestate_pid} = CompileState.start_link(%{
      pidge_scripts: ["main"],
      compiled_pidge_scripts: %{},

      prompt_files: [],
      compiled_prompt_files: %{},

      local_functions: [],
      compiled_local_functions: %{}
    })

    compile_pidge_scripts(:pidge_scripts, :compiled_pidge_scripts)
    compile_prompts(:prompt_files, :compiled_prompt_files)
    compile_local_functions(:local_functions, :compiled_local_functions)

    # end the state process
    CompileState.stop(compilestate_pid)
  end

  def compile_pidge_scripts(queue_key, compiled_map_key) do
    # Pull the next item from the queue
    case safe_pull_from_queue(queue_key, compiled_map_key) do
      {:queue_empty} -> :ok
      {:ok, script_name} ->
        with(
          {:mkdir, :ok} <- {:mkdir, File.mkdir_p("release")},
          {:read, {:ok, code}} <- {:read, File.read("src/#{script_name}.pj")},
          {:ok, pidge_ast} <- PidgeScript.compile_source(code)
        ) do
          File.write!("release/#{script_name}.pjc", inspect(pidge_ast, limit: :infinity, pretty: true))
        else
          error -> raise "Failed to compile: #{inspect(error, limit: :infinity, pretty: true)}"
        end

        compile_pidge_scripts(queue_key, compiled_map_key)
    end
  end

  # Function for validating the prompts referred to by the AST
  def compile_prompts(queue_key, compiled_map_key) do
    # Pull the next item from the queue
    case safe_pull_from_queue(queue_key, compiled_map_key) do
      {:queue_empty} -> :ok
      {:ok, script_name} ->
        filename = "src/prompts/#{script_name}.pjt"
        case File.exists?(filename) do
          false -> raise "PIDGE: Prompt file not found: #{filename}"
          true ->
            # chop off the /src/ part of the path
            new_file_path = "release/#{String.slice(filename, 4..-1)}"
            dirname = Path.dirname(new_file_path)
            File.mkdir_p!(dirname)
            File.write!(new_file_path, File.read!(filename))
        end

        compile_prompts(queue_key, compiled_map_key)
    end
  end

  # Function for validating the prompts referred to by the AST
  def compile_local_functions(queue_key, compiled_map_key) do
    # Pull the next item from the queue
    case safe_pull_from_queue(queue_key, compiled_map_key) do
      {:queue_empty} -> :ok
      {:ok, script_name} ->
        _filename = "src/local_functions/#{script_name}.ex"

        compile_prompts(queue_key, compiled_map_key)
    end
  end

  def get_all_method_calls(pidge_ast) do
    pidge_ast
    |> Enum.map(fn command ->
      case command do
        %{params: %{sub_pidge_ast: sub_pidge_ast}} ->
          get_all_method_calls(sub_pidge_ast)
        _ -> [command]
      end
    end)
    # Flatten the list of lists
    |> List.flatten()
  end

  # pull from the queue, and avoid infinite loops, by checking the compiled list
  def safe_pull_from_queue(queue_key, compiled_map_key) do
    case CompileState.shift_meta_key(queue_key) do
      nil -> {:queue_empty}
      item ->
        case Map.has_key?(CompileState.get_meta_key(compiled_map_key), item) do
          true -> safe_pull_from_queue(queue_key, compiled_map_key)
          false -> {:ok, item}
        end
    end
  end
end
