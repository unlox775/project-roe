defmodule Pidge.State do
  def get_current_state(session_id) do
    # Load state from release/#{session_id}.json
    case File.read("release/#{session_id}.json") do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, state} -> state
          error -> raise "Failed to load state, decoding JSON: #{inspect(error)}"
        end
      {:error, :enoent} -> %{}
      error -> raise "Failed to load state: #{inspect(error)}"
    end
  end

  def store_object(object, object_name, session_id) do
    # get the current state
    state = get_current_state(session_id)

    # store the object in the state
    state = Map.put(state, to_string(object_name), object)
    save_state(state, session_id)

    object
  end

  def merge_into_object(object, object_name, session_id) do
    # get the current state
    state = get_current_state(session_id)

    # store the object in the state
    state = Map.put(state, to_string(object_name), Map.merge(Map.get(state, to_string(object_name)), object))
    save_state(state, session_id)

    object
  end

  def clone_object(clone_from_object_name, object_name, session_id) do
    # get the current state
    state = get_current_state(session_id)

    # clone the object in the state
    state = Map.put(state, to_string(object_name), Map.get(state, to_string(clone_from_object_name)))
    save_state(state, session_id)

    Map.get(state, to_string(object_name))
  end

  defp save_state(state, session_id) do
    # save the state as JSON in release/state.json
    File.write!("release/#{session_id}.json", Jason.encode!(state, pretty: true))
  end
end
