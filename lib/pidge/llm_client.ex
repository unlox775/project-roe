defmodule Pidge.LLMClient do
  @moduledoc """
  OpenAI Chat Completions client with per-conversation history.
  Uses LLMConversationStore keyed by session and conversation id.
  """

  alias Pidge.LLMConversationStore

  @default_model "gpt-4o-mini"
  @api_url "https://api.openai.com/v1/chat/completions"

  def send_and_wait_for_response(session, conv, message) do
    conv_str = to_string(conv)
    # Append user message to history
    LLMConversationStore.append(session, conv_str, "user", message)
    messages = LLMConversationStore.get_messages(session, conv_str)
    api_messages = Enum.map(messages, fn %{"role" => r, "content" => c} -> %{role: r, content: c} end)

    case call_openai(api_messages) do
      {:ok, content} ->
        LLMConversationStore.append(session, conv_str, "assistant", content)
        {:ok, %{"body" => content}}
      {:error, reason} ->
        # Rollback: remove the user message we just appended
        trimmed = messages |> Enum.take(length(messages) - 1)
        LLMConversationStore.set_messages(session, conv_str, trimmed)
        {:error, reason}
    end
  end

  defp call_openai(messages) do
    api_key = System.get_env("OPENAI_API_KEY")
    if is_nil(api_key) or api_key == "" do
      {:error, "OPENAI_API_KEY not set"}
    else
      body = %{
        model: @default_model,
        messages: messages
      }
      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]
      case HTTPoison.post(@api_url, Jason.encode!(body), headers, [recv_timeout: 120_000]) do
        {:ok, %{status_code: 200, body: resp_body}} ->
          case Jason.decode(resp_body) do
            {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} when is_binary(content) ->
              {:ok, content}
            {:ok, %{"choices" => [%{"message" => %{"content" => nil}} | _]}} ->
              {:ok, ""}
            {:ok, parsed} ->
              {:error, "Unexpected OpenAI response: #{inspect(parsed)}"}
            {:error, _} = e -> e
          end
        {:ok, %{status_code: code, body: resp_body}} ->
          {:error, "OpenAI API error #{code}: #{resp_body}"}
        {:error, %{reason: reason}} ->
          {:error, "OpenAI request failed: #{inspect(reason)}"}
      end
    end
  end
end
