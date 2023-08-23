defmodule Pidge.SessionStateTest do
  use ExUnit.Case

  import Helpers.RuntimeSetup
  setup :sessionstate_genserver

  alias Pidge.Runtime.SessionState

  @obj_name :product
  @obj_name_str "product"
  @obj_value_simple %{"item" => "book", "author" => "Pliney"}
  @obj_value_json "{\n  \"author\": \"Pliney\",\n  \"item\": \"book\"\n}"

  describe "get/1 and store_object/3" do
    test "returns the object we stored" do
      SessionState.start_link("foo")
      SessionState.wipe()
      SessionState.store_object(@obj_value_simple, @obj_name)
      state = SessionState.get()

      assert state[@obj_name_str] == @obj_value_simple
      assert state["json"][@obj_name_str] == @obj_value_json
    end
  end

  describe "merge_into_object/3" do
    test "merges the object into the existing state" do
      merge_in_obj =
        @obj_value_simple
        |> Map.put("price", 10.99)
        |> Map.delete("item")

      SessionState.wipe()
      SessionState.store_object(@obj_value_simple, @obj_name)
      SessionState.merge_into_object(merge_in_obj, @obj_name)
      state = SessionState.get()

      assert state[@obj_name_str]["item"] == "book"
      assert state[@obj_name_str]["price"] == 10.99
      assert state[@obj_name_str]["author"] == "Pliney"
    end
  end

  describe "clone_object/3" do
    test "clones an existing object in the state" do
      SessionState.wipe()
      SessionState.store_object(@obj_value_simple, @obj_name)
      SessionState.clone_object(@obj_name, "new_product")
      state = SessionState.get()

      assert state["new_product"] == @obj_value_simple
    end
  end
end
