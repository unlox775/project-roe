defmodule Pidge.LLMConversationStore do
  @moduledoc """
  Stores per-conversation message history keyed by session and conversation id.
  Uses a JSON file per session: release/{session}_llm.json
  Structure: %{ "bard" => [%{"role" => "user", "content" => "..."}, ...], ... }
  """

  @base_dir "release"

  def get_messages(session, conv) when is_atom(conv), do: get_messages(session, to_string(conv))
  def get_messages(session, conv) when is_binary(conv) do
    session = normalize_session(session)
    data = read_all(session)
    Map.get(data, conv, [])
  end

  def append(session, conv, role, content) when is_atom(conv), do: append(session, to_string(conv), role, content)
  def append(session, conv, role, content) when is_binary(conv) do
    session = normalize_session(session)
    messages = get_messages(session, conv) ++ [%{"role" => to_string(role), "content" => content}]
    data = read_all(session) |> Map.put(conv, messages)
    write_all(session, data)
    :ok
  end

  def set_messages(session, conv, messages) when is_atom(conv), do: set_messages(session, to_string(conv), messages)
  def set_messages(session, conv, messages) when is_binary(conv) do
    session = normalize_session(session)
    data = read_all(session) |> Map.put(conv, messages)
    write_all(session, data)
    :ok
  end

  defp path_for(session), do: Path.join(@base_dir, "#{session}_llm.json")

  defp read_all(session) do
    path = path_for(session)
    case File.read(path) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, map} when is_map(map) -> map
          _ -> %{}
        end
      {:error, :enoent} -> %{}
      {:error, _} -> %{}
    end
  end

  defp write_all(session, data) do
    path = path_for(session)
    File.mkdir_p!(@base_dir)
    File.write!(path, Jason.encode!(data, pretty: true))
  end

  defp normalize_session(nil), do: "default"
  defp normalize_session(""), do: "default"
  defp normalize_session(s) when is_binary(s), do: String.downcase(s)
  defp normalize_session(s) when is_atom(s), do: s |> to_string() |> normalize_session()
end
