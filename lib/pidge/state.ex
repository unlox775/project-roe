defmodule Pidge.State do
  import Pidge.Util

  def session_id_to_filepath(session_id) do
    case session_id do
      nil -> "release/state.json"
      "" -> "release/state.json"
      _ -> "release/#{session_id}.json"
    end
  end
  def session_id_to_filepath(session_id, suffix) when is_atom(suffix) do
    case session_id do
      nil -> "release/state-#{suffix}.json"
      "" -> "release/state-#{suffix}.json"
      _ -> "release/#{session_id}-#{suffix}.json"
    end
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
    state = deep_set(state, object_name, object)

    # If the object is a map, store the JSON equivalent as well under json.object_name
    state =
      case is_map(object) && (! is_list(object_name) || Enum.count(object_name) == 1) do
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
    merged_object = Map.merge(deep_get(state, object_name), object)
    state = deep_set(state, object_name, merged_object)

    # If the object is a map, store the JSON equivalet as well under json.object_name
    state =
      case is_map(object) && (! is_list(object_name) || Enum.count(object_name) == 1) do
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
    clone_from = deep_get(state, clone_from_object_name)
    state = deep_set(state, object_name, clone_from)
    save_state(state, session_id)

    deep_get(state, object_name)
  end

  def get(object_name, session_id) do
    # get the current state
    state = get_current_state(session_id)

    # clone the object in the state
    deep_get(state, object_name)
  end

  def wipe(session_id) do
    save_state(%{}, session_id)
  end

  defp save_state(state, session_id) do
    # save the state as JSON
    File.write!(session_id_to_filepath(session_id), Jason.encode!(state, pretty: true))
  end

  # quick functions for getting string-based nested key lists
  def deep_get(state, key_list) do
    get_nested_key(state, make_list_of_strings(key_list))
  end
  def deep_set(state, key_list, value) do
    set_nested_key(state, make_list_of_strings(key_list), value)
  end
end
