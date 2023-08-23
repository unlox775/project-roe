defmodule Pidge.Run.LocalFunction do

  alias Pidge.Run.LocalFunction.CompiledElixir

  import Pidge.Util

  def function_call(alias_path, function_name, args) do
    function_dir =
      case alias_path do
        [] -> ""
        _ -> "/"<> (alias_path |> Enum.map(&(camel_to_snake_case(&1))) |> Enum.join("/"))
      end
    compiled_filename_stub = "release/local_functions#{function_dir}/#{function_name}"
    cond do
      File.exists?("#{compiled_filename_stub}.ex.pjf") ->
        CompiledElixir.run_function("#{compiled_filename_stub}.ex.pjf", args)
      true -> raise "PIDGE: Local function file not found: #{compiled_filename_stub}"
    end
  end

  # defp bug(level, stuff_to_debug), do: Pidge.Run.bug(level, stuff_to_debug)
end
