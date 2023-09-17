defmodule Pidge.Run.LocalFunction do

  alias Pidge.Run.LocalFunction.CompiledElixir
  alias Pidge.App.Loft

  import Pidge.Util

  def function_call(app_name, alias_path, function_name, args) do
    function_dir =
      case alias_path do
        [] -> ""
        _ -> (alias_path |> Enum.map(&(camel_to_snake_case(&1))) |> Enum.join("/")) <> "/"
      end
    compiled_filename_stub = "#{function_dir}#{function_name}"
    case Loft.get_local_function(app_name, compiled_filename_stub) do
      {:elixir, code} ->
        CompiledElixir.run_function(code, args)
      _ -> raise "PIDGE: Local function file not found: #{compiled_filename_stub}"
    end
  end

  # defp bug(level, stuff_to_debug), do: Pidge.Run.bug(level, stuff_to_debug)
end
