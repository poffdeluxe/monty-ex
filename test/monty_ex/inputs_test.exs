defmodule MontyEx.InputsTest do
  use ExUnit.Case

  describe "input variables" do
    test "with input variables" do
      assert {:ok, %{result: 30, stdout: ""}} =
               MontyEx.run("x + y", inputs: %{"x" => 10, "y" => 20})
    end

    test "with atom keys in inputs (converted to strings)" do
      assert {:ok, %{result: 42, stdout: ""}} =
               MontyEx.run("x * 2", inputs: %{x: 21})
    end

    test "multiple inputs" do
      assert {:ok, %{result: 6, stdout: ""}} =
               MontyEx.run("a + b + c", inputs: %{"a" => 1, "b" => 2, "c" => 3})
    end

    test "string input" do
      assert {:ok, %{result: "HELLO", stdout: ""}} =
               MontyEx.run("x.upper()", inputs: %{"x" => "hello"})
    end

    test "list input" do
      assert {:ok, %{result: 1, stdout: ""}} =
               MontyEx.run("x[0]", inputs: %{"x" => [1, 2, 3]})
    end

    test "dict input" do
      assert {:ok, %{result: 42, stdout: ""}} =
               MontyEx.run("x['key']", inputs: %{"x" => %{"key" => 42}})
    end

    test "nested input" do
      assert {:ok, %{result: 99, stdout: ""}} =
               MontyEx.run("x['a']['b']", inputs: %{"x" => %{"a" => %{"b" => 99}}})
    end

    test "missing input raises NameError" do
      assert {:error, %MontyEx.RuntimeError{type: "NameError"}} =
               MontyEx.run("x + y", inputs: %{"x" => 1})
    end

    test "input not mutated across expression" do
      assert {:ok, %{result: 5, stdout: ""}} =
               MontyEx.run("x", inputs: %{"x" => 5})
    end

    test "boolean input" do
      assert {:ok, %{result: true, stdout: ""}} =
               MontyEx.run("x and True", inputs: %{"x" => true})
    end
  end
end
