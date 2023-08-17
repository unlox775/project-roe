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
