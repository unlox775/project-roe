defmodule Pidge.Util do
  def make_list_of_strings([]), do: []
  def make_list_of_strings([_ | _] = keys_list), do:
    Enum.map(keys_list, &to_string/1)
  def make_list_of_strings(key), do: make_list_of_strings([key])

  def get_nested_key(state, []), do: state
  def get_nested_key(state, [key|tail]) do
    case is_map(state) && Map.has_key?(state, key) do
      true -> get_nested_key(Map.get(state, key), tail)
      false -> %{}
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
