defmodule Pidge do
  def main(args) do
    case args do
      ["compile" | rest_args] -> Pidge.Compiler.compile(rest_args)
      ["run" | rest_args] -> Pidge.Run.run(rest_args)
      ["continue" | rest_args] -> Pidge.Run.continue(rest_args)
      _ -> IO.puts("Unknown command")
    end
  end
end
