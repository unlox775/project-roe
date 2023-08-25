defmodule Pidge.Runtime.RunState do
  use GenServer

  # Client API

  def start_link(initial_opts), do: GenServer.start_link(__MODULE__, initial_opts, name: __MODULE__)
  def stop(pid), do: GenServer.stop(pid, :normal)

  # opts
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

  def reset_for_new_run() do
    no_reset_opts = [:verbosity, :session]
    get_opts() |> Map.take(no_reset_opts) |> set_opts()
    set_meta(%{})
  end

  ##########################
  ### Server Callbacks

  def init(%{} = initial_opts), do: {:ok, %{opts: initial_opts, meta: %{}}}

  # opts
  def handle_call({:set_opts, %{} = opts}, _from, state), do: {:reply, opts, Map.put(state, :opts, opts)}
  def handle_call({:set_opt, key, value}, _from, state), do: {:reply, :ok, Map.put(state, :opts, Map.put(state.opts, key, value))}
  def handle_call({:delete_opt, key}, _from, state) do
    case Map.has_key?(state.opts, key) do
      true -> {:reply, :ok, state |> Map.put(:opts, Map.delete(state.opts, key))}
      false -> {:reply, :ok, state}
    end
  end

  def handle_call(:get_opts, _from, state), do: {:reply, state.opts, state}
  def handle_call({:get_opt, key}, _from, state) do
    case Map.has_key?(state.opts, key) do
      true -> {:reply, Map.get(state.opts, key), state}
      false -> {:reply, nil, state}
    end
  end

  # meta
  def handle_call({:set_meta, %{} = meta}, _from, state), do: {:reply, meta, Map.put(state, :meta, meta)}
  def handle_call({:set_meta_key, key, value}, _from, state), do: {:reply, :ok, Map.put(state, :meta, Map.put(state.meta, key, value))}
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

end
