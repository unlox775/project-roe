defmodule Pidge.State do
  def session_id_to_filepath(session_id) do
    "release/#{session_id}.json"
  end

  def get_current_state(session_id) do
    # Load state from file
    case File.read(session_id_to_filepath(session_id)) do
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

    # If the object is a map, store the JSON equivalet as well under json.object_name
    state =
    case is_map(object) do
      true ->
        existing_json = if Map.has_key?(state, "json"), do: Map.get(state, "json"), else: %{}
        Map.put(state, :json, Map.put(existing_json,object_name, Jason.encode!(object, pretty: true)))
      false -> state
    end

    save_state(state, session_id)

    object
  end

  def merge_into_object(object, object_name, session_id) do
    # get the current state
    state = get_current_state(session_id)

    # store the object in the state
    merged_object = Map.merge(Map.get(state, to_string(object_name)), object)
    state = Map.put(state, to_string(object_name), merged_object)

    # If the object is a map, store the JSON equivalet as well under json.object_name
    state =
      case is_map(object) do
        true ->
          existing_json = if Map.has_key?(state, "json"), do: Map.get(state, "json"), else: %{}
          Map.put(state, :json, Map.put(existing_json,object_name, Jason.encode!(merged_object, pretty: true)))
        false -> state
      end

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

  def wipe(session_id) do
    save_state(%{}, session_id)
  end

  defp save_state(state, session_id) do
    # save the state as JSON
    File.write!(session_id_to_filepath(session_id), Jason.encode!(state, pretty: true))
  end
end
