defmodule Pidge.SessionStateTest do
  use ExUnit.Case

  import Helpers.RuntimeSetup
  setup :sessionstate_genserver

  alias Pidge.Runtime.SessionState

  @example_frame_id "foreach-00005[2]"
  @example_frame_ids ["block-00018","foreach-00005[2]"]
  @obj_name :product
  @obj_name_str "product"
  @obj_name_too :other_product
  @obj_name_too_str "other_product"
  @obj_value_simple %{"item" => "book", "author" => "Pliney"}
  @obj_value_json "{\n  \"author\": \"Pliney\",\n  \"item\": \"book\"\n}"
  @obj_value_simple_too %{"item" => "statue", "author" => "Athos"}
  # @obj_value_json_too "{\n  \"author\": \"Athos\",\n  \"item\": \"statue\"\n}"

  describe "get/1 and store_object/3" do
    test "returns the object we stored" do
      SessionState.wipe()
      SessionState.store_object(@obj_name, @obj_value_simple)
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
      SessionState.store_object(@obj_name, @obj_value_simple)
      SessionState.store_object("merge_in_obj",merge_in_obj)
      SessionState.merge_into_object("merge_in_obj", @obj_name)
      state = SessionState.get()

      assert state[@obj_name_str]["item"] == "book"
      assert state[@obj_name_str]["price"] == 10.99
      assert state[@obj_name_str]["author"] == "Pliney"
    end
  end

  describe "clone_object/3" do
    test "clones an existing object in the state" do
      SessionState.wipe()
      SessionState.store_object(@obj_name, @obj_value_simple)
      SessionState.clone_object(@obj_name, "new_product")
      state = SessionState.get()

      assert state["new_product"] == @obj_value_simple
    end
  end

  describe "get_stack_state/0" do
    test "returns the stack state" do
      SessionState.start_link("foo")
      SessionState.wipe()

      # Assuming initially, the stack is empty
      assert SessionState.get_stack_state() == %{}
    end
  end

  describe "store_in_stack/3 and get_from_stack_frame/2" do
    setup do
      frame_id = @example_frame_id
      SessionState.wipe()
      SessionState.store_in_stack([], @obj_name_too, @obj_value_simple)
      SessionState.store_in_stack([frame_id], @obj_name_too, @obj_value_simple_too)
      SessionState.store_in_stack([frame_id], @obj_name, @obj_value_simple_too)
      [frame_id: frame_id]
    end

    test "stores in the specified stack frame and retrieves from it", %{frame_id: frame_id} do
      assert SessionState.get_from_stack_frame(frame_id, @obj_name) == @obj_value_simple_too
    end

    test "doesn't store in global state" do
      stack_state = SessionState.get_stack_state()
      assert Map.has_key?(stack_state[@example_frame_id], @obj_name_str)

      state = SessionState.get()
      refute Map.has_key?(state, @obj_name_str)
    end

    test "updates global state if not declared in closure" do
      stack_state = SessionState.get_stack_state()
      refute Map.has_key?(stack_state[@example_frame_id], @obj_name_too_str)

      global = SessionState.get()
      assert Map.has_key?(global, @obj_name_too_str)
      assert Map.get(global, @obj_name_too_str) == @obj_value_simple_too
    end
  end

  describe "get_from_stack/2" do
    setup do
      frame_ids = @example_frame_ids
      SessionState.wipe()
      SessionState.store_in_stack(frame_ids, @obj_name, @obj_value_simple)
      [frame_ids: frame_ids]
    end

    test "retrieves from the topmost frame first, then looks downward", %{frame_ids: frame_ids} do
      # Storing another object in the deeper frame
      different_value = %{"item" => "notebook", "author" => "Scribe"}
      SessionState.store_in_stack([Enum.at(frame_ids, 1)], @obj_name, different_value)

      # Retrieving from the stack should give the topmost frame's value (from frame1 in this case)
      assert SessionState.get_from_stack(frame_ids, @obj_name_str) == different_value
    end
  end
end
