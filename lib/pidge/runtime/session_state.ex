defmodule Pidge.Runtime.SessionState do
  use GenServer

  import Pidge.Util

  # Client API
  def start_link(session_id), do: GenServer.start_link(__MODULE__, session_id, name: __MODULE__)
  def stop(pid), do: GenServer.stop(pid, :normal)

  # opts
  def store_object(object, object_name), do:
    GenServer.call(__MODULE__, {:store_object, object, object_name})
  def merge_into_object(clone_from_object_name, object_name), do:
    GenServer.call(__MODULE__, {:merge_into_object, clone_from_object_name, object_name})
  def clone_object(clone_from_object_name, object_name), do:
    GenServer.call(__MODULE__, {:clone_object, clone_from_object_name, object_name})
  def get(object_name), do: GenServer.call(__MODULE__, {:get, object_name})
  def get(), do: GenServer.call(__MODULE__, :get_global)

  def session_id(), do: GenServer.call(__MODULE__, :session_id)

  def wipe(), do: GenServer.call(__MODULE__, :wipe)


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

  def handle_call({:store_object, object, object_name}, _from, state) do
    # store the object in the state
    global = deep_set(state.global, object_name, object)

    # If the object is a map, store the JSON equivalent as well under json.object_name
    global =
      case is_map(object) && (! is_list(object_name) || Enum.count(object_name) == 1) do
        true ->
          json =
            Map.get(global, "json", %{})
            |> Map.put(to_string(object_name), Jason.encode!(object, pretty: true))
          Map.put(global, "json", json)
        false -> global
      end

    {:reply, object, save_global(global, state)}
  end

  def handle_call({:merge_into_object, clone_from_object_name, object_name}, _from, state) do
    # store the object in the state
    clone_from_object = deep_get(state.global, clone_from_object_name, %{})
    merged_object = Map.merge(deep_get(state.global, object_name, %{}), clone_from_object)
    global = deep_set(state.global, object_name, merged_object)

    # If the object is a map, store the JSON equivalet as well under json.object_name
    global =
      case is_map(merged_object) && (! is_list(object_name) || Enum.count(object_name) == 1) do
        true ->
          json =
            Map.get(global, "json", %{})
            |> Map.put(to_string(object_name), Jason.encode!(merged_object, pretty: true))
          Map.put(global, "json", json)
        false -> global
      end

    {:reply, merged_object, save_global(global, state)}
  end

  def handle_call({:clone_object, clone_from_object_name, object_name}, _from, state) do
    # clone the object in the state
    clone_from = deep_get(state.global, clone_from_object_name)
    global = deep_set(state.global, object_name, clone_from)

    {:reply, deep_get(global, object_name), save_global(global, state)}
  end

  def handle_call({:get, object_name}, _from, state) do
    {:reply, deep_get(state.global, object_name), state}
  end

  def handle_call(:get_global, _from, state) do
    {:reply, state.global, state}
  end

  def handle_call(:wipe, _from, state) do
    {:reply, :ok, state |> Map.put(:global, %{}) |> Map.put(:stack_state, %{}) |> save()}
  end

  def handle_call(:session_id, _from, state) do
    {:reply, state.session_id, state}
  end

  defp save_global(global, state), do: state |> Map.put(:global, global) |> save()
  defp save_stack_state(stack_state, state), do: state |> Map.put(:stack_state, stack_state) |> save()
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
