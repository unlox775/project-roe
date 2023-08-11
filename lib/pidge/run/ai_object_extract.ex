defmodule Pidge.Run.AIObjectExtract do

  def post_process(%{params: %{
      conversation_id: _conversation_id,
      format: format,
      prompt: _prompt,
      schema: _schema,
    }}, opts) do
    object =
      case format do
        "json" ->
          input = opts[:input]
          extract_json_object_from_input(input, opts)
        _ ->
          raise "Unsupported format in ai_object_extract: #{format}"
      end
    bug(opts, 1, label: "Extracted object", object: object)

    case object do
      nil ->
        {:error, "Failed to extract object from input"}
      _ ->
        # Change the input from the opts Keyword list to the parsed map
        {:ok, Keyword.put(opts, :input, object)}
    end
  end

  defp extract_json_object_from_input(input, opts) do
    # Find the char positions of all the open curly braces
    open_braces = input |> String.graphemes() |> Enum.with_index() |> Enum.filter(fn {char, _index} -> char == "{" end) |> Enum.map(fn {_char, index} -> index end)

    # Find the char positions of all the close curly braces, reversed
    close_braces = input |> String.graphemes() |> Enum.with_index() |> Enum.filter(fn {char, _index} -> char == "}" end) |> Enum.map(fn {_char, index} -> index end) |> Enum.reverse()

    # Do an reduce, finding the first open brace, which evaulates to a valid JSON object
    # Run optomistically, starting with the first open brace and the last close brace
    # If the JSON is invalid, it will throw an error, and we will try again with the next pair of braces
    # If the JSON is valid, we will return the object
    Enum.reduce_while(open_braces, nil, fn open_index, _acc ->
      case try_parse(input, open_index, close_braces, opts) do
        {:ok, json} -> {:halt, json}
        :error -> {:cont, nil}
      end
    end)
  end

  defp try_parse(input, open_index, close_braces, opts) do
    Enum.reduce_while(close_braces, :error, fn close_index, _acc ->
      substring = String.slice(input, open_index, close_index - open_index + 1)
      bug(opts, 5, label: "Trying to parse", substring: substring)
      case Poison.decode(substring) do
        {:ok, json} -> {:halt, {:ok, json}}
        {:error, _} -> {:cont, :error}
      end
    end)
  end

  defp bug(opts, level, stuff_to_debug), do: Pidge.Run.bug(opts, level, stuff_to_debug)
end