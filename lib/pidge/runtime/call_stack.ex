defmodule Pidge.Runtime.CallStack do

  alias Pidge.Runtime.{ SessionState, RunState }

  import Pidge.Util

  def enter_closure(closure_state, {closure_code_line, loop_iteration}) do
    closure = {closure_code_line, closure_state, loop_iteration}
    case RunState.get_meta_key(:closure_states) do
      nil -> RunState.set_meta_key(:closure_states, [closure])
      closure_states -> RunState.set_meta_key(:closure_states, closure_states ++ [closure])
    end
  end

  def leave_closure() do
    closure_states = RunState.get_meta_key(:closure_states)
    RunState.set_meta_key(:closure_states, Enum.drop(closure_states, -1))
  end

  def get_stack_address(:list) do
    case RunState.get_meta_key(:closure_states) do
      nil -> []
      closure_states ->
        Enum.map(closure_states, fn {seq, _, foreach_loop_index} ->
          case foreach_loop_index do
            nil -> "block-#{seq}"
            _ -> "foreach-#{seq}[#{foreach_loop_index}]"
          end
        end)
    end
  end
  def get_stack_address(:string), do: get_stack_address(false) |> Enum.join(".")

  def get_complete_variable_namespace do
    state =
      SessionState.get()

    # merge each of the closures into the state
    case RunState.get_meta_key(:closure_states) do
      nil -> state
      closure_states ->
        Enum.reduce(closure_states, state, fn {_, closure_state, _}, state ->
          bug(2, [label: "compile_template", closure_state: closure_state])
          Map.merge(state, closure_state)
        end)
    end
  end

  def get_variable(variable_name, default \\ nil) do
    case SessionState.get_from_stack(get_stack_address(:list), variable_name) do
      nil -> default
      value -> value
    end
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
