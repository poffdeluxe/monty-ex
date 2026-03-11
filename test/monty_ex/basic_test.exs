defmodule MontyEx.BasicTest do
  use ExUnit.Case

  describe "run/2" do
    test "basic arithmetic" do
      assert {:ok, %{result: 3, stdout: ""}} = MontyEx.run("1 + 2")
    end

    test "string operations" do
      assert {:ok, %{result: "hello world", stdout: ""}} = MontyEx.run("'hello' + ' ' + 'world'")
    end

    test "returns nil for None" do
      assert {:ok, %{result: nil, stdout: ""}} = MontyEx.run("None")
    end

    test "float arithmetic" do
      assert {:ok, %{result: result, stdout: ""}} = MontyEx.run("3.14 * 2")
      assert_in_delta result, 6.28, 0.001
    end

    test "list operations" do
      assert {:ok, %{result: [1, 2, 3], stdout: ""}} = MontyEx.run("[1, 2, 3]")
    end

    test "dict operations" do
      assert {:ok, %{result: %{"a" => 1, "b" => 2}, stdout: ""}} =
               MontyEx.run("{'a': 1, 'b': 2}")
    end

    test "boolean values" do
      assert {:ok, %{result: true, stdout: ""}} = MontyEx.run("True")
      assert {:ok, %{result: false, stdout: ""}} = MontyEx.run("False")
    end

    test "empty inputs map" do
      assert {:ok, %{result: 42, stdout: ""}} = MontyEx.run("42", inputs: %{})
    end

    test "default limits (no limits specified)" do
      assert {:ok, %{result: 10, stdout: ""}} = MontyEx.run("5 + 5")
    end

    test "multiline variable assignment" do
      code = """
      x = 5
      y = 10
      x + y
      """

      assert {:ok, %{result: 15, stdout: ""}} = MontyEx.run(code)
    end

    test "function definition and call" do
      code = """
      def add(a, b):
          return a + b
      add(3, 4)
      """

      assert {:ok, %{result: 7, stdout: ""}} = MontyEx.run(code)
    end

    test "nested function calls" do
      code = """
      def double(x):
          return x * 2
      def quad(x):
          return double(double(x))
      quad(3)
      """

      assert {:ok, %{result: 12, stdout: ""}} = MontyEx.run(code)
    end
  end

  describe "run!/2" do
    test "returns result map on success" do
      assert %{result: 3, stdout: ""} = MontyEx.run!("1 + 2")
    end

    test "raises SyntaxError" do
      assert_raise MontyEx.SyntaxError, fn ->
        MontyEx.run!("def")
      end
    end

    test "raises RuntimeError" do
      assert_raise MontyEx.RuntimeError, fn ->
        MontyEx.run!("1 / 0")
      end
    end
  end
end
