defmodule Pidge.Compiler.PidgeScript do

  alias Pidge.Compiler.{CompileState, Expression}
  alias Pidge.Compiler.PidgeScript.Validate

  import Pidge.Util

  @pre_code_code_include "defmodule Pidge do; def a <~ b, do: max(a, b); def pidge do ;"
  @post_code_code_include """
    end
  end
  """

  @this_dot_that :.
  @access_dot_get [Access, :get]
  @callstack_module [:Pidge,:Runtime,:CallStack]

  # constant defining what opts are allowed for which functions
  @allowed_opts %{
    ai_prompt: [:human_input],
    ai_pipethru: [:optional_human_input, :loopback_allowed_to],
    ai_object_extract: [:schema, :human_input, :optional_human_input],
    ai_codeblock_extract: [:largest, :all, :human_input, :optional_human_input]
  }
  def compile_source(code) do
    with(
      {:ok, ast } <- Code.string_to_quoted(@pre_code_code_include <> code <> @post_code_code_include),
      # Drop the module definition
      {:defmodule, [line: 1], [{:__aliases__, [line: 1], [:Pidge]}, [do: {:__block__, [], ast } ] ] } <- ast,
      # Drop the first 1 item(s0 in the ast, which are the operator
      ast <- Enum.slice(ast, 1, length(ast)),
      # Drop the function pidge wrapper
      [{:def, _, [{:pidge, _, nil}, [do: ast ] ] } ] <- ast,
      [_|_] = pidge_ast <- parse_ast(ast),
      # Validate the AST
      :ok <- Validate.validate_ast(pidge_ast)
    ) do
      {:ok, pidge_ast}
    else
      error -> raise "Failed to compile: #{inspect(error, limit: :infinity, printable_limit: :infinity, pretty: true)}"
    end
  end

  def parse_ast({:__block__, _, list}) do
    Enum.reduce(list, [], fn command, acc ->
      acc ++ parse_command(command)
    end)
    # Loop Through each command and if id is nil, set ID to "00001" corresponding to the index of the List
    |> Enum.with_index(1)
    |> Enum.map(fn {command, index} ->
      Map.put(command, :seq, String.pad_leading(to_string(index), 5, "0"))
    end)
  end
  def parse_ast({:|>, a, b}), do: parse_ast({:__block__, a, b})
  def parse_ast({_, a, _} = line), do: parse_ast({:__block__, a, [line]})


  def parse_command(
    {
      {
        @this_dot_that,
        _,
        [
          {_,_,[:Context]},
          context_function
        ]
      }, _, params}) when is_atom(context_function) do
    case {context_function, params} do
      {:add_conversation, [conversation_id]} ->
        [%{
          id: nil,
          method: :context_create_conversation,
          params: %{ conversation_id: conversation_id}
        }]
      {:prompt_base, [prompt_base_subdir]} ->
        CompileState.set_scope_key(:prompt_base, prompt_base_subdir<>"/")
        [%{
          id: nil,
          method: :prompt_base,
          params: %{ prompt_base_subdir: prompt_base_subdir}
        }]
    end
  end

  def parse_command(
    {
      {
        @this_dot_that,
        _,
        [
          {:__aliases__,_,[:Local | alias_path]},
          function_name
        ]
      }, _, args}) do
    CompileState.push_meta_key(:local_functions, {alias_path, function_name})

    parsed_args = args |> Enum.map(fn arg ->
      collapse_dottree(arg, [])
    end)

    [%{
      id: nil,
      method: :local_function_call,
      params: %{ alias_path: alias_path, function_name: function_name, args: parsed_args }
    }]
  end

  # Handle |> pipes, just call parse_ast and concat the results
  def parse_command({:|>, _, _} = block) do
    parse_ast(block)
  end

  def parse_command(
    {:=, a,
      [
        {{@this_dot_that, b, @access_dot_get}, _, access_chain},
        c
      ]
      }
      ) do
    # Parse to grab the first elem if each tuple
    pidge_access_chain = access_chain |> collapse_dottree([])

    parse_command({:=, a, [{pidge_access_chain, b, nil},c]})
  end
  def parse_command(
    {:=, _line,
      [
        {name, _, _},
        value
      ]
      }
      ) do
    assign_name =
      case name do
        {@this_dot_that, _, _} -> name |> collapse_dottree([])
        [""<>_|_] -> name
        x when is_atom(x) -> to_string(name)
      end

    case value do
      {{@this_dot_that, _line, [{:__aliases__, _, [:Local | _]}, _]}, _, _} ->
        parse_command(value) ++ [%{
          id: nil,
          method: :store_object,
          params: %{object_name: assign_name}
        }]
      {{@this_dot_that, _, _}, _, _} ->
        [%{
          id: nil,
          method: :clone_object,
          params: %{clone_from_object_name: value |> collapse_dottree([]), object_name: assign_name}
        }]

      # If it is a pipe, we evaluate the whole chain, and then store the result
      {:|>, _, _} = sub_struct ->
        parse_ast(sub_struct) ++ [%{
          id: nil,
          method: :store_object,
          params: %{object_name: assign_name}
        }]
      # If it is a simple atom, we are just assigning one variable to another
      {atom,_,nil} when is_atom(atom) ->
        [%{
          id: nil,
          method: :clone_object,
          params: %{clone_from_object_name: to_string(atom), object_name: assign_name}
        }]
      # If the the value is a 3-elem tuple, we assume this is a function call
      {_, _, _} ->
        parse_command(value) ++ [%{
          id: nil,
          method: :store_object,
          params: %{object_name: assign_name}
        }]
      simple ->
        [%{
          id: nil,
          method: :store_simple_value,
          params: %{object_name: assign_name, value: simple}
        }]
      # error -> raise "PIDGE: Invalid assignment value on #{inspect(line)}: #{inspect(error)}"
    end
  end

  def parse_command({:<~, a, b}) do
    commands = parse_command({:=, a, b})

    # change the method key of the last map in commands list to :merge_into_object
    Enum.map(commands, fn command ->
      if command == Enum.at(commands, -1) do
        Map.put(command, :method, :merge_into_object)
      else
        command
      end
    end)
  end

  def parse_command({:foreach, line, args}) do
    {loop_on_variable_path, instance_variable_name, iter_variable_name, sub_ast} =
      case args do
        [{loop_on_variable_path, _, _}, {:fn, _, [{:->, _, [[{{instance_variable_name, _, nil}, {iter_variable_name, _, nil}}], sub_ast]}]}] ->
          {loop_on_variable_path, instance_variable_name, iter_variable_name, sub_ast}

        error -> raise "PIDGE: Invalid foreach on #{inspect(line)}: #{inspect(error)}"
      end

    sub_pidge_ast = parse_ast(sub_ast)

    [%{
      id: nil,
      method: :foreach,
      params: %{
        loop_on_variable_name: loop_on_variable_path |> collapse_dottree([]),
        instance_variable_name: to_string(instance_variable_name),
        iter_variable_name: to_string(iter_variable_name),
        sub_pidge_ast: sub_pidge_ast
      }
    }]
  end

  def parse_command({:if, _, [{_, _, _} = expression, [do: sub_ast]]}) do
    sub_pidge_ast = parse_ast(sub_ast)

    [%{
      id: nil,
      method: :if,
      params: %{
        expression: Expression.compile_expression(expression),
        sub_pidge_ast: sub_pidge_ast
      }
    }]
  end

  def parse_command({:fly, _, [sub_pidge_filename]}) when is_atom(sub_pidge_filename) do
    CompileState.push_meta_key(:pidge_scripts, sub_pidge_filename)
    [%{
      id: nil,
      method: :fly,
      params: %{
        sub_pidge_filename: sub_pidge_filename
      }
    }]
  end

  def parse_command({:bring, _, [first_var|_] = variables}) when is_atom(first_var) do
    [%{
      id: nil,
      method: :bring,
      params: %{
        variables: variables
      }
    }]
  end

  def parse_command({:case, case_line, [{expression, _, []}, [do: case_asts]]}) do
    cases =
      Enum.map(case_asts, fn case_option ->
        case case_option do
          {:->, _line, [[case_value], sub_ast]} ->
            sub_pidge_ast = parse_ast(sub_ast)

            %{
              case_expression: case_value,
              sub_pidge_ast: sub_pidge_ast
            }
           {_, line, _} -> raise "PIDGE: Invalid case option on #{inspect(line)}: #{inspect(case_option)}"
           _ -> raise "PIDGE: Really Invalid case option on #{inspect(case_line)}: #{inspect(case_option)}"
          end
      end)

    [%{
      id: nil,
      method: :case,
      params: %{
        expression: Expression.compile_expression(expression),
        cases: cases
      }
    }]
  end

  def parse_command({:continue, _line, nil}) do
    [%{
      id: nil,
      method: :continue,
      params: %{}
    }]
  end

  def parse_command({:input, _, _}) do
    [%{
      id: nil,
      method: :pipe_from_input,
      params: %{}
    }]
  end

  def parse_command({:human_input, _line, nil}) do
    [%{
      id: nil,
      method: :pipe_from_human_input,
      params: %{human_input: true}
    }]
  end

  def parse_command({variable_name, _line, nil}) when is_atom(variable_name) do
    [%{
      id: nil,
      method: :pipe_from_variable,
      params: %{
        variable: to_string(variable_name)
      }
    }]
  end

  # parse function call command where the first value of the tuple is an atom
  def parse_command({function_name, line, args}) when is_atom(function_name) do
    # if function name is not in @allowed_opts, raise a compile error
    if !Map.has_key?(@allowed_opts, function_name) do
      raise "PIDGE: Invalid function name: #{function_name}#{inspect(args)} on #{inspect(line)}"
    end

    case {function_name,args} do
      {:ai_object_extract, [conversation_id, prompt, format, opts]} ->
        CompileState.push_meta_key(:prompt_files, CompileState.get_scope_key(:prompt_base,"")<>to_string(prompt))
        [%{
          id: prompt,
          method: function_name,
          params: parse_opts(function_name, %{
            conversation_id: to_string(conversation_id),
            prompt: to_string(prompt),
            format: to_string(format)
          }, opts, line)
        }]
      {:ai_codeblock_extract, [conversation_id, prompt, language, opts]} ->
        CompileState.push_meta_key(:prompt_files, CompileState.get_scope_key(:prompt_base,"")<>to_string(prompt))
        [%{
          id: prompt,
          method: function_name,
          params: parse_opts(function_name, %{
            conversation_id: to_string(conversation_id),
            prompt: to_string(prompt),
            language: to_string(language)
          }, opts, line)
        }]
      {_, [conversation_id, prompt]} ->
        CompileState.push_meta_key(:prompt_files, CompileState.get_scope_key(:prompt_base,"")<>to_string(prompt))
        [%{
          id: prompt,
          method: function_name,
          params: %{conversation_id: to_string(conversation_id), prompt: to_string(prompt)}
        }]
      {_, [conversation_id, prompt, opts]} ->
        CompileState.push_meta_key(:prompt_files, CompileState.get_scope_key(:prompt_base,"")<>to_string(prompt))
        [%{
          id: prompt,
          method: function_name,
          params: parse_opts(function_name, %{
            conversation_id: to_string(conversation_id),
            prompt: to_string(prompt)
          }, opts, line)
        }]

      _ ->
        raise "PIDGE: Invalid function call: #{function_name}(#{args |> Enum.join(", ")})"
    end
  end

  def collapse_dottree(a, b, c \\ nil)
  def collapse_dottree({@this_dot_that, _, [a, key]}, acc, flag) when is_atom(key) do
    collapse_dottree(a, acc, flag) ++ [to_string(key)]
  end
  def collapse_dottree({{@this_dot_that, _, _} = dot, _, []}, acc, flag) do
    (collapse_dottree(dot |> trace(), [], flag) |> trace()) ++ acc
  end
  def collapse_dottree(
    [
      {dot, _, []},
      {var_key, _line, _}
    ], acc, flag) do
    case var_key |> trace() do
      atom when is_atom(atom) -> collapse_dottree(dot, [{var_key}] ++ acc, flag)
      _ -> collapse_dottree(dot, [{collapse_dottree(var_key,[])}] ++ acc, flag)
    end
  end
  def collapse_dottree({{@this_dot_that,_,[{:__aliases__,_,@callstack_module},:get_variable]},_,[_]} = access, acc, :expr), do: [access] ++ acc
  def collapse_dottree(
    {
      {
        @this_dot_that,
        _line1,
        @access_dot_get
      },
      _line2,
      [
        dot,
        key_access
      ]
    }, acc, flag) do
    case {key_access,flag} |> trace() do
      ### Called from within Expression evaluation
      # if the "that", or the key being accessed is a CallStack.get_variable() lookup
      #   --> don't modify anything, just let it pass through as-is
      {{{@this_dot_that,_,[{:__aliases__,_,@callstack_module},:get_variable]},_,[_]} = x,:expr} ->
        [dot |> trace()] ++ [x] ++ acc
      # a key which is an already-dottree-collapsed list
      {x,:expr} when is_list(x) -> [dot ++[{key_access |> trace()}]] ++ acc
      # a key who's value comes from a variable like foo[i]
      {{var_key,line,_},:expr} when is_atom(var_key) ->
        collapse_dottree(dot, [Expression.wrap_partial_expression({:access, var_key |> trace(label: "before"), line}) |> trace()] ++ acc, :expr)
      # a key who's value is another lookup like foo[stuff.i.j]
      {{var_key,line,_},:expr} ->
        collapse_dottree(dot, [{collapse_dottree(Expression.wrap_partial_expression({:access, var_key, line}) |> trace(),[])}] ++ acc, :expr)

      # a key who's value comes from a variable like foo[i]
      {{var_key,_,_},_} when is_atom(var_key) ->
        collapse_dottree(dot, [{to_string(var_key) |> trace()}] ++ acc, flag)
      # a key who's value is another lookup like foo[stuff.i.j]
      {{var_key,_,_},_} ->
        collapse_dottree(dot, [{collapse_dottree(var_key |> trace(),[])}] ++ acc, flag)
      # literal key like foo[0] or foo["key"]
      {x,_} when is_integer(x) -> collapse_dottree(dot, [key_access |> trace()] ++ acc, flag)
      {x,_} when is_binary(x) -> collapse_dottree(dot, [key_access |> trace()] ++ acc, flag)
    end
  end
  def collapse_dottree({{@this_dot_that, _line1, @access_dot_get}, _line2, [dot,""<>_ = string_key]}, acc, flag) do
    collapse_dottree(dot |> trace(), [string_key] ++ acc, flag)
  end
  def collapse_dottree({key, _,nil}, acc, _flag) when is_atom(key) do
    ([to_string(key |> trace())] |> trace()) ++ acc
  end
  def collapse_dottree(key, acc, _flag) when is_atom(key) do
    [to_string(key |> trace())] ++ acc
  end
  def collapse_dottree(key, [], _flag) when is_binary(key), do: key |> trace()
  def collapse_dottree(key, [], _flag) when is_number(key), do: key |> trace()
  def collapse_dottree(key, [], _flag) when is_atom(key), do: key |> trace()

  def parse_opts(function_name, params, opts, line) do
    opts = Map.new(opts)
    # if there are any disallowed opts (not in list for this function of @allowed_opts), raise a compile error
    if Map.keys(opts) |> Enum.any?(&!Enum.member?(@allowed_opts[function_name], &1)) do
      raise "PIDGE: Invalid option(s) for #{function_name} on #{inspect(line)}: #{opts |> Map.keys |> Enum.join(", ")}"
    end
    # merge opts map into params (only if in @allowed_opts)
    Map.merge(params, opts |> Map.take(@allowed_opts[function_name]))
  end

  def to_method({@this_dot_that, _, [{:__aliases__, _, _}, fun]}) when is_atom(fun), do: Atom.to_string(fun)
  def to_method(fun) when is_atom(fun), do: Atom.to_string(fun)

  def parse_params(fun, args, params) do
    case fun do
      {@this_dot_that, _, [{:__aliases__, _, _}, :add_conversation]} ->
        {"conversation_id", List.first(params)}
      _ ->
        {
          "conversation_id",
          List.first(args)
        }
    end
  end
end
