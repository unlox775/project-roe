defmodule Pidge.Runtime.SessionState do
  use GenServer

  import Pidge.Util
  require IEx
  alias Pidge.ObjectPatch

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
  def last_revision(), do: GenServer.call(__MODULE__, :last_revision)

  def save(revision_label), do: GenServer.call(__MODULE__, {:save, revision_label})
  def revert_to_revision(revision_label), do: GenServer.call(__MODULE__, {:revert_to_revision, revision_label})

  def wipe(), do: GenServer.call(__MODULE__, :wipe)

  # stack state
  def get_stack_state(), do: GenServer.call(__MODULE__, :get_stack_state)
  def get_from_stack_frame(frame_id, object_name), do: GenServer.call(__MODULE__, {:get_from_stack_frame, frame_id, object_name})
  def get_from_stack(frame_ids, object_name), do: GenServer.call(__MODULE__, {:get_from_stack, frame_ids |> Enum.reverse(), object_name})
  def store_in_stack(frame_ids, object_name, object) when is_list(frame_ids), do: GenServer.call(__MODULE__, {:store_in_stack, frame_ids, object_name, object})


  ##########################
  ### Server Callbacks

  def init(session_id) do
    {stack_state, global} = __MODULE__.get_current_state(session_id)
    {rev_chain, _patch_chain, _boneyard} = __MODULE__.get_vc_chain(session_id)
    {:ok, %{
      session_id: session_id,
      stack_state: stack_state,
      global: global,
      last_revision: rev_chain |> List.last()
    }}
  end

  defp session_id_to_filepath(session_id, suffix \\ ".json") do
    case session_id do
      nil -> "release/state#{suffix}"
      "" -> "release/state#{suffix}"
      _ -> "release/#{session_id}#{suffix}"
    end
  end
  # defp session_id_to_filepath(session_id, suffix) when is_atom(suffix) do
  #   case session_id do
  #     nil -> "release/state-#{suffix}.json"
  #     "" -> "release/state-#{suffix}.json"
  #     _ -> "release/#{session_id}-#{suffix}.json"
  #   end
  # end

  def get_current_state(session_id) do
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

  def get_vc_chain(session_id) do
    # Load state from file
    case File.read(session_id_to_filepath(session_id,"-vc.erlbin")) do
      {:ok, serialized} ->
        case :erlang.binary_to_term(serialized) do
          %{rev_chain: rev_chain, patch_chain: patch_chain, boneyard: boneyard} -> {rev_chain, patch_chain, boneyard}
          error -> raise "Failed to load VC state, decoding serialized erlang: #{inspect(error)}"
        end
      {:error, :enoent} -> {[],[],[]}
      error -> raise "Failed to load VC state: #{inspect(error)}"
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
    # Remove the state file
    File.rm(session_id_to_filepath(state.session_id))
    # remove the vc file
    File.rm(session_id_to_filepath(state.session_id, "-vc.erlbin"))

    {:ok, empty_state} = init(state.session_id)
    {:reply, :ok, empty_state}
  end

  def handle_call(:session_id, _from, state) do
    {:reply, state.session_id, state}
  end

  def handle_call(:last_revision, _from, state) do
    {:reply, state.last_revision, state}
  end

  # The idea is to store in the deepest stack frame first, if the key exists there
  # Then if not, fall back to less and less deep.  Last resort, store in global
  def handle_call({:store_in_stack, [deepest|_] = reverse_frame_ids, object_name, object}, from, state) do
    variable_key =
      case object_name do
        [x|_] -> x
        _ -> object_name
      end
      |> to_string()

    scan =
      reverse_frame_ids
      |> Enum.map(&(Map.has_key?(Map.get(state.stack_state, &1, %{}), variable_key)))

    {:reply, global, _} = handle_call(:get_global, from, state)
    global_has_key = Map.has_key?(global, variable_key)
    case Enum.find_index(scan ++ [global_has_key], &(&1 == true)) do
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

  def handle_call({:save, revision_label}, _from, state) do
    # Read the current state from the file
    {cur_stack_state, cur_global} = __MODULE__.get_current_state(state.session_id)
    {rev_chain, patch_chain, boneyard} = __MODULE__.get_vc_chain(state.session_id)
    current_state = %{stack_state: cur_stack_state, global: cur_global}

    # Assemble new state
    new_state = %{ stack_state: state.stack_state, global: state.global }

    # Raise if the revision label is already in the chain
    if Enum.member?(rev_chain, revision_label) do
      raise "Revision label #{revision_label} already exists in the chain"
    end

    # compute diff
    diff = ObjectPatch.diff_objects(current_state, new_state)
    rev_chain = rev_chain ++ [revision_label]
    patch_chain = patch_chain ++ [diff]

    # Create the directory if it doesn't exist
    state_file = session_id_to_filepath(state.session_id)
    parent_dir = Path.dirname(state_file)
    case File.dir?(parent_dir) do
      true -> :ok
      false -> File.mkdir_p!(parent_dir)
    end

    # save the state as JSON
    File.write!(
      state_file,
      Jason.encode!(new_state, pretty: true)
      )
    File.write!(
      session_id_to_filepath(state.session_id, "-vc.erlbin"),
      :erlang.term_to_binary(%{rev_chain: rev_chain, patch_chain: patch_chain, boneyard: boneyard})
      )

    {:reply, :ok, state}
  end

  def handle_call({:revert_to_revision, revision_label}, _from, state) do
    # Read the current state from the file
    {cur_stack_state, cur_global} = __MODULE__.get_current_state(state.session_id)
    cur_state = %{stack_state: cur_stack_state, global: cur_global}
    {rev_chain, patch_chain, boneyard} = __MODULE__.get_vc_chain(state.session_id)

    # Raise if the revision label is not in the chain
    if !Enum.member?(rev_chain, revision_label) do
      raise "Revision label #{revision_label} does not exist in the chain"
    end

    # Find the index of the revision label
    idx = Enum.find_index(rev_chain, &(&1 == revision_label))
    count_of_revs_to_revert = Enum.count(rev_chain) - idx - 1

    # Get list of revisions to revert (not including the revision to revert to)
    revs_to_revert = Enum.take(rev_chain, count_of_revs_to_revert * -1)
    new_rev_chain = Enum.drop(rev_chain, count_of_revs_to_revert * -1)
    patches_to_revert = Enum.take(patch_chain, count_of_revs_to_revert * -1)
    new_patch_chain = Enum.drop(patch_chain, count_of_revs_to_revert * -1)

    # Apply the patches in reverse order, to the current state
    new_state =
      patches_to_revert
      |> Enum.reverse()
      |> Enum.reduce(cur_state, fn patch, new_state ->
        ObjectPatch.patch_object(new_state, patch, true)
      end)

    # Store what we are culling in the boneyard
    boneyard = boneyard ++ %{
      revision_label: revision_label,
      reverted_revisions: revs_to_revert,
      reverted_patches: patches_to_revert,
      idx: idx
    }

    # save the state as JSON
    File.write!(
      session_id_to_filepath(state.session_id),
      Jason.encode!(new_state, pretty: true)
      )
    File.write!(
      session_id_to_filepath(state.session_id, "-vc.erlbin"),
      Jason.encode!(%{rev_chain: new_rev_chain, patch_chain: new_patch_chain, boneyard: boneyard}, pretty: true)
      )

    {:reply, :ok, %{
      session_id: state.session_id,
      stack_state: new_state.stack_state,
      global: new_state.global,
      last_revision: new_rev_chain |> List.last()
    }}
  end

  # Internal Methods

  defp update_namespace_key(namespace, key_address, value) do
    namespace = deep_set(namespace, key_address, value)

    variable_key =
      case key_address do
        [x|_] -> x
        _ -> key_address
      end
      |> to_string()
      |> trace()

    # If the object is a map, store the JSON equivalent as well under json.key_address
    case is_map(namespace[variable_key]) do
      true ->
        json =
          Map.get(namespace, "json", %{})
          |> Map.put(to_string(variable_key), Jason.encode!(namespace[variable_key], pretty: true))
        Map.put(namespace, "json", json)
      false -> namespace
    end
  end

  defp save_global(global, state), do: state |> Map.put(:global, global)
  # defp save_stack_state(stack_state, state), do: state |> Map.put(:stack_state, stack_state)
  defp save_frame_state(frame_id, frame_state, state), do: state |> Map.put(:stack_state, Map.put(state.stack_state, frame_id, frame_state))

  # quick functions for getting string-based nested key lists
  def deep_get(state, key_list, default \\ nil) do
    # get_nested_key(state, make_list(key_list |> trace()), default)
    get_nested_key(state, atoms_to_strings(key_list |> trace()) |> trace(label: "after a2s"), default) |> trace(label: "deep_get result")
  end
  def deep_set(state, key_list, value) do
    # set_nested_key(state, make_list(key_list |> trace()), value)
    set_nested_key(state, atoms_to_strings(key_list |> trace()) |> trace(label: "after a2s"), value) |> trace(label: "deep_set result")
  end
end
