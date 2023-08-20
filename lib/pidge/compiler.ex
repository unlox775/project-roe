defmodule Pidge.Compiler do

  @pre_code_code_include "defmodule Pidge do; def a <~ b, do: max(a, b); def pidge do ;"
  @post_code_code_include """
    end
  end
  """

  def compile(_args) do
    with(
      {:mkdir, :ok} <- {:mkdir, File.mkdir_p("release")},
      {:read, {:ok, code}} <- {:read, File.read("src/main.pj")},
      {:ok, pidge_ast} <- compile_source(code)
    ) do
      validate_ast(pidge_ast)
      prompt_files = compile_prompts(pidge_ast)

      # Copy all the prompt files under release/prompts/
      prompt_files |> Enum.each(fn filename ->
        # chop off the /src/ part of the path
        new_file_path = "release/#{String.slice(filename, 4..-1)}"
        dirname = Path.dirname(new_file_path)
        File.mkdir_p!(dirname)
        File.write!(new_file_path, File.read!(filename))
      end)

      File.write!("release/main.pjc", inspect(pidge_ast, limit: :infinity, pretty: true))
    else
      error -> raise "Failed to compile: #{inspect(error, limit: :infinity, pretty: true)}"
    end
  end

  def compile_source(code) do
    with(
      {:ok, ast } <- Code.string_to_quoted(@pre_code_code_include <> code <> @post_code_code_include),
      # Drop the module definition
      {:defmodule, [line: 1], [{:__aliases__, [line: 1], [:Pidge]}, [do: {:__block__, [], ast } ] ] } <- ast,
      # Drop the first 1 item(s0 in the ast, which are the operator
      ast <- Enum.slice(ast, 1, length(ast)),
      # Drop the function pidge wrapper
      [{:def, _, [{:pidge, _, nil}, [do: ast ] ] } ] <- ast,
      [_|_] = pidge_ast <- parse_ast(ast)
    ) do
      {:ok, pidge_ast}
    else
      error -> raise "Failed to compile: #{inspect(error, limit: :infinity, pretty: true)}"
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

  # constant defining what opts are allowed for which functions
  @allowed_opts %{
    ai_prompt: [:human_input],
    ai_pipethru: [:optional_human_input, :loopback_allowed_to],
    ai_object_extract: [:schema, :partial, :optional_human_input]
  }

  def parse_command(
    {
      {
        :.,
        _,
        [
          {_,_,[:Context]},
          :add_conversation
        ]
      }, _, [conversation_id]}) do
    [%{
      id: nil,
      method: :context_create_conversation,
      params: %{ conversation_id: conversation_id}
    }]
  end

  def parse_command(
    {
      {
        :.,
        _,
        [
          {_,_,[:Local]},
          function_name
        ]
      }, _, args}) do
    [%{
      id: nil,
      method: :local_function_call,
      params: %{ function_name: function_name, args: args }
    }]
  end

  # Handle |> pipes, just call parse_ast and concat the results
  def parse_command({:|>, _, _} = block) do
    parse_ast(block)
  end

  def parse_command(
    {:=, a,
      [
        {{:., b, [Access, :get]}, _, access_chain},
        c
      ]
      }
      ) do
    # Parse to grab the first elem if each tuple
    pidge_access_chain = access_chain |> Enum.map(&(to_string(elem(&1, 0))))

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
        {:., _, _} -> name |> collapse_dottree([])
        [""<>_|_] -> name
        x when is_atom(x) -> to_string(name)
      end

    case value do
      {{:., _line, [{:__aliases__, _, [:Local]}, _]}, _, _} ->
        parse_command(value) ++ [%{
          id: nil,
          method: :store_object,
          params: %{object_name: assign_name}
        }]
      {{:., _, _}, _, _} ->
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
      method: :foreach,
      params: %{
        expression: compile_expression(expression),
        sub_pidge_ast: sub_pidge_ast
      }
    }]
  end

  def parse_command({:fly, _, [sub_pidge_filename]}) when is_atom(sub_pidge_filename) do
    [%{
      id: nil,
      method: :fly,
      params: %{
        sub_pidge_filename: sub_pidge_filename
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
      method: :foreach,
      params: %{
        expression: compile_expression(expression),
        cases: cases
      }
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
        [%{
          id: prompt,
          method: function_name,
          params: parse_opts(function_name, %{
            conversation_id: to_string(conversation_id),
            prompt: to_string(prompt),
            format: to_string(format)
          }, opts, line)
        }]
      {_, [conversation_id, prompt]} ->
        [%{
          id: prompt,
          method: function_name,
          params: %{conversation_id: to_string(conversation_id), prompt: to_string(prompt)}
        }]
      {_, [conversation_id, prompt, opts]} ->
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

  def compile_expression(expr), do: expr

  def collapse_dottree({:., _, [a, key]}, acc) when is_atom(key) do
    collapse_dottree(a, acc) ++ [to_string(key)]
  end
  def collapse_dottree({{:., _, _} = dot, _, []}, acc) do
    collapse_dottree(dot, acc)
  end
  def collapse_dottree({
      {:., _line1, [Access, :get]},
      _line2,
      [
        dot,
        {var_key, _line3, _}
      ]
      }, acc) do
    case var_key do
      atom when is_atom(atom) -> collapse_dottree(dot, [{var_key}] ++ acc)
      _ -> collapse_dottree(dot, [{collapse_dottree(var_key,[])}] ++ acc)
    end
  end
  def collapse_dottree({{:., _line1, [Access, :get]}, _line2, [dot,""<>_ = string_key]}, acc) do
    collapse_dottree(dot, [string_key] ++ acc)
  end
  def collapse_dottree({key, _,nil}, acc) when is_atom(key) do
    [to_string(key)] ++ acc
  end
  def collapse_dottree(key, acc) when is_atom(key) do
    [to_string(key)] ++ acc
  end

  def parse_opts(function_name, params, opts, line) do
    opts = Map.new(opts)
    # if there are any disallowed opts (not in list for this function of @allowed_opts), raise a compile error
    if Map.keys(opts) |> Enum.any?(&!Enum.member?(@allowed_opts[function_name], &1)) do
      raise "PIDGE: Invalid option(s) for #{function_name} on #{inspect(line)}: #{opts |> Map.keys |> Enum.join(", ")}"
    end
    # merge opts map into params (only if in @allowed_opts)
    Map.merge(params, opts |> Map.take(@allowed_opts[function_name]))
  end

  def to_method({:., _, [{:__aliases__, _, _}, fun]}) when is_atom(fun), do: Atom.to_string(fun)
  def to_method(fun) when is_atom(fun), do: Atom.to_string(fun)

  def parse_params(fun, args, params) do
    case fun do
      {:., _, [{:__aliases__, _, _}, :add_conversation]} ->
        {"conversation_id", List.first(params)}
      _ ->
        {
          "conversation_id",
          List.first(args)
        }
    end
  end

  # Function to validate the PIDGE AST
  def validate_ast(ast) do
    # Make sure all the ID's are either nil or unique, and raise an error if not
    ids = ast |> Enum.map(&(&1.id)) |> Enum.reject(&is_nil/1)
    if ids |> Enum.uniq() |> length() != length(ids) do
      raise "PIDGE: Duplicate ID's found in AST: #{ids |> Enum.uniq() |> Enum.join(", ")}"
    end
  end

  # Function for validating the prompts referred to by the AST
  def compile_prompts(ast) do
    # For each of the commands that have a :prompt param, make sure that file exists under the prompts directory
    #  Aggregate all the missing prompt files, so we can list all that are missing
    prompt_files = ast
      |> get_all_method_calls
      |> Enum.filter(fn command ->
        Map.has_key?(command.params, :prompt)
      end)
      |> Enum.map(fn command ->
        command.params.prompt
      end)
      |> Enum.map(&("src/prompts/#{&1}.pjt"))

    missing_prompts = prompt_files
      |> Enum.reject(fn file ->
        File.exists?(file)
      end)
    if missing_prompts != [] do
      raise "PIDGE: Missing prompt files: #{missing_prompts |> Enum.join(", ")}"
    end

    prompt_files
  end

  def get_all_method_calls(pidge_ast) do
    pidge_ast
    |> Enum.map(fn command ->
      case command do
        %{params: %{sub_pidge_ast: sub_pidge_ast}} ->
          get_all_method_calls(sub_pidge_ast)
        _ -> [command]
      end
    end)
    # Flatten the list of lists
    |> List.flatten()
  end
end
