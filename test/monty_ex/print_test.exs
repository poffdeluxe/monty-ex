defmodule MontyEx.PrintTest do
  use ExUnit.Case

  describe "print" do
    test "print captures stdout" do
      assert {:ok, %{result: nil, stdout: "hello\n"}} = MontyEx.run("print('hello')")
    end

    test "multiple prints" do
      assert {:ok, %{result: nil, stdout: "a\nb\n"}} = MontyEx.run("print('a')\nprint('b')")
    end

    test "print with multiple values" do
      assert {:ok, %{result: nil, stdout: "1 2 3\n"}} = MontyEx.run("print(1, 2, 3)")
    end

    test "print with custom separator" do
      assert {:ok, %{result: nil, stdout: "1-2-3\n"}} = MontyEx.run("print(1, 2, 3, sep='-')")
    end

    test "print with custom end" do
      assert {:ok, %{result: nil, stdout: "hi!"}} = MontyEx.run("print('hi', end='!')")
    end

    test "print with no arguments" do
      assert {:ok, %{result: nil, stdout: "\n"}} = MontyEx.run("print()")
    end

    test "print mixed types" do
      assert {:ok, %{result: nil, stdout: "1 two 3.0 True None\n"}} =
               MontyEx.run("print(1, 'two', 3.0, True, None)")
    end

    test "print in loop" do
      code = """
      for i in range(3):
          print(i)
      """

      assert {:ok, %{result: nil, stdout: "0\n1\n2\n"}} = MontyEx.run(code)
    end
  end
end
