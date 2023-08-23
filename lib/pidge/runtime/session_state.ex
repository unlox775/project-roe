defmodule Pidge.Runtime.SessionState do
  use GenServer

  import Pidge.Util

  # Client API
  def start_link(session_id), do: GenServer.start_link(__MODULE__, session_id, name: __MODULE__)
  def stop(pid), do: GenServer.stop(pid, :normal)

  # opts
  def store_object(object, object_name), do:
    GenServer.call(__MODULE__, {:store_object, object, object_name})
  def merge_into_object(object, object_name), do:
    GenServer.call(__MODULE__, {:merge_into_object, object, object_name})
  def clone_object(clone_from_object_name, object_name), do:
    GenServer.call(__MODULE__, {:clone_object, clone_from_object_name, object_name})
  def get(object_name), do: GenServer.call(__MODULE__, {:get, object_name})
  def get(), do: GenServer.call(__MODULE__, :get_contents)

  def session_id(), do: GenServer.call(__MODULE__, :session_id)

  def wipe(), do: GenServer.call(__MODULE__, :wipe)
  def set_opts(opts), do: GenServer.call(__MODULE__, {:set_opts, opts})
  def set_opt(key, value), do: GenServer.call(__MODULE__, {:set_opt, key, value})
  def delete_opt(key), do: GenServer.call(__MODULE__, {:delete_opt, key})

  def get_opts(), do: GenServer.call(__MODULE__, :get_opts)
  def get_opt(key), do: GenServer.call(__MODULE__, {:get_opt, key})
  def get_verbosity(), do: get_opt(:verbosity)

  # meta
  def set_meta(meta), do: GenServer.call(__MODULE__, {:set_meta, meta})
  def set_meta_key(key, value), do: GenServer.call(__MODULE__, {:set_meta_key, key, value})
  def delete_meta_key(key), do: GenServer.call(__MODULE__, {:delete_meta_key, key})

  def get_meta(), do: GenServer.call(__MODULE__, :get_meta)
  def get_meta_key(key), do: GenServer.call(__MODULE__, {:get_meta_key, key})


  ##########################
  ### Server Callbacks

  def init(session_id) do
    {:ok, %{session_id: session_id, contents: get_current_state(session_id)}}
  end

  defp session_id_to_filepath(session_id) do
    case session_id do
      nil -> "release/state.json"
      "" -> "release/state.json"
      _ -> "release/#{session_id}.json"
    end
  end
  # defp session_id_to_filepath(session_id, suffix) when is_atom(suffix) do
  #   case session_id do
  #     nil -> "release/state-#{suffix}.json"
  #     "" -> "release/state-#{suffix}.json"
  #     _ -> "release/#{session_id}-#{suffix}.json"
  #   end
  # end

  defp get_current_state(session_id) do
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

  def handle_call({:store_object, object, object_name}, _from, state) do
    # store the object in the state
    contents = deep_set(state.contents, object_name, object)

    # If the object is a map, store the JSON equivalent as well under json.object_name
    contents =
      case is_map(object) && (! is_list(object_name) || Enum.count(object_name) == 1) do
        true ->
          json =
            Map.get(contents, "json", %{})
            |> Map.put(to_string(object_name), Jason.encode!(object, pretty: true))
          Map.put(contents, "json", json)
        false -> contents
      end

    {:reply, object, save_state(contents, state)}
  end

  def handle_call({:merge_into_object, object, object_name}, _from, state) do
    # store the object in the state
    merged_object = Map.merge(deep_get(state.contents, object_name), object)
    contents = deep_set(state.contents, object_name, merged_object)

    # If the object is a map, store the JSON equivalet as well under json.object_name
    contents =
      case is_map(object) && (! is_list(object_name) || Enum.count(object_name) == 1) do
        true ->
          json =
            Map.get(contents, "json", %{})
            |> Map.put(to_string(object_name), Jason.encode!(merged_object, pretty: true))
          Map.put(contents, "json", json)
        false -> contents
      end

    {:reply, object, save_state(contents, state)}
  end

  def handle_call({:clone_object, clone_from_object_name, object_name}, _from, state) do
    # clone the object in the state
    clone_from = deep_get(state.contents, clone_from_object_name)
    contents = deep_set(state.contents, object_name, clone_from)

    {:reply, deep_get(contents, object_name), save_state(contents, state)}
  end

  def handle_call({:get, object_name}, _from, state) do
    {:reply, deep_get(state, object_name), state}
  end

  def handle_call(:get_contents, _from, state) do
    {:reply, state.contents, state}
  end

  def handle_call(:wipe, _from, state) do
    {:reply, :ok, save_state(%{}, state)}
  end

  def handle_call(:session_id, _from, state) do
    {:reply, state.session_id, state}
  end

  defp save_state(contents, state) do
    state = Map.put(state, :contents, contents)

    # save the state as JSON
    File.write!(session_id_to_filepath(state.session_id), Jason.encode!(state.contents, pretty: true))

    state
  end

  # quick functions for getting string-based nested key lists
  def deep_get(state, key_list) do
    get_nested_key(state, make_list_of_strings(key_list))
  end
  def deep_set(state, key_list, value) do
    set_nested_key(state, make_list_of_strings(key_list), value)
  end
end
