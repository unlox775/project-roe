defmodule Pidge.WebClient.Socket do
  use WebSockex

  @url "wss://abandoned-scared-halibut.gigalixirapp.com/socket/websocket"
  @heartbeat_interval 30_000  # 30 seconds

  def send_and_watch_for_response(%{message: message, channel: channel, ref: ref} = state) do
    state =
      state
      |> Map.put(:started_heartbeat, false)
      |> Map.put(:parent, self())

      IO.inspect(@url, label: "URL")
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
    IO.inspect(join_message, label: "JOIN MESSAGE")
    WebSockex.send_frame(pid, {:text, Poison.encode!(join_message)})
    IO.inspect(payload_message, label: "payload MESSAGE")
    WebSockex.send_frame(pid, {:text, Poison.encode!(payload_message)})
    {:ok, pid}
  end

  def terminate(reason, state) do
    IO.puts("WebSockex #{inspect(state.channel)} terminating with reason: #{inspect reason}")
    exit(:normal)
  end

  def handle_frame({_type, msg}, %{ref: ref, parent: parent} = state) do
    # First time: If we haven't started the heartbeat, do so
    state =
      if !state.started_heartbeat do
        IO.inspect("CASE: First time: If we haven't started the heartbeat, do so")
        schedule_heartbeat()
        Map.put(state, :started_heartbeat, true)
      else
        state
      end

    IO.inspect(msg, label: "GOT msg")
    case Poison.decode(msg) do
      # Ignore our own message bouncing back
      {:ok, %{"ref" => ^ref}} ->
        IO.inspect("CASE: Ignoring our own message bouncing back")
        {:ok, state}
      {:ok, %{"event" => "send_script_to_chat"}} ->
        IO.inspect("CASE: Ignoring our own message bouncing back [send_script_to_chat]")
        {:ok, state}
      {:ok, %{"event" => "new_script_to_chat"}} ->
        IO.inspect("CASE: Ignoring our own message bouncing back [new_script_to_chat]")
        {:ok, state}
      {:ok, %{"event" => "phx_reply", "payload" => %{"response" => %{}, "status" => "ok"}}} ->
        {:ok, state}

      # When we actually DO get a response (and they will kill us)
      {:ok, %{ "event" => "new_chat_to_script", "payload" => %{"body" => _body} = payload }} ->
        IO.inspect("CASE: We got a response, so we're done.")
        send(parent, {ref, payload})
        {:ok, state}

      other ->
        IO.inspect(other, label: "CASE: Didn't match anything good")
        raise "Unexpected message: #{inspect(other)}"
    end
    {:ok, state}
  end

  def handle_info(:send_heartbeat, state) do
    IO.inspect("Sending heartbeat")
    heartbeat_message = %{
      topic: "phoenix",
      event: "heartbeat",
      payload: %{},
      ref: nil
    }

    # WebSockex.send_frame(self(), {:text, Poison.encode!(heartbeat_message)})
    schedule_heartbeat()
    {:reply, {:text, Poison.encode!(heartbeat_message)}, state}
  end

  def handle_connect(conn) do
    IO.puts("WebSockex connected to #{inspect(conn.url)}")
    schedule_heartbeat()
    {:ok, conn}
  end

  defp schedule_heartbeat() do
    IO.puts("Scheduling heartbeat")
    Process.send_after(self(), :send_heartbeat, @heartbeat_interval)
  end
end
