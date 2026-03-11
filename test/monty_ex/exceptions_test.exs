defmodule MontyEx.ExceptionsTest do
  use ExUnit.Case

  describe "syntax errors" do
    test "returns SyntaxError for invalid syntax" do
      assert {:error, %MontyEx.SyntaxError{type: "SyntaxError"} = err} =
               MontyEx.run("def")

      assert is_binary(err.message)
      assert is_list(err.traceback)
    end

    test "SyntaxError has traceback with location" do
      assert {:error, %MontyEx.SyntaxError{traceback: traceback}} =
               MontyEx.run("1 +")

      assert is_list(traceback)

      if length(traceback) > 0 do
        frame = hd(traceback)
        assert Map.has_key?(frame, :filename)
        assert Map.has_key?(frame, :line)
        assert Map.has_key?(frame, :column)
      end
    end

    test "SyntaxError message formatting" do
      {:error, err} = MontyEx.run("def")
      assert Exception.message(err) =~ "SyntaxError"
    end
  end

  describe "runtime errors" do
    test "ZeroDivisionError" do
      assert {:error, %MontyEx.RuntimeError{type: "ZeroDivisionError"} = err} =
               MontyEx.run("1 / 0")

      assert is_binary(err.message)
    end

    test "NameError" do
      assert {:error, %MontyEx.RuntimeError{type: "NameError"}} =
               MontyEx.run("undefined_variable")
    end

    test "TypeError" do
      assert {:error, %MontyEx.RuntimeError{type: "TypeError"}} =
               MontyEx.run("'a' + 1")
    end

    test "IndexError" do
      assert {:error, %MontyEx.RuntimeError{type: "IndexError"}} =
               MontyEx.run("[1, 2][5]")
    end

    test "KeyError" do
      assert {:error, %MontyEx.RuntimeError{type: "KeyError"}} =
               MontyEx.run("{'a': 1}['b']")
    end

    test "ValueError" do
      assert {:error, %MontyEx.RuntimeError{type: "ValueError"}} =
               MontyEx.run("int('abc')")
    end

    test "AttributeError" do
      assert {:error, %MontyEx.RuntimeError{type: "AttributeError"}} =
               MontyEx.run("(1).foo")
    end

    test "AssertionError" do
      assert {:error, %MontyEx.RuntimeError{type: "AssertionError"}} =
               MontyEx.run("assert False")
    end

    test "NotImplementedError" do
      assert {:error, %MontyEx.RuntimeError{type: "NotImplementedError"}} =
               MontyEx.run("raise NotImplementedError('todo')")
    end

    test "try-except catches exception" do
      code = """
      try:
          1 / 0
      except:
          result = 'caught'
      result
      """

      assert {:ok, %{result: "caught", stdout: ""}} = MontyEx.run(code)
    end

    test "nested function traceback has multiple frames" do
      code = """
      def inner():
          raise ValueError("deep error")
      def outer():
          return inner()
      outer()
      """

      assert {:error, %MontyEx.RuntimeError{traceback: traceback}} = MontyEx.run(code)
      assert length(traceback) > 1
    end

    test "RuntimeError message formatting" do
      {:error, err} = MontyEx.run("1 / 0")
      msg = Exception.message(err)
      assert msg =~ "ZeroDivisionError"
    end

    test "runtime error has traceback" do
      {:error, %MontyEx.RuntimeError{traceback: traceback}} = MontyEx.run("1 / 0")
      assert is_list(traceback)
    end
  end
end
