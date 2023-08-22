defmodule Pidge.Compiler.LocalFunction do
  alias Pidge.Compiler.LocalFunction.ElixirSyntax

  def compile_elixir_function(code) do
    with 1 <- 1,
      {:ok, ast} <- ElixirSyntax.validate_function(code),
      {:ok, bytecode} <- ElixirSyntax.compile_function(ast)
    do
      {:ok, bytecode}
    end
  end
end
