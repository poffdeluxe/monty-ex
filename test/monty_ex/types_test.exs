defmodule MontyEx.TypesTest do
  use ExUnit.Case

  describe "Python → Elixir type conversion" do
    test "None → nil" do
      assert {:ok, %{result: nil}} = MontyEx.run("None")
    end

    test "True → true" do
      assert {:ok, %{result: true}} = MontyEx.run("True")
    end

    test "False → false" do
      assert {:ok, %{result: false}} = MontyEx.run("False")
    end

    test "int → integer" do
      assert {:ok, %{result: 42}} = MontyEx.run("42")
    end

    test "negative int" do
      assert {:ok, %{result: -7}} = MontyEx.run("-7")
    end

    test "float → float" do
      assert {:ok, %{result: 3.14}} = MontyEx.run("3.14")
    end

    test "str → String" do
      assert {:ok, %{result: "hello"}} = MontyEx.run("'hello'")
    end

    test "empty string" do
      assert {:ok, %{result: ""}} = MontyEx.run("''")
    end

    test "bytes → binary" do
      assert {:ok, %{result: result}} = MontyEx.run("b'hello'")
      assert is_binary(result)
    end

    test "list → list" do
      assert {:ok, %{result: [1, 2, 3]}} = MontyEx.run("[1, 2, 3]")
    end

    test "empty list" do
      assert {:ok, %{result: []}} = MontyEx.run("[]")
    end

    test "nested list" do
      assert {:ok, %{result: [[1, 2], [3, 4]]}} = MontyEx.run("[[1, 2], [3, 4]]")
    end

    test "tuple → tuple" do
      assert {:ok, %{result: result}} = MontyEx.run("(1, 2, 3)")
      assert result == {1, 2, 3}
    end

    test "empty tuple" do
      assert {:ok, %{result: {}}} = MontyEx.run("()")
    end

    test "dict → map" do
      assert {:ok, %{result: %{"x" => 1, "y" => 2}}} = MontyEx.run("{'x': 1, 'y': 2}")
    end

    test "empty dict" do
      assert {:ok, %{result: %{}}} = MontyEx.run("{}")
    end

    test "nested dict" do
      assert {:ok, %{result: %{"a" => %{"b" => 1}}}} = MontyEx.run("{'a': {'b': 1}}")
    end

    test "mixed types in list" do
      assert {:ok, %{result: [1, "two", 3.0, true, nil]}} =
               MontyEx.run("[1, 'two', 3.0, True, None]")
    end

    test "big int output (positive)" do
      {:ok, %{result: result}} = MontyEx.run("2 ** 100")
      assert is_integer(result)
      assert result == 1267650600228229401496703205376
    end

    test "big int output (negative)" do
      {:ok, %{result: result}} = MontyEx.run("-(2 ** 100)")
      assert is_integer(result)
      assert result == -1267650600228229401496703205376
    end

    test "big int output is integer, not string" do
      {:ok, %{result: result}} = MontyEx.run("2 ** 200")
      assert is_integer(result)
      refute is_binary(result)
    end

    test "set → list" do
      {:ok, %{result: result}} = MontyEx.run("{1, 2, 3}")
      assert is_list(result)
      assert Enum.sort(result) == [1, 2, 3]
    end

    test "frozenset → list" do
      {:ok, %{result: result}} = MontyEx.run("frozenset({1, 2, 3})")
      assert is_list(result)
      assert Enum.sort(result) == [1, 2, 3]
    end

    test "mixed nested structure" do
      {:ok, %{result: result}} = MontyEx.run("{'a': [1, (2, 3)], 'b': {'c': True}}")
      assert result["a"] == [1, {2, 3}]
      assert result["b"] == %{"c" => true}
    end
  end

  describe "Elixir → Python type conversion (inputs)" do
    test "nil → None" do
      assert {:ok, %{result: true}} = MontyEx.run("x is None", inputs: %{"x" => nil})
    end

    test "true → True" do
      assert {:ok, %{result: true}} = MontyEx.run("x is True", inputs: %{"x" => true})
    end

    test "false → False" do
      assert {:ok, %{result: true}} = MontyEx.run("x is False", inputs: %{"x" => false})
    end

    test "integer → int" do
      assert {:ok, %{result: 84}} = MontyEx.run("x * 2", inputs: %{"x" => 42})
    end

    test "float → float" do
      assert {:ok, %{result: result}} = MontyEx.run("x + 1.0", inputs: %{"x" => 2.5})
      assert_in_delta result, 3.5, 0.001
    end

    test "String → str" do
      assert {:ok, %{result: "HELLO"}} = MontyEx.run("x.upper()", inputs: %{"x" => "hello"})
    end

    test "list → list" do
      assert {:ok, %{result: 6}} = MontyEx.run("sum(x)", inputs: %{"x" => [1, 2, 3]})
    end

    test "tuple → tuple" do
      assert {:ok, %{result: 2}} = MontyEx.run("len(x)", inputs: %{"x" => {1, 2}})
    end

    test "map → dict" do
      assert {:ok, %{result: 1}} = MontyEx.run("x['a']", inputs: %{"x" => %{"a" => 1}})
    end

    test "map with atom keys → dict with string keys" do
      assert {:ok, %{result: 1}} = MontyEx.run("x['a']", inputs: %{"x" => %{a: 1}})
    end

    test "big int input" do
      big = 1267650600228229401496703205376
      assert {:ok, %{result: result}} = MontyEx.run("x + 1", inputs: %{"x" => big})
      assert result == big + 1
    end

    test "big int roundtrip" do
      big = 2 ** 100
      assert {:ok, %{result: ^big}} = MontyEx.run("x", inputs: %{"x" => big})
    end
  end
end
