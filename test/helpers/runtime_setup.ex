defmodule Helpers.RuntimeSetup do
  use ExUnit.Case
  alias Pidge.Runtime.SessionState

  def sessionstate_genserver(context) do
    line = Map.get(context, :line, context.module)

    {:ok, sessionstate_pid, session} = get_session_id(context.module,line)

    # Schedule the cleanup function to run after the test is complete
    on_exit(fn ->

      # check if the sessionstate_pid is still alive
      case Process.alive?(sessionstate_pid) do
        true ->
          SessionState.stop(sessionstate_pid)
        false -> :ok
      end
    end)

    # Return the sessionstate_pid to the test
    case Map.has_key?(context, :line) do
      false -> %{session: session}
      true -> {:ok, %{session: session}}
    end
  end

  def get_session_id(module,line) do
    token = :crypto.hash(:sha256,"#{module}_#{line}") |> Base.encode16
    session = "test/#{String.slice(token, 0, 8)}"
    {:ok, sessionstate_pid} = SessionState.start_link(session)
    {:ok, sessionstate_pid, session}
  end
end
