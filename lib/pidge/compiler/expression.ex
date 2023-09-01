defmodule Pidge.Compiler.Expression do
  import Pidge.Util

  @this_dot_that :.
  @access_dot_get [Access, :get]
  @callstack_module [:Pidge,:Runtime,:CallStack]

  def compile_expression(expr) do
    expr |> trace(label: "compile_expression BEFORE")

    compiled = walk_expression(expr, &(wrap_partial_expression(&1)))
    compiled |> trace(label: "compile_expression AFTER")
  end

  def wrap_partial_expression(item) do
    trace(item, label: to_string(elem(item,0)))
    case item do
      {:access, {{:.,line,@access_dot_get},_line2,[_,_]} = access, _} ->
        access_to_callstack_get_variable(line, access) |> trace()
      {:access, {{:., line, [_|_]}, _line2, []} = access, _} ->
        access_to_callstack_get_variable(line, access) |> trace()
      {:access, {atom, line, nil}, _} when is_atom(atom) ->
        access_to_callstack_get_variable(line, atom) |> trace()
      {:access, access, line} ->
        trace(line, label: "wrap_partial_expression[#{inspect(line)}] line #{__ENV__.line}")
        access_to_callstack_get_variable(line, access) |> trace()

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

  def walk_expression({{@this_dot_that,_line,@access_dot_get} = x,line,[obj,key]}, c), do:
    report_access({x, line, sub_walk_list([obj |> trace(label: "arg a"),key |> trace(label: "arg b")], c) |> trace(label: "first")},c) |> trace()
  def walk_expression({{@this_dot_that, line, [obj,key]}, line2, []}, c), do:
    report_access({{@this_dot_that, line, sub_walk_list([obj,key], c)}, line2, []},c) |> trace()

  def walk_expression({:! = x, line, [_] = ops}, c), do: {x, line, sub_walk_list(ops, c)} |> trace()

  def walk_expression({varname, line, nil} = var, c) when is_atom(varname), do: report_access(var |> trace(), c, line) |> trace()
  def walk_expression({@this_dot_that,line,[{y,_,nil},z]} = x, c) when is_atom(y) and is_atom(z), do: report_access(x, c, line) |> trace()
  def walk_expression(x, c) when is_number(x),                   do: report_term(x, c)
  def walk_expression(x, c) when is_atom(x),                     do: report_term(x, c)
  def walk_expression(""<>_ = x, c),                             do: report_term(x, c)

  def walk_expression(fail), do: raise "Unknown expression: #{inspect(fail)}"

  def report_term(term, c), do: apply(c, [{:term, term}])
  def report_access(access, c, line \\ nil), do: apply(c, [{:access, access, line}])
  def sub_walk_list(ops, c), do: Enum.map(ops, fn op -> walk_expression(op |> trace(label: "before value"), c) |> trace() end)

  def access_to_callstack_get_variable(line, var_name) when is_atom(var_name) do
    {
      {@this_dot_that, line, [{:__aliases__, line, @callstack_module}, :get_variable]},
      line,
      [ [to_string(var_name |> trace())] ]
    }
  end
  def access_to_callstack_get_variable(line, dottree) do
    [first|tail] = Pidge.Compiler.PidgeScript.collapse_dottree(dottree |> trace(),[],:expr)
    first =
      case first do
        {{@this_dot_that, line, [{:__aliases__, line, @callstack_module}, :get_variable]}, _, [vars]} -> vars
        ""<>_ -> [first]
      end
    {
      {@this_dot_that, line, [{:__aliases__, line, @callstack_module}, :get_variable]},
      line,
      [(first ++ tail) |> trace()]
    }
  end
end
