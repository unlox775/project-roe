defmodule Pidge.Runtime.RunState do
  use GenServer

  # Client API

  def start_link(initial_opts) do
    GenServer.start_link(__MODULE__, initial_opts, name: __MODULE__)
  end

  def set_opts(opts) do
    GenServer.call(__MODULE__, {:set_opts, opts})
    opts
  end

  def set_opt(key, value) do
    GenServer.call(__MODULE__, {:set_opt, key, value})
    value
  end

  def delete_opt(key) do
    GenServer.call(__MODULE__, {:delete_opt, key})
    :ok
  end

  def get_opts() do
    GenServer.call(__MODULE__, :get_opts)
  end

  def get_opt(key) do
    GenServer.call(__MODULE__, {:get_opt, key})
  end

  def get_verbosity() do
    get_opt(:verbosity)
  end

  # Server Callbacks

  def init(%{} = initial_opts) do
    {:ok, %{opts: initial_opts}}
  end

  def handle_call({:set_opts, %{} = opts}, _from, state) do
    {:reply, :ok, Map.put(state, :opts, opts)}
  end

  def handle_call({:set_opt, key, value} = msg, _from, state) do
    IO.inspect(msg, label: "set_opt MSG")
    {:reply, :ok, Map.put(state, :opts, Map.put(state.opts, key, value)) |> IO.inspect(label: "set_opt")}
  end

  def handle_call({:delete_opt, key}, _from, state) do
    case Map.has_key?(state.opts, key) do
      true -> {:reply, :ok, state |> Map.put(:opts, Map.delete(state.opts, key))}
      false -> {:reply, :ok, state}
    end
  end

  def handle_call(:get_opts, _from, state) do
    {:reply, state.opts, state}
  end

  def handle_call({:get_opt, key}, _from, state) do
    case Map.has_key?(state.opts, key) do
      true -> {:reply, Map.get(state.opts, key), state}
      false -> {:reply, nil, state}
    end
  end
end
