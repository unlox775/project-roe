defmodule Pidge.WebClient.Socket do
  use WebSockex

  @url "wss://abandoned-scared-halibut.gigalixirapp.com/socket/websocket"
  @heartbeat_interval 30_000  # 30 seconds

  def send_and_watch_for_response(%{message: message, channel: channel, ref: ref, opts: opts} = state) do
    state =
      state
      |> Map.put(:started_heartbeat, false)
      |> Map.put(:parent, self())

      bug(opts,3,[url: @url])
      {:ok, pid} = WebSockex.start(@url, __MODULE__, state)

    join_message = %{
      topic: channel,
      event: "phx_join",
      payload: %{},
      ref: ref + 1
    }
    payload_message = %{
      topic: channel,
      event: "send_script_to_chat",
      payload: %{
          body: message
      },
      ref: ref
    }
    bug(opts,5,[join_message: join_message])
    WebSockex.send_frame(pid, {:text, Poison.encode!(join_message)})
    bug(opts,5,[payload_message: payload_message])
    WebSockex.send_frame(pid, {:text, Poison.encode!(payload_message)})
    {:ok, pid}
  end

  def terminate(reason, %{channel: channel, opts: opts}) do
    bug(opts, 1, [label: "WebSockex #{inspect(channel)} terminating with reason: #{inspect reason}"])
    exit(:normal)
  end

  def handle_frame({_type, msg}, %{ref: ref, parent: parent, opts: opts} = state) do
    # First time: If we haven't started the heartbeat, do so
    state =
      if !state.started_heartbeat do
        bug(opts,2,[label: "CASE: First time: If we haven't started the heartbeat, do so"])
        schedule_heartbeat(opts)
        Map.put(state, :started_heartbeat, true)
      else
        state
      end

    bug(opts,3,[msg: msg, label: "GOT msg"])
    case Poison.decode(msg) do
      # Ignore our own message bouncing back
      {:ok, %{"ref" => ^ref}} ->
        bug(opts,2,[label: "CASE: Ignoring our own message bouncing back"])
        {:ok, state}
      {:ok, %{"event" => "send_script_to_chat"}} ->
        bug(opts,2,[label: "CASE: Ignoring our own message bouncing back [send_script_to_chat]"])
        {:ok, state}
      {:ok, %{"event" => "new_script_to_chat"}} ->
        bug(opts,2,[label: "CASE: Ignoring our own message bouncing back [new_script_to_chat]"])
        {:ok, state}
      {:ok, %{"event" => "phx_reply", "payload" => %{"response" => %{}, "status" => "ok"}}} ->
        {:ok, state}

      # When we actually DO get a response (and they will kill us)
      {:ok, %{ "event" => "new_chat_to_script", "payload" => %{"body" => _body} = payload }} ->
        bug(opts,2,[label: "CASE: We got a response, so we're done."])
        send(parent, {ref, payload})
        {:ok, state}

      other ->
        bug(opts,2,[other: other, label: "CASE: Didn't match anything good"])
        raise "Unexpected message: #{inspect(other)}"
    end
    {:ok, state}
  end

  def handle_info(:send_heartbeat, %{opts: opts} = state) do
    bug(opts,2,[label: "Sending heartbeat"])
    heartbeat_message = %{
      topic: "phoenix",
      event: "heartbeat",
      payload: %{},
      ref: nil
    }

    # WebSockex.send_frame(self(), {:text, Poison.encode!(heartbeat_message)})
    schedule_heartbeat(opts)
    {:reply, {:text, Poison.encode!(heartbeat_message)}, state}
  end

  def handle_connect(conn) do
    # IO.puts("WebSockex connected to #{inspect(conn.url)}")
    schedule_heartbeat([])
    {:ok, conn}
  end

  defp schedule_heartbeat(opts) do
    bug(opts, 3, "Scheduling heartbeat")
    Process.send_after(self(), :send_heartbeat, @heartbeat_interval)
  end

  defp bug(opts, level, stuff_to_debug), do: Pidge.Run.bug(opts, level, stuff_to_debug)
end
