defmodule Pidge.WebClient do
  @max_wait_time 300_000 # 5 minutes
  @recheck_every 200  # fifth of a second

  alias Pidge.WebClient.Socket

  def send_and_wait_for_response(message, channel, opts) do
    ref = 10000 + :rand.uniform(100000 - 1)
    {:ok, socket_pid} = send_message(message, channel, ref, opts)

    case wait_for_response(ref, socket_pid, @max_wait_time) do
      {:ok, response} ->
        # kill the socket
        Process.exit(socket_pid, :kill)
        bug(opts, 5,[response: response, label: "AFTERKILL - CASE: We got a response, so we're done."])
        {:ok, response}
      {:error, :timeout} ->
        # kill the socket
        Process.exit(socket_pid, :kill)
        raise "Timeout waiting 5 minutes for response sending this to [#{channel}]:\n\n#{inspect message}"
    end
  end

  defp send_message(message, channel, ref, opts) do
    state = %{
      message: message,
      ref: ref,
      channel: channel,
      opts: opts
    }
    Socket.send_and_watch_for_response(state)
  end

  defp wait_for_response(_, _, remaining_time) when remaining_time <= 0 do
    {:error, :timeout}
  end

  defp wait_for_response(ref, socket_pid, remaining_time) do
    case receive_message(ref) do
      {:ok, response} -> {:ok, response}
      :timeout -> wait_for_response(ref, socket_pid, remaining_time - @recheck_every)
    end
  end

  defp receive_message(ref) do
    receive do
      {^ref, response} -> {:ok, response}
      _ -> :timeout
    after
      @recheck_every -> :timeout
    end
  end

  defp bug(opts, level, stuff_to_debug), do: Pidge.Run.bug(opts, level, stuff_to_debug)
end
