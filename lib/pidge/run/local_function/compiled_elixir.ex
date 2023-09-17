defmodule Pidge.Run.LocalFunction.CompiledElixir do
  def run_function(code, args) do
    :code.load_binary(PidgeLocalFunction, [], code)

    # Now call PidgeLocalFunction.function() with the args passed in using apply
    result = apply(PidgeLocalFunction, :function, args)

    # As this does actually load this module into the current namespace, we need to purge it
    :code.purge(PidgeLocalFunction)
    :code.delete(PidgeLocalFunction)

    result
  end
end
