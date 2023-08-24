defmodule Pidge.Runtime.SessionState do
  use GenServer

  import Pidge.Util

  # Client API
  def start_link(session_id), do: GenServer.start_link(__MODULE__, session_id, name: __MODULE__)
  def stop(pid), do: GenServer.stop(pid, :normal)

  # global state
  def store_object(object_name, object), do:
    GenServer.call(__MODULE__, {:store_object, object_name, object})
  def merge_into_object(clone_from_object_name, object_name), do:
    GenServer.call(__MODULE__, {:merge_into_object, clone_from_object_name, object_name})
  def clone_object(clone_from_object_name, object_name), do:
    GenServer.call(__MODULE__, {:clone_object, clone_from_object_name, object_name})
  def get(object_name), do: GenServer.call(__MODULE__, {:get, object_name})
  def get(), do: GenServer.call(__MODULE__, :get_global)

  def session_id(), do: GenServer.call(__MODULE__, :session_id)

  def wipe(), do: GenServer.call(__MODULE__, :wipe)

  # stack state
  def get_stack_state(), do: GenServer.call(__MODULE__, :get_stack_state)
  def get_from_stack_frame(frame_id, object_name), do: GenServer.call(__MODULE__, {:get_from_stack_frame, frame_id, object_name})
  def get_from_stack(frame_ids, object_name), do: GenServer.call(__MODULE__, {:get_from_stack, frame_ids |> Enum.reverse(), object_name})
  def store_in_stack(frame_ids, object_name, object) when is_list(frame_ids), do: GenServer.call(__MODULE__, {:store_in_stack, frame_ids, object_name, object})


  ##########################
  ### Server Callbacks

  def init(session_id) do
    {stack_state, global} = get_current_state(session_id)
    {:ok, %{session_id: session_id, stack_state: stack_state, global: global}}
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
          {:ok, %{"stack_state" => stack_state, "global" => global}} -> {stack_state, global}
          {:ok, global} -> {%{}, global}
          error -> raise "Failed to load state, decoding JSON: #{inspect(error)}"
        end
      {:error, :enoent} -> {%{},%{}}
      error -> raise "Failed to load state: #{inspect(error)}"
    end
  end

  def handle_call({:store_object, object_name, object}, _from, state) do
    # store the object in the state
    global = update_namespace_key(state.global, object_name, object)

    {:reply, object, save_global(global, state)}
  end

  def handle_call({:merge_into_object, clone_from_object_name, object_name}, _from, state) do
    # store the object in the state
    clone_from_object = deep_get(state.global, clone_from_object_name, %{})
    merged_object = Map.merge(deep_get(state.global, object_name, %{}), clone_from_object)
    global = update_namespace_key(state.global, object_name, merged_object)

    {:reply, merged_object, save_global(global, state)}
  end

  def handle_call({:clone_object, clone_from_object_name, object_name}, _from, state) do
    # clone the object in the state
    clone_from = deep_get(state.global, clone_from_object_name)
    global = update_namespace_key(state.global, object_name, clone_from)

    {:reply, deep_get(global, object_name), save_global(global, state)}
  end

  def handle_call({:get, object_name}, _from, state) do
    {:reply, deep_get(state.global, object_name), state}
  end
  def handle_call({:get_from_stack_frame, frame_id, object_name}, _from, state) do
    {:reply, deep_get(Map.get(state.stack_state, frame_id, %{}), object_name), state}
  end

  def handle_call(:get_global, _from, state), do: {:reply, state.global, state}
  def handle_call(:get_stack_state, _from, state), do: {:reply, state.stack_state, state}

  def handle_call(:wipe, _from, state) do
    {:reply, :ok, state |> Map.put(:global, %{}) |> Map.put(:stack_state, %{}) |> save()}
  end

  def handle_call(:session_id, _from, state) do
    {:reply, state.session_id, state}
  end

  # The idea is to store in the deepest stack frame first, if the key exists there
  # Then if not, fall back to less and less deep.  Last resort, store in global
  def handle_call({:store_in_stack, [deepest|_] = reverse_frame_ids, object_name, object}, from, state) do
    variable_key =
      case object_name do
        [x|_] -> x
        _ -> object_name
      end

    scan =
      reverse_frame_ids
      |> Enum.map(&(Map.has_key?(Map.get(state.stack_state, &1, %{}), variable_key)))

    global = handle_call(:get_global, from, state)
    case Enum.find_index(scan ++ [global], &(&1 == true)) do
      nil ->
        # New variable! If we didn't find the key in any of the frames, store it in the deepest state
        frame = update_namespace_key(Map.get(state.stack_state, deepest, %{}), object_name, object)
        {:reply, object, save_frame_state(deepest, frame, state)}
      frame_idx ->
        # If we did find the key in a frame, store it in that frame (or global)
        case Enum.at(reverse_frame_ids, frame_idx, :global) do
          :global ->
            handle_call({:store_object, object_name, object}, from, state)
          frame_id ->
            frame = update_namespace_key(Map.get(state.stack_state, frame_id, %{}), object_name, object)
            {:reply, object, save_frame_state(frame_id, frame, state)}
      end
    end
  end
  def handle_call({:store_in_stack, [] = _reverse_frame_ids, object_name, object}, from, state) do
    handle_call({:store_object, object_name, object}, from, state)
  end

  def handle_call({:get_from_stack, [deepest|shallower_frame_ids] = _reverse_frame_ids, object_name}, from, state) do
    variable_key =
      case object_name do
        [x|_] -> x
        _ -> object_name
      end

    # Check to see if this key is in the deepest frame
    cond do
      Map.has_key?(state.stack_state, deepest) && Map.has_key?(state.stack_state[deepest], variable_key) ->
        handle_call({:get_from_stack_frame, deepest, object_name}, from, state)
      true ->
        handle_call({:get_from_stack, shallower_frame_ids, object_name}, from, state)
    end
  end
  def handle_call({:get_from_stack, [] = _reverse_frame_ids, object_name}, from, state) do
    handle_call({:get, object_name}, from, state)
  end

  # Internal Methods

  defp update_namespace_key(namespace, key_address, value) do
    namespace = deep_set(namespace, key_address, value)

    # If the object is a map, store the JSON equivalet as well under json.key_address
    case is_map(value) && ! is_list(key_address) do
      true ->
        json =
          Map.get(namespace, "json", %{})
          |> Map.put(to_string(key_address), Jason.encode!(value, pretty: true))
        Map.put(namespace, "json", json)
      false -> namespace
    end
  end

  defp save_global(global, state), do: state |> Map.put(:global, global) |> save()
  # defp save_stack_state(stack_state, state), do: state |> Map.put(:stack_state, stack_state) |> save()
  defp save_frame_state(frame_id, frame_state, state), do: state |> Map.put(:stack_state, Map.put(state.stack_state, frame_id, frame_state)) |> save()
  defp save(state) do
    # save the state as JSON
    File.write!(
      session_id_to_filepath(state.session_id),
      Jason.encode!(%{
        global: state.global,
        stack_state: state.stack_state
        }, pretty: true)
      )

    state
  end

  # quick functions for getting string-based nested key lists
  def deep_get(state, key_list, default \\ nil) do
    get_nested_key(state, make_list_of_strings(key_list), default)
  end
  def deep_set(state, key_list, value) do
    set_nested_key(state, make_list_of_strings(key_list), value)
  end
end
