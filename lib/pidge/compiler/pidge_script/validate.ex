defmodule Pidge.Compiler.PidgeScript.Validate do
  # Function to validate the PIDGE AST
  def validate_ast(ast) do
    # Make sure all the ID's are either nil or unique, and raise an error if not
    ids = ast |> Enum.map(&(&1.id)) |> Enum.reject(&is_nil/1)
    if ids |> Enum.uniq() |> length() != length(ids) do
      raise "PIDGE: Duplicate ID's found in AST: #{ids |> Enum.uniq() |> Enum.join(", ")}"
    end
    :ok
  end
end
