defmodule Pidge.ObjectPatchTest do
  use ExUnit.Case
  alias Pidge.ObjectPatch

  describe "diff_objects/2" do
    test "simple map difference" do
      a = %{name: "John", age: 30}
      b = %{name: "John", age: 31, gender: "male"}

      expected_diff = %{
        minuses: [{[:age], 30}],
        pluses: [ {[:gender], "male"}, {[:age], 31}]
      }

      assert ObjectPatch.diff_objects(a, b) == expected_diff
    end

    test "nested map difference" do
      a = %{user: %{name: "John", preferences: %{theme: "light", language: "English"}}}
      b = %{user: %{name: "John", preferences: %{theme: "dark"}}}

      expected_diff = %{
        minuses: [{[:user, :preferences, :language], "English"}, {[:user, :preferences, :theme], "light"}],
        pluses: [{[:user, :preferences, :theme], "dark"}]
      }

      assert ObjectPatch.diff_objects(a, b) == expected_diff
    end

    test "list difference" do
      a = [1, 2, 3]
      b = [1, 3, 4]

      expected_diff = %{
        minuses: [{[1], 2},{[2], 3}],
        pluses: [{[1], 3},{[2], 4}]
      }

      assert ObjectPatch.diff_objects(a, b) == expected_diff
    end

    test "nested list inside map difference" do
      a = %{data: [1, 2, 3]}
      b = %{data: [1, 3, 4]}

      expected_diff = %{
        minuses: [{[:data, 1], 2},{[:data, 2], 3}],
        pluses: [{[:data, 1], 3},{[:data, 2], 4}]
      }

      assert ObjectPatch.diff_objects(a, b) == expected_diff
    end

    test "map inside list difference" do
      a = [%{name: "John"}, %{name: "Doe"}]
      b = [%{name: "John", age: 30}, %{name: "Doe"}]

      expected_diff = %{
        minuses: [],
        pluses: [{[0, :age], 30}]
      }

      assert ObjectPatch.diff_objects(a, b) == expected_diff
    end
  end

  def lists_are_equal(list1,list2) do
    set1 = MapSet.new(list1)
    set2 = MapSet.new(list2)

    set1 == set2
  end

  describe "zip_with_default/4" do
    test "zips two lists with default value when one is shorter" do
      # Test when first list is shorter
      assert ObjectPatch.zip_with_default([1], [2, 3], :default) == [{1, 2}, {:default, 3}]

      # Test when second list is shorter
      assert ObjectPatch.zip_with_default([1, 2], [3], :default) == [{1, 3}, {2, :default}]

      # Test with both lists of equal length
      assert ObjectPatch.zip_with_default([1, 2], [3, 4], :default) == [{1, 3}, {2, 4}]

      # Test with both lists empty
      assert ObjectPatch.zip_with_default([], [], :default) == []

      # Test with first list empty
      assert ObjectPatch.zip_with_default([], [1, 2], :default) == [{:default, 1}, {:default, 2}]

      # Test with second list empty
      assert ObjectPatch.zip_with_default([1, 2], [], :default) == [{1, :default}, {2, :default}]
    end
  end

  describe "patch_object/3" do
    test "applies a diff to an object" do
      object = %{name: "John", age: 30}
      diff = %{pluses: [{[:age], 31}], minuses: [{[:age], 30}]}

      {new_object, errors} = ObjectPatch.patch_object(object, diff)
      assert new_object == %{name: "John", age: 31}
      assert errors == []
    end

    test "applies a diff in reverse" do
      object = %{name: "John", age: 30}
      diff = %{pluses: [{[:age], 30}], minuses: [{[:age], 31}]}

      {new_object, errors} = ObjectPatch.patch_object(object, diff, true)
      assert new_object == %{name: "John", age: 31}
      assert errors == []
    end

    test "handles non-existing keys in the diff" do
      object = %{name: "John", age: 30}
      diff = %{pluses: [{[:height], 175}], minuses: [{[:age], 30}]}

      {new_object, errors} = ObjectPatch.patch_object(object, diff)
      assert new_object == %{name: "John", height: 175}
      assert errors == []
    end

    test "captures errors when value mismatch" do
      object = %{name: "John", age: 30}
      diff = %{pluses: [{[:age], 31}], minuses: [{[:age], 29}]}

      {new_object, errors} = ObjectPatch.patch_object(object, diff)
      assert new_object == %{name: "John", age: 31}
      assert errors == ["Warning: patch attempted to remove a value that didn't match the expected value: age was 30 != 29 (all parents did exist)"]
    end

    test "handles deep nested paths" do
      object = %{name: "John", details: %{height: 175, hobbies: ["reading", "swimming"]}}
      diff = %{pluses: [{[:details, :hobbies, 2], "coding"}], minuses: [{[:details, :height], 175}]}

      {new_object, errors} = ObjectPatch.patch_object(object, diff)
      assert new_object == %{name: "John", details: %{hobbies: ["reading", "swimming", "coding"]}}
      assert errors == []
    end

    test "captures errors for non-existing deep nested paths" do
      object = %{name: "John", details: %{height: 175, hobbies: ["reading"]}}
      diff = %{
        pluses: [
          {[:details, :hobbies, 5], "coding"},
          {[:details, :portfolio, 0, :url],"http://mysite.com"}
        ],
        minuses: [
          {[:details, :weight], 70}
        ]
      }

      {_new_object, errors} = ObjectPatch.patch_object(object, diff)
      assert errors == [
        "Warning: patch attempted to remove a key that didn't exist: details.weight on %{height: 175, hobbies: [\"reading\"]} (all parents did exist)",
        "Warning: patch attempted to add an element on a list that didn't exist: details.hobbies.5 (all parents did exist)",
        "Warning: patch attempted to add a key that didn't exist: details.portfolio / 0.url on %{height: 175, hobbies: [\"reading\"]} (one or more parents did not exist)"
      ]
    end

    test "captures warnings, like removing a value that didn't match the expected value" do
      object = %{name: "John", details: %{height: 175, hobbies: ["reading"]}}
      diff = %{pluses: [{[:details, :hobbies, 0], "coding"},{[:name], "Elmo"}], minuses: [{[:details, :height], 190}]}

      {new_object, errors} = ObjectPatch.patch_object(object, diff)
      assert new_object == %{name: "Elmo", details: %{hobbies: ["coding"]}}
      assert errors == [
        "Warning: patch attempted to remove a value that didn't match the expected value: details.height was 175 != 190 (all parents did exist)",
        "Warning: patch overwrote a value that already existed: details.hobbies.0 had \"reading\" and was overwritten with \"coding\" (all parents did exist)",
        "Warning: patch overwrote a value that already existed: name had \"John\" and was overwritten with \"Elmo\" (all parents did exist)"
      ]
    end
  end
end
