defmodule Pidge.ObjectPatch do
  @moduledoc """
  Provides functionality to generate diffs for deeply nested maps and lists.

  The main function, `diff_objects/2`, takes two Elixir structures (maps and lists)
  and returns a diff that details how to transform the first argument (`a`) to 
  match the second argument (`b`).

  The diff is represented as a map with two keys: `:pluses` and `:minuses`. Each 
  is a list of tuples where the first element of each tuple is a list representing
  a "path" to the changed value, and the second element is the changed value itself.

  Paths are lists of keys and/or indices, with integers representing list indices 
  and other values representing map keys. The order of elements in a path indicates
  the depth-first traversal needed to reach the changed value.

  ## Examples

  Consider a diff between two simple maps:

      a = %{name: "John", age: 30}
      b = %{name: "John", age: 31, gender: "male"}
      
      Pidge.ObjectPatch.diff_objects(a, b)

  This would return:

      %{
        pluses: [[[:age], 31], [[:gender], "male"]],
        minuses: [[[:age], 30]]
      }

  For a more complex example involving nested structures:

      a = %{user: %{name: "John", preferences: %{theme: "light", language: "English"}}}
      b = %{user: %{name: "John", preferences: %{theme: "dark"}}}

      Pidge.ObjectPatch.diff_objects(a, b)

  This would return:

      %{
        pluses: [[[:user, :preferences, :theme], "dark"]],
        minuses: [[[:user, :preferences, :theme], "light"], [[:user, :preferences, :language], "English"]]
      }
  
  This indicates that, in the transition from `a` to `b`, the theme was changed from "light" to "dark"
  and the language preference was removed.
  """

@no_value :no___value

  @doc """
  Calculates the diff between two maps or lists, `a` and `b`.

  The result is a map with two keys:

    * `:pluses` - Represents added or changed values in `b` compared to `a`.
    * `:minuses` - Represents removed or changed values from `a` that are not present or different in `b`.

  Each item in the `:pluses` and `:minuses` lists is a tuple. The first element is a list representing
  the path to the changed value, and the second element is the changed value itself.

  ## Examples

      iex> a = %{name: "John", age: 30}
      iex> b = %{name: "John", age: 31, gender: "male"}
      iex> Pidge.ObjectPatch.diff_objects(a, b)
      %{
        pluses: [[[:age], 31], [[:gender], "male"]],
        minuses: [[[:age], 30]]
      }
  """
  def diff_objects(a, b) do
    diff_crawl(a,b,[],%{
      pluses: [],
      minuses: []
    })
  end

  defp diff_crawl(%{} = a, %{} = b,p,acc) do
    a_set = a |> Map.keys |> MapSet.new
    b_set = b |> Map.keys |> MapSet.new
    
    a_only = MapSet.difference(a_set, b_set)
    both = MapSet.intersection(a_set, b_set)
    b_only = MapSet.difference(b_set, a_set)
    
    a_only = Enum.to_list(a_only)
    both = Enum.to_list(both)
    b_only = Enum.to_list(b_only)

    acc = Map.reduce(a_only ++ b_only, acc, fn key, sub_acc->
      capture_diff(
        Map.get(a, key, @no_value),
        Map.get(b, key, @no_value),
        p ++ [key],
        sub_acc
      )
    end)

    acc = Map.reduce(both, acc, fn key, sub_acc ->
      diff_crawl(Map.get(a,key),Map.get(b,key),p ++ [key], sub_acc)
    end)
  end
  defp diff_crawl(%{} = a,b,p,acc), do: capture_diff(a,b,p,acc)
  defp diff_crawl(a,%{} = b,p,acc), do: capture_diff(a,b,p,acc)
  defp diff_crawl(a,b,p,acc) when is_list(a) and is_list(b) do
    zip_with_default(a,b,@no_value)
    |> with_index()
    |> Enum.reduce([], fn {pair,i}, sub_acc ->
    case pair do
      {a_v,@no_value = b_v} -> capture_diff(a_v,b_v,p ++ [i], sub_acc)
      {@no_value = a_v, b_v} -> capture_diff(a_v,b_v,p ++ [i], sub_acc)
      {a_v,b_v} -> diff_crawl(a_v,b_v,p ++ [i], sub_acc)
    end)
  end
  defp diff_crawl(a,b,p,acc) when is_list(a), do: capture_diff(a,b,p,acc)
  defp diff_crawl(a,b,p,acc) when is_list(b), do: capture_diff(a,b,p,acc)
  defp diff_crawl(_same,^_same,_p,acc), do: acc
  defp diff_crawl(a,b,p,acc), do: capture_diff(a,b,p,acc)

  defp capture_diff(@no_value,b,p,acc), do: Map.put(acc, :pluses, acc.pluses ++ [p,b])
  defp capture_diff(a,@no_value,p,acc), do: Map.put(acc, :minuses, acc.minuses ++ [p,a])
  defp capture_diff(a,b,p,acc) do
    acc
    |> Map.put(:minuses, acc.minuses ++ [p,a])
    |> Map.put(:pluses, acc.pluses ++ [p,b])
  end

  def zip_with_default([a|[]], [b|[]], default, acc \\ [])
  def zip_with_default([a|[]], [b|[]], default, acc), do: acc
  def zip_with_default([a|[]], [b|b_tail], default, acc),
    do: zip_with_default([],b_tail, default, acc ++ [{a,default}])
  def zip_with_default([a|a_tail], [b|[]], default, acc),
    do: zip_with_default(a_tail, [], default, acc ++ [{default, b}])
  def zip_with_default([a|a_tail], [b|b_tail], default, acc),
    do: zip_with_default(a_tail, b_tail, default, acc ++ [{a, b}])
end