defmodule Pidge.Compiler.LocalFunction.ElixirSyntax do
  @precode "defmodule PidgeLocalFunction do; "
  @postcode "\n end"

  def validate_function(code) do
    # compile
    ast = Code.string_to_quoted(@precode<>code<>@postcode)

    # Test for certain no-no's to keep this case reallllllly simple
    # TODO

    {:ok, ast}
  end

  def compile_function(ast) do
    # compile
    [{PidgeLocalFunction,bytecode}] = Code.compile_quoted(ast)

    # As this does actually load this module into the current namespace, we need to purge it
    :code.purge(PidgeLocalFunction)
    :code.delete(PidgeLocalFunction)

    {:ok, bytecode}
  end
end
