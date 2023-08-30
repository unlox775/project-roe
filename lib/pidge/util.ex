defmodule Pidge.Util do

  @line_trace false
  defmacro trace(value, opts \\ []) do
    if @line_trace do
      quote do
        IO.inspect(unquote(value), label: Keyword.get(unquote(opts), :label, to_string(elem(__ENV__.function,0)))<>" at #{__ENV__.file}:#{__ENV__.line}")
      end
    else
      quote do
        unquote(value)
      end
    end
  end

  def make_list_of_strings([]), do: []
  def make_list_of_strings([_ | _] = keys_list), do:
    Enum.map(keys_list, &to_string/1)
  def make_list_of_strings(key), do: make_list_of_strings([key])

  def make_list([]), do: []
  def make_list([_ | _] = keys_list), do: keys_list
  def make_list(key), do: make_list([key])

  def get_nested_key(state, [], default) do
    if state == nil, do: default, else: state
  end
  def get_nested_key(state, [key|tail], default) do
    case is_map(state) && Map.has_key?(state, key) do
      true -> get_nested_key(Map.get(state, key), tail, default)
      false ->
        trace({state, key, tail}, label: "get_nested_key")
        case {state, key, tail} do
          {x,"length",[]} when is_list(x) -> Enum.count(x)
          {x,idx,_} when is_list(x) and is_integer(idx) ->
            get_nested_key(Enum.at(state, idx), tail, default)
          _ -> default
        end
    end
  end

  def set_nested_key(state, [key|tail], value) do
    new_value =
      case tail do
        [] -> value
        _ -> set_nested_key(Map.get(state, key, %{}), tail, value)
      end

    Map.put(state, key, new_value)
  end

  def camel_to_snake_case(string) do
    string
    |> to_string()
    |> String.replace(~r/([A-Z])/, "_\\1")
    |> String.replace(~r/^_+/, "")
    |> String.downcase()
  end
end

# defmodule Pidge.Util do
#   def make_list_of_strings([]), do: []
#   def make_list_of_strings([_ | _] = keys_list), do:
#     Enum.map(keys_list, &to_string/1)
#   def make_list_of_strings(key), do: make_list_of_strings([key])

#   def get_nested_key(obj, [], state), do: obj
#   def get_nested_key(obj, [key|tail], state) do
#     # key = case key do
#     #   {key} when is_atom(key) ->
#     # end

#     case is_map(obj) && Map.has_key?(obj, key) do
#       true -> get_nested_key(Map.get(obj, key), tail, state)
#       false -> %{}
#     end
#   end

#   def set_nested_key(obj, [key|tail], value, state) do
#     new_value =
#       case tail do
#         [] -> value
#         _ -> set_nested_key(Map.get(obj, key, %{}), tail, value, state)
#       end

#     Map.put(obj, key, new_value)
#   end
# end
