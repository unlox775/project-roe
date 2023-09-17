defmodule Pidge.Compiler do

  alias Pidge.Compiler.PidgeScript
  alias Pidge.Compiler.LocalFunction
  alias Pidge.Compiler.CompileState

  import Pidge.Util

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

    # Write manifest.json
    manifest = %{
      pidge_code: Map.keys(CompileState.get_meta_key(:compiled_pidge_scripts)),
      prompt_files: Map.keys(CompileState.get_meta_key(:compiled_prompt_files)),
      local_function_files: Map.keys(CompileState.get_meta_key(:compiled_local_functions))
    }
    File.write!("release/manifest.json", Jason.encode!(manifest, pretty: true))

    # end the state process
    CompileState.stop(compilestate_pid)
  end

  def compile_pidge_scripts(queue_key, compiled_map_key) do
    # Pull the next item from the queue
    case safe_pull_from_queue(queue_key, compiled_map_key) do
      {:queue_empty} -> :ok
      {:ok, script_name} ->
        CompileState.set_meta_key(:current_scope, [script_name])
        CompileState.set_scope_key(:prompt_base, "")
        with(
          {:mkdir, :ok} <- {:mkdir, File.mkdir_p("release")},
          {:read, {:ok, code}} <- {:read, File.read("src/#{script_name}.pj")},
          {:ok, pidge_ast} <- PidgeScript.compile_source(code)
        ) do
          File.write!("release/#{script_name}.pjc", inspect(pidge_ast, limit: :infinity, printable_limit: :infinity, pretty: true))
        else
          error -> raise "Failed to compile: #{inspect(error, limit: :infinity, printable_limit: :infinity, pretty: true)}"
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
      {:ok, {path, function_name}} ->
        function_dir =
          case path do
            [] -> ""
            _ -> "/"<> (path |> Enum.map(&(camel_to_snake_case(&1))) |> Enum.join("/"))
          end
        filename_stub = "local_functions#{function_dir}/#{function_name}"
        compiled_filename_stub = "release/#{filename_stub}"
        File.mkdir_p!(Path.dirname(compiled_filename_stub))
        cond do
          File.exists?("src/#{filename_stub}.ex") ->
            # This runs validation and will raise if anything fails
            IO.puts("\nCompiling local function: src/#{filename_stub}.ex ...")
            {:ok, bytecode} = LocalFunction.compile_elixir_function(
              File.read!("src/#{filename_stub}.ex")
              )
            File.write!("#{compiled_filename_stub}.ex.pjf", bytecode)

          true -> raise "PIDGE: Local function file not found: #{filename_stub}"
        end

        compile_local_functions(queue_key, compiled_map_key)
    end
  end

  # pull from the queue, and avoid infinite loops, by checking the compiled list
  def safe_pull_from_queue(queue_key, compiled_map_key) do
    case CompileState.shift_meta_key(queue_key) do
      nil -> {:queue_empty}
      item ->
        id =
          case item do
            x when is_tuple(x) ->
              # count the number of items in the tuple
              item |> Tuple.to_list() |> List.flatten() |> Enum.join("|")
            x when is_atom(x) -> to_string(item)
            _ -> item
          end

        case Map.has_key?(CompileState.get_meta_key(compiled_map_key), id) do
          true -> safe_pull_from_queue(queue_key, compiled_map_key)
          false ->
            CompileState.set_meta_key(compiled_map_key, Map.put(CompileState.get_meta_key(compiled_map_key), id, true))
            {:ok, item}
        end
    end
  end
end
