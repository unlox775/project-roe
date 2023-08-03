defmodule AstCompiler do
  def parse_ast({:__block__, _, list}) do
    Enum.reduce(list, [], fn command, acc ->
      acc ++ parse_command(command)
    end)
  end
  def parse_ast({:|>, _, list}) do
    Enum.reduce(list, [], fn command, acc ->
      acc ++ parse_command(command)
    end)
  end

  # constant defining what opts are allowed for which functions
  @allowed_opts %{
    ai_prompt: [:human_input],
    ai_pipethru: [:optional_human_input, :loopback_allowed_to],
    ai_object_extract: [:schema, :partial]
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
      method: "context_create_conversation",
      params: %{ conversation_id: conversation_id}
    }]
  end

  # Handle |> pipes, just call parse_ast and concat the results
  def parse_command({:|>, _, _} = block) do
    parse_ast(block)
  end

  def parse_command(
    {:=, _,
      [
        {name, _, _},
        value
      ]
      }
      ) do
    case value do
      # If it is a pipe, we evaluate the whole chain, and then store the result
      {:|>, _, _} = sub_struct ->
        parse_ast(sub_struct) ++ [%{
          id: nil,
          method: "store_object",
          params: %{object_name: to_string(name)}
        }]
      # If it is a simple atom, we are just assigning one variable to another
      {atom,_,nil} when is_atom(atom) ->
        [%{
          id: nil,
          method: "clone_object",
          params: %{clone_from_object_name: to_string(atom), object_name: to_string(name)}
        }]
      # If the the value is a 3-elem tuple, we assume this is a function call
      {_, _, _} ->
        parse_command(value) ++ [%{
          id: nil,
          method: "store_object",
          params: %{object_name: to_string(name)}
        }]
    end
  end

  # parse function call command where the first value of the tuple is an atom
  def parse_command({function_name, _, args}) when is_atom(function_name) do
    # if function name is not in @allowed_opts, raise a compile error
    if !Map.has_key?(@allowed_opts, function_name) do
      raise "PEJJ: Invalid function name: #{function_name}"
    end

    case {function_name,args} do
      {:ai_object_extract, [conversation_id, prompt, format, opts]} ->
        [%{
          id: prompt,
          method: to_string(function_name),
          params: parse_opts(function_name, %{
            conversation_id: to_string(conversation_id),
            prompt: to_string(prompt),
            format: to_string(format)
          }, opts)
        }]
      {_, [conversation_id, prompt]} ->
        [%{
          id: prompt,
          method: to_string(function_name),
          params: %{conversation_id: to_string(conversation_id), prompt: to_string(prompt)}
        }]
      {_, [conversation_id, prompt, opts]} ->
        [%{
          id: prompt,
          method: to_string(function_name),
          params: parse_opts(function_name, %{
            conversation_id: to_string(conversation_id),
            prompt: to_string(prompt)
          }, opts)
        }]

      _ ->
        raise "PEJJ: Invalid function call: #{function_name}(#{args |> Enum.join(", ")})"
    end
  end


  # def parse_command({:=, _, [{name, _, _}, other_name]}) do
  #   [%{
  #     id: nil,
  #     method: "clone_object",
  #     params: %{clone_from_object_name: to_string(other_name), object_name: to_string(name)}
  #   }]
  # end

  def parse_opts(function_name, params, opts) do
    opts = Map.new(opts)
    # if there are any disallowed opts (not in list for this function of @allowed_opts), raise a compile error
    if Map.keys(opts) |> Enum.any?(&!Enum.member?(@allowed_opts[function_name], &1)) do
      raise "PEJJ: Invalid option(s) for #{function_name}: #{opts |> Map.keys |> Enum.join(", ")}"
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

  # Function to validate the PEJJ AST
  def validate_ast(ast) do
    # Make sure all the ID's are either nil or unique, and raise an error if not
    ids = ast |> Enum.map(&(&1.id)) |> Enum.reject(&is_nil/1)
    if ids |> Enum.uniq() |> length() != length(ids) do
      raise "PEJJ: Duplicate ID's found in AST: #{ids |> Enum.uniq() |> Enum.join(", ")}"
    end
  end

  # Function for validating the prompts referred to by the AST
  def compile_prompts(ast) do
    # For each of the commands that have a :prompt param, make sure that file exists under the prompts directory
    #  Aggregate all the missing prompt files, so we can list all that are missing
    prompt_files = ast
      |> Enum.filter(fn command ->
        Map.has_key?(command.params, :prompt)
      end)
      |> Enum.map(fn command ->
        command.params.prompt
      end)
      |> Enum.map(&("prompts/#{&1}.pjt"))

    missing_prompts = prompt_files
      |> Enum.reject(fn file ->
        File.exists?(file)
      end)
    if missing_prompts != [] do
      raise "PEJJ: Missing prompt files: #{missing_prompts |> Enum.join(", ")}"
    end

    prompt_files
  end
end
