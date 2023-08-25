defmodule Pidge.Compiler.Expression do
  def compile_expression(expr) do
    IO.inspect(expr, label: "compile_expression BEFORE")

    compiled = walk_expression(expr, &(wrap_partial_expression(&1)))
    IO.inspect(compiled, label: "compile_expression AFTER")
  end

  def wrap_partial_expression(item) do
    IO.inspect(item, label: to_string(elem(item,0)))
    case item do
      {:access, {{:.,line,[Access, :get]},_line2,[_,_]} = access, _} ->
        access_to_callstack_get_variable(line, access) |> IO.inspect(label: "wrap_partial_expression line #{__ENV__.line}")
      {:access, {{:., line, [_|_]}, _line2, []} = access, _} ->
        access_to_callstack_get_variable(line, access) |> IO.inspect(label: "wrap_partial_expression line #{__ENV__.line}")
      {:access, access, line} ->
        access_to_callstack_get_variable(line, access) |> IO.inspect(label: "wrap_partial_expression line #{__ENV__.line}")

      {:term, term} -> term
    end
  end

  # Basically we walk through the allowed operators, and if we find anything we don't like, we return an error
  def walk_expression({:|| = x, line, [_|_] = ops}, c), do: {x, line, sub_walk_list(ops, c)}
  def walk_expression({:&& = x, line, [_|_] = ops}, c), do: {x, line, sub_walk_list(ops, c)}
  def walk_expression({:> = x,  line, [_,_] = ops}, c), do: {x, line, sub_walk_list(ops, c)}
  def walk_expression({:>= = x, line, [_,_] = ops}, c), do: {x, line, sub_walk_list(ops, c)}
  def walk_expression({:< = x,  line, [_,_] = ops}, c), do: {x, line, sub_walk_list(ops, c)}
  def walk_expression({:<= = x, line, [_,_] = ops}, c), do: {x, line, sub_walk_list(ops, c)}
  def walk_expression({:== = x, line, [_,_] = ops}, c), do: {x, line, sub_walk_list(ops, c)}
  def walk_expression({{:.,_line,[Access, :get]} = x,line,[_,_] = ops}, c), do:
    report_access({x, line, sub_walk_list(ops, c)},c)
  def walk_expression({{:., line, [_|_] = ops}, line2, []}, c), do:
    report_access({{:., line, sub_walk_list(ops, c)}, line2, []},c)

  def walk_expression({:! = x, line, [_] = ops}, c), do: {x, line, sub_walk_list(ops, c)}

  def walk_expression({x, _line, nil} = var, c) when is_atom(x), do: report_term(var, c)
  def walk_expression({:.,_,[{y,_,nil},z]} = x, c) when is_atom(y) and is_atom(z), do: report_term(x, c)
  def walk_expression(x, c) when is_number(x),                   do: report_term(x, c)
  def walk_expression(x, c) when is_atom(x),                   do: report_term(x, c)
  def walk_expression(""<>_ = x, c),                             do: report_term(x, c)

  def walk_expression(fail), do: raise "Unknown expression: #{inspect(fail)}"

  def report_term(term, c), do: apply(c, [{:term, term}])
  def report_access(access, c), do: apply(c, [{:access, access, nil}])
  def sub_walk_list(ops, c), do: Enum.map(ops, fn op -> walk_expression(op, c) end)

  def access_to_callstack_get_variable(line, var_name) when is_atom(var_name) do
    IO.inspect({__ENV__.line, var_name}, label: "access_to_callstack_get_variable")
    {{:., line, [{:__aliases__, line, [:Pidge,:Runtime,:CallStack]}, :get_variable]}, line, [to_string(var_name)]}
  end
  def access_to_callstack_get_variable(line, dottree) do
    IO.inspect(__ENV__.line, label: "access_to_callstack_get_variable")
    var_path = Pidge.Compiler.PidgeScript.collapse_dottree(dottree,[],:expr)
    {{:., line, [{:__aliases__, line, [:Pidge,:Runtime,:CallStack]}, :get_variable]}, line, [var_path]}
  end
end
