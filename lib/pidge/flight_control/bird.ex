defmodule Pidge.FlightControl.Bird do
  use GenServer

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def stop do
    GenServer.stop(__MODULE__)
  end

  def execute_script(script) do
    GenServer.call(__MODULE__, {:execute_script, script})
  end

  # Server Callbacks

  def init(_ops) do
    {:ok, %{}}
  end

  def handle_call({:execute_script, script}, _from, state) do
    IO.inspect(script)

    {:reply, :ok, state}
  end
end
