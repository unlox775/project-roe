defmodule Pidge do
  def main(args) do
    case args do
      ["compile" | rest_args] -> Pidge.Compiler.compile(rest_args)
      ["run" | rest_args] -> Pidge.Harness.CommandLine.run(rest_args)
      ["go" | rest_args] ->
        Pidge.Compiler.compile([])
        Pidge.Harness.CommandLine.run(rest_args)
      ["continue" | rest_args] -> Pidge.Harness.CommandLine.continue(rest_args)
      ["new" | [app_name]] -> Pidge.App.new_app(app_name)
      _ ->
        IO.puts("Unknown command")
        IO.puts("Usage:")
        IO.puts("  compile <args> - Compile the code")
        IO.puts("  run <args> - Run the code")
        IO.puts("  go <args> - Compile and run the code")
        IO.puts("  continue <args> - Continue running the code")
        IO.puts("  new <app_name> - Create a new app")
    end
  end
end
