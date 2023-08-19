defmodule Pidge do
  def main(args) do
    case args do
      ["compile" | rest_args] -> Pidge.Compiler.compile(rest_args)
      ["run" | rest_args] -> Pidge.Run.run(rest_args)
      ["go" | rest_args] ->
        Pidge.Compiler.compile([])
        Pidge.Run.run(rest_args)
      ["continue" | rest_args] -> Pidge.Run.continue(rest_args)
      ["new" | [project_name]] -> Pidge.Project.new_project(project_name)
      _ -> IO.puts("Unknown command")
    end
  end
end
