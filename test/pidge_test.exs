defmodule PidgeTest do
  use ExUnit.Case
  doctest Pidge

  test "greets the world" do
    assert Pidge.hello() == :world
  end
end
