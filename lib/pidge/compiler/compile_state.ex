defmodule Pidge.Compiler.CompileState do
  use GenServer

  # Client API

  def start_link(initial_meta), do: GenServer.start_link(__MODULE__, initial_meta, name: __MODULE__)
  def stop(pid), do: GenServer.stop(pid, :normal)

  # meta
  def set_meta(meta), do: GenServer.call(__MODULE__, {:set_meta, meta})
  def set_meta_key(key, value), do: GenServer.call(__MODULE__, {:set_meta_key, key, value})
  def push_meta_key(key, value), do: GenServer.call(__MODULE__, {:push_meta_key, key, value})
  def delete_meta_key(key), do: GenServer.call(__MODULE__, {:delete_meta_key, key})

  def get_meta(), do: GenServer.call(__MODULE__, :get_meta)
  def get_meta_key(key), do: GenServer.call(__MODULE__, {:get_meta_key, key})
  def shift_meta_key(key), do: GenServer.call(__MODULE__, {:shift_meta_key, key})

  ##########################
  ### Server Callbacks

  def init(%{} = initial_meta), do: {:ok, %{meta: initial_meta}}

  # meta
  def handle_call({:set_meta, %{} = meta}, _from, state), do: {:reply, meta, Map.put(state, :meta, meta)}
  def handle_call({:set_meta_key, key, value}, _from, state), do: {:reply, :ok, Map.put(state, :meta, Map.put(state.meta, key, value))}
  def handle_call({:push_meta_key, key, value}, _from, state) do
    current_state =
      case Map.has_key?(state.meta, key) do
        true -> Map.get(state.meta, key)
        false -> []
      end
      |> case do
        [_|_] = s -> s
        [] -> []
        s -> raise "Tried to push a non-list meta key: #{inspect(key)} => #{inspect(s)}"
      end

    {:reply, :ok, Map.put(state, :meta, Map.put(state.meta, key, current_state ++ [value]))}
  end
  def handle_call({:delete_meta_key, key}, _from, state) do
    case Map.has_key?(state.meta, key) do
      true -> {:reply, :ok, state |> Map.put(:meta, Map.delete(state.meta, key))}
      false -> {:reply, :ok, state}
    end
  end

  def handle_call(:get_meta, _from, state), do: {:reply, state.meta, state}
  def handle_call({:get_meta_key, key}, _from, state) do
    case Map.has_key?(state.meta, key) do
      true -> {:reply, Map.get(state.meta, key), state}
      false -> {:reply, nil, state}
    end
  end
  def handle_call({:shift_meta_key, key}, _from, state) do
    case Map.has_key?(state.meta, key) do
      true ->
        case Map.get(state.meta, key) do
          [head | tail] ->
            {:reply, head, state |> Map.put(:meta, Map.put(state.meta, key, tail))}
          [] -> {:reply, nil, state}
        end
      false -> {:reply, nil, state}
    end
  end

end
