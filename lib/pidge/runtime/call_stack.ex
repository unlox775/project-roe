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

  def get_stack_address(false) do
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
  def get_stack_address(true), do: get_stack_address(false) |> Enum.join(".")

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

  def get_variable(variable_name) do
    # Really inefficient way, but it works for now
    state =
      get_complete_variable_namespace()

    deep_get(state, variable_name)
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
