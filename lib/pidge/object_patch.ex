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
        minuses: [{[:age], 30}],
        pluses: [{[:age], 31}, {[:gender], "male"}]
      }

  For a more complex example involving nested structures:

      a = %{user: %{name: "John", preferences: %{theme: "light", language: "English"}}}
      b = %{user: %{name: "John", preferences: %{theme: "dark"}}}

      Pidge.ObjectPatch.diff_objects(a, b)

  This would return:

      %{
        minuses: [{[:user, :preferences, :theme], "light"}, {[:user, :preferences, :language], "English"}],
        pluses: [{[:user, :preferences, :theme], "dark"}]
      }

  This indicates that, in the transition from `a` to `b`, the theme was changed from "light" to "dark" and the language preference was removed.
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
        minuses: [{[:age], 30}],
        pluses: [{[:age], 31}, {[:gender], "male"}]
      }
  """
  @spec diff_objects(any, any) :: map
  def diff_objects(a, b) do
    diff_crawl(a,b,[],%{
      pluses: [],
      minuses: []
    })
  end

  defp diff_crawl(%{} = a, %{} = b,p,acc) do
    a_set = a |> Map.keys |> Enum.sort() |> MapSet.new
    b_set = b |> Map.keys |> Enum.sort() |> MapSet.new

    a_only = MapSet.difference(a_set, b_set)
    both = MapSet.intersection(a_set, b_set)
    b_only = MapSet.difference(b_set, a_set)

    a_only = Enum.to_list(a_only)
    both = Enum.to_list(both)
    b_only = Enum.to_list(b_only)

    acc = Enum.reduce(a_only ++ b_only, acc, fn key, sub_acc->
      capture_diff(
        Map.get(a, key, @no_value),
        Map.get(b, key, @no_value),
        p ++ [key],
        sub_acc
      )
    end)

    Enum.reduce(both, acc, fn key, sub_acc ->
      diff_crawl(Map.get(a,key),Map.get(b,key),p ++ [key], sub_acc)
    end)
  end
  defp diff_crawl(%{} = a,b,p,acc), do: capture_diff(a,b,p,acc)
  defp diff_crawl(a,%{} = b,p,acc), do: capture_diff(a,b,p,acc)
  defp diff_crawl(a,b,p,acc) when is_list(a) and is_list(b) do
    zip_with_default(a,b,@no_value)
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {pair,i}, sub_acc ->
      case pair do
        {a_v,@no_value = b_v} -> capture_diff(a_v,b_v,p ++ [i], sub_acc)
        {@no_value = a_v, b_v} -> capture_diff(a_v,b_v,p ++ [i], sub_acc)
        {a_v,b_v} -> diff_crawl(a_v,b_v,p ++ [i], sub_acc)
      end
    end)
  end
  defp diff_crawl(a,b,p,acc) when is_list(a), do: capture_diff(a,b,p,acc)
  defp diff_crawl(a,b,p,acc) when is_list(b), do: capture_diff(a,b,p,acc)
  defp diff_crawl(same,same,_p,acc), do: acc
  defp diff_crawl(a,b,p,acc), do: capture_diff(a,b,p,acc)

  defp capture_diff(@no_value,b,p,acc), do: Map.put(acc, :pluses, acc.pluses ++ [{p,b}])
  defp capture_diff(a,@no_value,p,acc), do: Map.put(acc, :minuses, acc.minuses ++ [{p,a}])
  defp capture_diff(a,b,p,acc) do
    acc
    |> Map.put(:minuses, acc.minuses ++ [{p,a}])
    |> Map.put(:pluses, acc.pluses ++ [{p,b}])
  end

  @doc """
  Zips two lists, `a` and `b`, using a default value when one list is shorter than the other.

  If one list is shorter than the other, the default value will be used to "fill in" the missing
  values, so the resulting zipped list has the length of the longer list.

  ## Examples

      iex> Pidge.ObjectPatch.zip_with_default([1, 2], [3], :default)
      [{1, 3}, {2, :default}]

      iex> Pidge.ObjectPatch.zip_with_default([1], [2, 3], :default)
      [{1, 2}, {:default, 3}]

      iex> Pidge.ObjectPatch.zip_with_default([1, 2], [3, 4], :default)
      [{1, 3}, {2, 4}]

  """
  @spec zip_with_default(list, list, any, [{any, any}]) :: [{any, any}]
  def zip_with_default(a,b,default,acc \\ [])
  def zip_with_default([], [], _default, acc), do: acc
  def zip_with_default([], [b|b_tail], default, acc),
    do: zip_with_default([], b_tail, default, acc ++ [{default, b}])
  def zip_with_default([a|a_tail], [], default, acc),
    do: zip_with_default(a_tail, [], default, acc ++ [{a,default}])
  def zip_with_default([a|a_tail], [b|b_tail], default, acc),
    do: zip_with_default(a_tail, b_tail, default, acc ++ [{a, b}])

  @doc """
  Applies a diff to an object to transform it. The transformation can be done forwards or in reverse.

  Given an object and a diff, this function will apply the diff to the object to generate a new version of the object.
  Optionally, you can reverse the application of the diff by setting the `reverse` parameter to `true`.

  The function also returns any encountered errors as a list of error messages.

  ## Parameters

  - `object`: The initial object to which the diff should be applied.
  - `diff`: The diff that should be applied to the object. It should contain `:pluses` and `:minuses` keys, which is the output of the `diff_objects/2` function.
  - `reverse` (optional): If set to `true`, the diff will be applied in reverse (default is `false`).

  ## Return values

  The function returns a tuple with two elements:
  1. The transformed object.
  2. A list of encountered errors, which were non-fatal, but which meant one or more of the patch transformations may not have completed as specified.

  ## Examples

      iex> object = %{name: "John", age: 30}
      iex> diff = %{pluses: [{[:age], 31}], minuses: [{[:age], 30}]}
      iex> Pidge.ObjectPatch.patch_object(object, diff)
      {%{name: "John", age: 31}, []}

      iex> Pidge.ObjectPatch.patch_object(object, diff, true)
      {%{name: "John", age: 30}, []}

  """
  @spec patch_object(any, map, boolean) :: {any, [any]}
  def patch_object(object, diff, reverse \\ false) do
    # remove values from object
    {object,errors} =
      diff
      |> Map.get(if reverse, do: :pluses, else: :minuses)
      |> Enum.reduce({object, []}, fn {path, value}, {acc,errors} ->
        try do
          {new_acc, picked_value} = cherry_pick(acc, path)
          case picked_value do
            ^value -> {new_acc, errors}
            _ -> {new_acc, errors ++ ["Warning: patch attempted to remove a value that didn't match the expected value: #{Enum.join(path, ".")} was #{inspect(picked_value)} != #{inspect(value)} (all parents did exist)"]}
          end
        catch
          :error, e -> {acc, errors ++ [Exception.message(e)]}
        end
      end)

    # add values to object
    diff
    |> Map.get(if reverse, do: :minuses, else: :pluses)
    |> Enum.reduce({object, errors}, fn {path, value}, {acc,errors} ->
      try do
        {new_acc, overwritten_value} = cherry_plant(acc, path, value)
        case overwritten_value do
          @no_value -> {new_acc, errors}
          _ ->
            error = "Warning: patch overwrote a value that already existed: #{Enum.join(path, ".")} had #{inspect(overwritten_value)} and was overwritten with #{inspect(value)} (all parents did exist)"
            { new_acc, errors ++ [error] }
        end
      catch
        :error, e -> {acc, errors ++ [Exception.message(e)]}
      end
    end)
  end

  defp cherry_pick(obj,path), do: cherry_x(path,obj,[],:remove,nil)
  defp cherry_plant(obj,path,value), do: cherry_x(path,obj,[],:add,value)

  # Handle the last key in the path
  defp cherry_x([last_key|[]],%{} = obj,pc,x,v) do
    case {x,obj} do
      {:remove, %{^last_key => _}} ->
        removed_value = Map.get(obj,last_key)
        { Map.delete(obj,last_key), removed_value }
      {:remove, _} -> raise "Warning: patch attempted to #{to_string(x)} a key that didn't exist: #{Enum.join(pc ++ [last_key], ".")} on #{inspect(obj)} (all parents did exist)"
      {:add, _} ->
        overwritten_value = Map.get(obj,last_key, @no_value)
        { Map.put(obj,last_key,v), overwritten_value }
    end
  end
  defp cherry_x([last_idx|[]],obj,pc,x,v) when is_list(obj) and is_integer(last_idx) do
    cond do
      x == :add && last_idx == Enum.count(obj) -> { obj ++ [v], @no_value }
      x == :add    && last_idx < Enum.count(obj) ->
        overwritten_value = Enum.at(obj,last_idx)
        { obj |> List.delete_at(last_idx) |> List.insert_at(last_idx,v), overwritten_value }
      x == :remove && last_idx < Enum.count(obj) ->
        removed_value = Enum.at(obj,last_idx)
        { obj |> List.delete_at(last_idx), removed_value }
      true -> raise "Warning: patch attempted to #{to_string(x)} an element on a list that didn't exist: #{Enum.join(pc ++ [last_idx], ".")} (all parents did exist)"
    end
  end
  defp cherry_x([last_idx|[]],obj,pc,x,_v) when is_list(obj), do: raise "Patch attempt to #{to_string(x)} an element from a list with an non-integer index: #{Enum.join(pc ++ [last_idx], ".")} on #{inspect(obj)} (all parents did exist)"

  # Handle the beginning of the path
  defp cherry_x([key|p],%{} = obj,pc,x,v) do
    case obj do
      %{^key => _} ->
        {new_value, return_value} = cherry_x(p,obj[key],pc ++ [key],x,v)
        { Map.put(obj, key, new_value), return_value }
      _ -> raise "Warning: patch attempted to #{to_string(x)} a key that didn't exist: #{Enum.join(pc ++ [key], ".")} / #{Enum.join(p, ".")} on #{inspect(obj)} (one or more parents did not exist)"
    end
  end
  defp cherry_x([idx|p],obj,pc,x,v) when is_list(obj) and is_integer(idx) do
    cond do
      idx < Enum.count(obj) ->
        {new_value, return_value} = cherry_x(p,Enum.at(obj,idx),pc ++ [idx],x,v)
        { obj |> List.delete_at(idx) |> List.insert_at(idx,new_value), return_value }
      true -> raise "Warning: patch attempted to #{to_string(x)} an element on a list that didn't exist: #{Enum.join(pc ++ [idx], ".")} / #{Enum.join(p, ".")} (one or more parents did not exist)"
    end
  end
  defp cherry_x([idx|p],obj,pc,x,_v) when is_list(obj), do: raise "Patch attempted to #{to_string(x)} an element from a list with an non-integer index: #{Enum.join(pc ++ [idx], ".")} / #{Enum.join(p, ".")} on #{inspect(obj)} (one or more parents did not exist)"
end
