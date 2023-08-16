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

  def get_opts() do
    GenServer.call(__MODULE__, :get_opts)
  end

  # Server Callbacks

  def init(initial_opts) do
    {:ok, %{opts: initial_opts}}
  end

  def handle_call({:set_opts, opts}, _from, state) do
    {:reply, :ok, Map.put(state, :opts, opts)}
  end

  def handle_call(:get_opts, _from, state) do
    {:reply, state.opts, state}
  end
end
