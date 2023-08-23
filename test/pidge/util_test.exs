defmodule Pidge.UtilTest do
  use ExUnit.Case, async: true

  alias Pidge.Util

  describe "make_list_of_strings/1" do
    test "converts empty list to empty list" do
      assert Util.make_list_of_strings([]) == []
    end

    test "converts list of different types to list of strings" do
      assert Util.make_list_of_strings([:a, 1, "string"]) == ["a", "1", "string"]
    end

    test "converts single non-list value to list of strings" do
      assert Util.make_list_of_strings(:a) == ["a"]
    end
  end

  describe "get_nested_key/3" do
    setup do
      state = %{
        a: %{
          b: %{
            c: "value"
          }
        }
      }
      {:ok, state: state}
    end

    test "returns state for empty key list", %{state: state} do
      assert Util.get_nested_key(state, [], nil) == state
    end

    test "returns nested map value for key list", %{state: state} do
      assert Util.get_nested_key(state, [:a, :b], nil) == %{c: "value"}
    end

    test "returns default for non-existent key", %{state: state} do
      assert Util.get_nested_key(state, [:a, :d], "none") == "none"
    end
  end

  describe "set_nested_key/3" do
    setup do
      state = %{
        a: %{
          b: %{
            c: "value"
          }
        }
      }
      {:ok, state: state}
    end

    test "sets value for nested key", %{state: state} do
      result = Util.set_nested_key(state, [:a, :b, :d], "new_value")
      assert result[:a][:b][:d] == "new_value"
    end

    test "sets value for deeper nested key", %{state: state} do
      result = Util.set_nested_key(state, [:a, :b, :e, :f], "deep_value")
      assert result[:a][:b][:e][:f] == "deep_value"
    end

    test "does not modify original state", %{state: state} do
      Util.set_nested_key(state, [:a, :b, :e, :f], "deep_value")
      assert not Map.has_key?(state[:a][:b], :e)
    end
  end
end
