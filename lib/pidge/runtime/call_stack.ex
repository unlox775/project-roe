defmodule Pidge.Runtime.CallStack do

  alias Pidge.Runtime.{ SessionState, RunState }

  import Pidge.Util

  def enter_closure(closure_state, block_type, closure_code_line, loop_iteration) do
    closure = {block_type, closure_code_line, loop_iteration}
    case RunState.get_meta_key(:closure_states) do
      nil -> RunState.set_meta_key(:closure_states, [closure])
      closure_states -> RunState.set_meta_key(:closure_states, closure_states ++ [closure])
    end

    # set each of the keys in the closure state with set_variable
    Enum.each(closure_state, fn {key, value} ->
      set_variable(key, value)
    end)
  end

  def leave_closure() do
    closure_states = RunState.get_meta_key(:closure_states)
    RunState.set_meta_key(:closure_states, Enum.drop(closure_states, -1))
  end

  def get_stack_address(:list) do
    case RunState.get_meta_key(:closure_states) do
      nil -> []
      closure_states ->
        Enum.map(closure_states, fn {block_type, seq, iteration_index} ->
          case block_type do
            :if -> "block-#{seq}"
            :foreach -> "foreach-#{seq}[#{iteration_index}]"
            :case -> "case-#{seq}[#{iteration_index}]"
          end
        end)
    end
  end
  def get_stack_address(:string), do: get_stack_address(false) |> Enum.join(".")

  def get_complete_variable_namespace do
    global = SessionState.get()
    stack_state = SessionState.get_stack_state()

    # merge each of the closures into the state
    case RunState.get_meta_key(:closure_states) do
      nil -> global
      _ ->
        Enum.reduce(get_stack_address(:list), global, fn frame_id, state ->
          bug(5, [label: "get_complete_variable_namespace", closure_state: Map.get(stack_state, frame_id, %{})])
          Map.merge(state, Map.get(stack_state, frame_id, %{}))
        end)
    end
  end

  def get_variable(variable_name, default \\ nil) do
    return =
      case SessionState.get_from_stack(get_stack_address(:list), variable_name) do
        nil -> default
        value -> value
      end
    bug(4, [label: "get_variable", var: variable_name, resulting_value: return])

    return
  end

  def set_variable(variable_name, value) do
    SessionState.store_in_stack(get_stack_address(:list), variable_name, value)
  end

  def clone_variable(clone_from_object_name, object_name) do
    clone_from = get_variable(clone_from_object_name)
    set_variable(object_name, clone_from)

    clone_from
  end

  def merge_into_variable(clone_from_object_name, merge_into_object_name) do
    clone_from_object = get_variable(clone_from_object_name)
    merged_object = Map.merge(get_variable(merge_into_object_name, %{}), clone_from_object)
    set_variable(merge_into_object_name, merged_object)

    merged_object
  end


  # quick functions for getting string-based nested key lists
  def deep_get(state, key_list, default \\ nil) do
    get_nested_key(state, make_list_of_strings(key_list), default)
  end
  def deep_set(state, key_list, value) do
    set_nested_key(state, make_list_of_strings(key_list), value)
  end
  defp bug(level, stuff_to_debug), do: Pidge.Run.bug(level, stuff_to_debug)
end
