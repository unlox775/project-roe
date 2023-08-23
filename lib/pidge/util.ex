defmodule Pidge.Util do
  def make_list_of_strings([]), do: []
  def make_list_of_strings([_ | _] = keys_list), do:
    Enum.map(keys_list, &to_string/1)
  def make_list_of_strings(key), do: make_list_of_strings([key])

  def get_nested_key(state, [], default) do
    if state == nil, do: default, else: state
  end
  def get_nested_key(state, [key|tail], default) do
    case is_map(state) && Map.has_key?(state, key) do
      true -> get_nested_key(Map.get(state, key), tail, default)
      false -> default
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
