defmodule Pidge.FlightControl do
  use GenServer

  # Client API
  def start_link(initial_opts \\ []), do: GenServer.start_link(__MODULE__, initial_opts, name: __MODULE__)
  def stop(pid), do: GenServer.stop(pid, :normal)
  def new_flight(script), do: GenServer.call(__MODULE__, {:new_flight, script})
  def check_flight_status(flight_no), do: GenServer.call(__MODULE__, {:check_flight_status, flight_no})

  # Bird API
  def coming_in_for_landing(payload), do: GenServer.call(__MODULE__, {:coming_in_for_landing, payload})
  def i_crashed(error_payload), do: GenServer.call(__MODULE__, {:i_crashed, error_payload})

  # Server Callbacks

  def init(_) do
    # Initialize worker pool
    {:ok, _} = :poolboy.start_link([
      name: {:global, __MODULE__},
      worker_module: Pidge.FlightControl.Bird,
      size: 4,
      max_overflow: 2
    ])

    # Start a repeating timer that sends a :check_flights message every 5000 milliseconds
    {:ok, _} = :timer.send_interval(5000, self(), :check_flights)

    {:ok, %{
      in_flight: %{},
      flight_caller: %{},
      runway_queue: [],
      landed_taxi_queue: %{},
      crashed_flights: %{}
    }}
  end

  def terminate(:normal, _state) do
    # Terminate worker pool
    :poolboy.stop({:global, __MODULE__})
  end

  def handle_call({:new_flight, _script} = payload, from, state), do: new_flight(payload, from, state)

  def handle_call({:coming_in_for_landing, payload}, {bird_pid,_} = from, state) do
    # This is a reply from a worker
    # We need to find the flight number
    flight_no = state.in_flight |> Map.keys() |> Enum.find(fn flight_no ->
      state.in_flight[flight_no] == bird_pid
    end)

    if flight_no == nil do
      IO.inspect(state, label: "state")
      IO.inspect(bird_pid, label: "bird_pid")
      IO.inspect(from, label: "from")
      IO.inspect(payload, label: "payload")
      raise "Flight not found in :coming_in_for_landing handler"
    end

    state =
      state
      |> Map.put(:in_flight, Map.delete(state.in_flight, flight_no))
      |> Map.put(:landed_taxi_queue, Map.put(state.landed_taxi_queue, flight_no, payload))

    send_message_to_flight_caller(state, flight_no, {:landed, flight_no, payload})

    {:reply, :ok, next_flight(bird_pid, state)}
  end

  def handle_call({:i_crashed, error_payload}, {bird_pid,_} = from, state) do
    # This is a reply from a worker
    # We need to find the flight number
    flight_no = state.in_flight |> Map.keys() |> Enum.find(fn flight_no ->
      state.in_flight[flight_no] == bird_pid
    end)

    if flight_no == nil do
      IO.inspect(state, label: "state")
      IO.inspect(bird_pid, label: "bird_pid")
      IO.inspect(from, label: "from")
      IO.inspect(error_payload, label: "error_payload")
      raise "Flight not found in :i_crashed handler"
    end

    state =
      state
      |> Map.put(:in_flight, Map.delete(state.in_flight, flight_no))
      |> Map.put(:crashed_flights, Map.put(state.crashed_flights, flight_no, error_payload))

    send_message_to_flight_caller(state, flight_no, {:crashed, flight_no, error_payload})

    {:reply, :ok, next_flight(bird_pid, state)}
  end

  def handle_call({:check_flight_status, flight_no}, _from, state) do
    case state do
      %{ in_flight: %{^flight_no => bird_pid} } ->
        # check if pid is still running
        case Process.alive?(bird_pid) do
          true -> {:reply, :in_flight, state}
          false ->
            err_payload = {:error, "PID was found to not be alive during check_flight_status"}
            {:reply, :ok, state} = handle_call({:i_crashed, err_payload}, {bird_pid, nil}, state)
            {:reply, {:crashed, err_payload}, state}
        end
      %{ landed_taxi_queue: %{^flight_no => payload} } -> {:reply, {:landed, payload}, state}
      %{ crashed_flights: %{^flight_no => err_payload} } -> {:reply, {:crashed, err_payload}, state}
      _ ->
        number_in_queue = state.runway_queue |> Enum.find_index(fn {num, _} -> flight_no == num end)
        case number_in_queue do
          nil -> {:reply, :not_found, state}
          _ -> {:reply, {:on_runway, number_in_queue}, state}
        end
    end
  end

  defp new_flight(payload, {caller_pid, _}, state) do
    flight_no = :crypto.strong_rand_bytes(8) |> Base.encode16()

    state = Map.put(state, :flight_caller, Map.put(state.flight_caller, flight_no, caller_pid))

    case :poolboy.checkout({:global, Pidge.FlightControl}, false) do
      :full ->
        # Queue the script
        {:reply, flight_no, Map.put(state, :runway_queue, state.runway_queue ++ [{flight_no,payload}])}
      bird_pid ->
        GenServer.cast(bird_pid, payload)
        {:reply, flight_no, Map.put(state, :in_flight, Map.put(state.in_flight, flight_no, bird_pid))}
    end
  end

  defp next_flight(bird_pid, state) do
    case state.runway_queue do
      [] ->
        :poolboy.checkin({:global, Pidge.FlightControl}, bird_pid)
        state
      [{flight_no, payload} | rest] ->
        GenServer.cast(bird_pid, payload)
        state
        |> Map.put(:in_flight, Map.put(state.in_flight, flight_no, bird_pid))
        |> Map.put(:runway_queue, rest)
    end
  end

  def handle_info(:check_flights, state) do
    new_state = Enum.reduce(state.in_flight, state, fn {flight_no, bird_pid}, acc_state ->
      if Process.alive?(bird_pid) do
        acc_state
      else
        err_payload = {:error, "PID was found to not be alive during check_flights"}
        {:reply, :ok, acc_state} = handle_call({:i_crashed, err_payload}, {bird_pid, nil}, acc_state)
        Map.put(acc_state, :in_flight, Map.delete(state.in_flight, flight_no))
      end
    end)

    {:noreply, new_state}
  end

  defp send_message_to_flight_caller(state, flight_no, message) do
    caller_pid = state.flight_caller[flight_no]
    send(caller_pid, message)
  end
end
