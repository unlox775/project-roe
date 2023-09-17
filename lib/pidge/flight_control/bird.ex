defmodule Pidge.FlightControl.Bird do
  use GenServer

  alias Pidge.Run
  alias Pidge.FlightControl

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def stop do
    GenServer.stop(__MODULE__)
  end

  # Server Callbacks

  def init(_ops) do
    {:ok, %{}}
  end

  def handle_cast({:new_flight, {app_name, script_name}}, state) do
    try do
      payload = Run.private__run(app_name, script_name)

      FlightControl.coming_in_for_landing(payload)
      {:noreply, state}
    rescue
      error ->
        FlightControl.i_crashed("Error: #{inspect(error)}")
        {:noreply, state}
    end
  end
end
