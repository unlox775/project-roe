defmodule Pidge.FlightControl.Bird do
  use GenServer

  alias Pidge.Run
  alias Pidge.FlightControl
  alias Pidge.Runtime.RunState

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

  # Payload from harness is {:local, :main, opts}; legacy format {:new_flight, {app_name, script_name, opts}}
  def handle_cast({app_name, script_name, opts}, state) when is_map(opts) do
    do_run(app_name, script_name, opts, state)
  end
  def handle_cast({:new_flight, {app_name, script_name, opts}}, state) do
    do_run(app_name, script_name, opts, state)
  end

  defp do_run(app_name, script_name, opts, state) do
    try do
      RunState.init_session(opts)
      if (opts[:verbosity] || 0) >= 4 do
        IO.puts("[pidge:bird] do_run received opts from_step=#{inspect(opts[:from_step])} opts_keys=#{inspect(Map.keys(opts || %{}))}")
      end
      payload = Run.private__run(app_name, script_name, opts)

      FlightControl.coming_in_for_landing(payload)
      {:noreply, state}
    rescue
      error ->

        stacktrace = __STACKTRACE__ |> Enum.map(fn {mod, fun, arity, [file: file, line: line]} ->
          "    #{file}:#{line}: #{mod}.#{fun}/#{arity}}"
        end)
        |> Enum.join("\n")

        FlightControl.i_crashed("Error: #{inspect(error)}\nStacktrace: \n#{stacktrace}")
        {:noreply, state}
    end
  end
end
