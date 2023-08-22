defmodule Pidge.SessionStateTest do
  use ExUnit.Case, async: true
  alias Pidge.Runtime.SessionState

  @obj_name :product
  @obj_name_str "product"
  @obj_value_simple %{"item" => "book", "author" => "Pliney"}
  @obj_value_json "{\n  \"author\": \"Pliney\",\n  \"item\": \"book\"\n}"

  def get_session_id(line) do
    token = :crypto.hash(:sha256,"#{__MODULE__}_#{line}") |> Base.encode16
    "test/#{String.slice(token, 0, 8)}"
  end

  describe "get_current_state/1 and store_object/3" do
    test "returns the object we stored" do
      session_id = get_session_id(__ENV__.line)

      SessionState.wipe(session_id)
      SessionState.store_object(@obj_value_simple, @obj_name, session_id)
      state = SessionState.get_current_state(session_id)

      assert state[@obj_name_str] == @obj_value_simple
      assert state["json"][@obj_name_str] == @obj_value_json
    end
  end

  describe "merge_into_object/3" do
    test "merges the object into the existing state" do
      session_id = get_session_id(__ENV__.line)

      merge_in_obj =
        @obj_value_simple
        |> Map.put("price", 10.99)
        |> Map.delete("item")

      SessionState.wipe(session_id)
      SessionState.store_object(@obj_value_simple, @obj_name, session_id)
      SessionState.merge_into_object(merge_in_obj, @obj_name, session_id)
      state = SessionState.get_current_state(session_id)

      assert state[@obj_name_str]["item"] == "book"
      assert state[@obj_name_str]["price"] == 10.99
      assert state[@obj_name_str]["author"] == "Pliney"
    end
  end

  describe "clone_object/3" do
    test "clones an existing object in the state" do
      session_id = get_session_id(__ENV__.line)

      SessionState.wipe(session_id)
      SessionState.store_object(@obj_value_simple, @obj_name, session_id)
      SessionState.clone_object(@obj_name, "new_product", session_id)
      state = SessionState.get_current_state(session_id)

      assert state["new_product"] == @obj_value_simple
    end
  end
end
