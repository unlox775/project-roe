defmodule Pidge.Run.AIObjectExtract do

  alias Pidge.Runtime.RunState

  def object_extract_post_process(%{params: %{
      format: format,
    }}) do
    object =
      case format do
        "json" ->
          input = RunState.get_opt(:input)
          extract_json_object_from_input(input)
        _ ->
          raise "Unsupported format in ai_object_extract: #{format}"
      end
    bug(1, label: "Extracted object", object: object)

    case object do
      nil ->
        {:error, "Failed to extract object from input"}
      _ ->
        # Change the input opt to the parsed map
        RunState.set_opt(:input, object)
        bug(5, label: "Opts post-extract", object: RunState.get_opts())
        {:ok}
    end
  end

  defp extract_json_object_from_input(input) do
    # Find the char positions of all the open curly braces
    open_braces = input |> String.graphemes() |> Enum.with_index() |> Enum.filter(fn {char, _index} -> char == "{" end) |> Enum.map(fn {_char, index} -> index end)

    # Find the char positions of all the close curly braces, reversed
    close_braces = input |> String.graphemes() |> Enum.with_index() |> Enum.filter(fn {char, _index} -> char == "}" end) |> Enum.map(fn {_char, index} -> index end) |> Enum.reverse()

    # Do an reduce, finding the first open brace, which evaulates to a valid JSON object
    # Run optomistically, starting with the first open brace and the last close brace
    # If the JSON is invalid, it will throw an error, and we will try again with the next pair of braces
    # If the JSON is valid, we will return the object
    Enum.reduce_while(open_braces, nil, fn open_index, _acc ->
      case try_parse(input, open_index, close_braces) do
        {:ok, json} -> {:halt, json}
        :error -> {:cont, nil}
      end
    end)
  end

  defp try_parse(input, open_index, close_braces) do
    Enum.reduce_while(close_braces, :error, fn close_index, _acc ->
      substring = String.slice(input, open_index, close_index - open_index + 1)
      bug(5, label: "Trying to parse", substring: substring)
      case Poison.decode(substring) do
        {:ok, json} -> {:halt, {:ok, json}}
        {:error, _} -> {:cont, :error}
      end
    end)
  end


  def codeblock_extract_post_process(%{params: %{language: language} = params}) do
    # Run regex, to find all pairs of ~r/```(language)\n(.*)```/m
    # For each match, run the post_process function for that language
    matches =
      ~r/```#{language}\n(.*?)```/s
      |> Regex.scan(RunState.get_opt(:input)|> IO.inspect(label: "codeblock_extract_post_process line #{__ENV__.line}"))
      |> IO.inspect(label: "codeblock_extract_post_process line #{__ENV__.line}")
      |> Enum.map(fn [_,code] -> code end)
      |> IO.inspect(label: "codeblock_extract_post_process line #{__ENV__.line}")

    sorted =
      case Map.get(params, :largest, false)|> IO.inspect(label: "codeblock_extract_post_process line #{__ENV__.line}") do
        true -> Enum.sort_by(matches, &(String.length(&1)), :desc)
        _ -> matches
      end
    |> IO.inspect(label: "codeblock_extract_post_process line #{__ENV__.line}")
    result =
      case Map.get(params, :all, false)|> IO.inspect(label: "codeblock_extract_post_process line #{__ENV__.line}") do
        true -> sorted |> Enum.map(fn code -> code end)
        _ -> Enum.at(sorted, -1)
      end
      |> IO.inspect(label: "codeblock_extract_post_process line #{__ENV__.line}")

    bug(2, label: "post code block extract", code: result)
    RunState.set_opt(:input, result)
    bug(5, label: "Opts post-extract", object: RunState.get_opts())
    {:ok}
  end

  defp bug(level, stuff_to_debug), do: Pidge.Run.bug(level, stuff_to_debug)
end
