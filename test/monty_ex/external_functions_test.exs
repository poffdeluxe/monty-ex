defmodule MontyEx.ExternalFunctionsTest do
  use ExUnit.Case

  # =============================================================================
  # Basic external function tests
  # =============================================================================

  describe "basic external function calls" do
    test "no args" do
      assert {:ok, %{result: "called", stdout: ""}} =
               MontyEx.run("noop()",
                 external_functions: %{"noop" => fn [], _kwargs -> "called" end}
               )
    end

    test "positional args" do
      ext_fn = fn args, _kwargs ->
        assert args == [1, 2, 3]
        "ok"
      end

      assert {:ok, %{result: "ok", stdout: ""}} =
               MontyEx.run("func(1, 2, 3)", external_functions: %{"func" => ext_fn})
    end

    test "kwargs only" do
      ext_fn = fn args, kwargs ->
        assert args == []
        assert kwargs == %{"a" => 1, "b" => "two"}
        "ok"
      end

      assert {:ok, %{result: "ok", stdout: ""}} =
               MontyEx.run("func(a=1, b=\"two\")", external_functions: %{"func" => ext_fn})
    end

    test "mixed positional and kwargs" do
      ext_fn = fn args, kwargs ->
        assert args == [1, 2]
        assert kwargs == %{"x" => "hello", "y" => true}
        "ok"
      end

      assert {:ok, %{result: "ok", stdout: ""}} =
               MontyEx.run("func(1, 2, x=\"hello\", y=True)",
                 external_functions: %{"func" => ext_fn}
               )
    end

    test "complex types as args" do
      ext_fn = fn [list_arg, dict_arg], _kwargs ->
        assert list_arg == [1, 2]
        assert dict_arg == %{"key" => "value"}
        "ok"
      end

      assert {:ok, %{result: "ok", stdout: ""}} =
               MontyEx.run("func([1, 2], {\"key\": \"value\"})",
                 external_functions: %{"func" => ext_fn}
               )
    end
  end

  # =============================================================================
  # Return value tests
  # =============================================================================

  describe "return values" do
    test "returning a string" do
      assert {:ok, %{result: "hello", stdout: ""}} =
               MontyEx.run("greet()",
                 external_functions: %{"greet" => fn [], _kwargs -> "hello" end}
               )
    end

    test "returning a list" do
      assert {:ok, %{result: [1, 2, 3], stdout: ""}} =
               MontyEx.run("get_list()",
                 external_functions: %{"get_list" => fn [], _kwargs -> [1, 2, 3] end}
               )
    end

    test "returning a map" do
      assert {:ok, %{result: %{"a" => 1}, stdout: ""}} =
               MontyEx.run("get_dict()",
                 external_functions: %{"get_dict" => fn [], _kwargs -> %{"a" => 1} end}
               )
    end

    test "returning nil" do
      assert {:ok, %{result: nil, stdout: ""}} =
               MontyEx.run("get_none()",
                 external_functions: %{"get_none" => fn [], _kwargs -> nil end}
               )
    end

    test "returning complex nested type" do
      get_data = fn [], _kwargs ->
        %{"a" => [1, 2, 3], "b" => %{"nested" => true}}
      end

      assert {:ok, %{result: result, stdout: ""}} =
               MontyEx.run("get_data()", external_functions: %{"get_data" => get_data})

      assert result == %{"a" => [1, 2, 3], "b" => %{"nested" => true}}
    end
  end

  # =============================================================================
  # Multiple external functions tests
  # =============================================================================

  describe "multiple external functions" do
    test "two different external functions" do
      ext_fns = %{
        "add" => fn [a, b], _kwargs -> a + b end,
        "mul" => fn [a, b], _kwargs -> a * b end
      }

      assert {:ok, %{result: 15, stdout: ""}} =
               MontyEx.run("add(1, 2) + mul(3, 4)", external_functions: ext_fns)
    end

    test "external function called multiple times with state" do
      counter = :counters.new(1, [])

      ext_fn = fn [], _kwargs ->
        :counters.add(counter, 1, 1)
        :counters.get(counter, 1)
      end

      assert {:ok, %{result: 6, stdout: ""}} =
               MontyEx.run("counter() + counter() + counter()",
                 external_functions: %{"counter" => ext_fn}
               )

      assert :counters.get(counter, 1) == 3
    end

    test "chained calls in sequence" do
      ext_fns = %{
        "double" => fn [x], _kwargs -> x * 2 end,
        "add_one" => fn [x], _kwargs -> x + 1 end
      }

      code = """
      a = double(5)
      b = add_one(a)
      b
      """

      assert {:ok, %{result: 11, stdout: ""}} =
               MontyEx.run(code, external_functions: ext_fns)
    end

    test "external function called in a loop" do
      code = """
      total = 0
      for i in range(5):
          total = total + increment(i)
      total
      """

      assert {:ok, %{result: 15, stdout: ""}} =
               MontyEx.run(code,
                 external_functions: %{"increment" => fn [x], _kwargs -> x + 1 end}
               )
    end
  end

  # =============================================================================
  # Combined with other options tests
  # =============================================================================

  describe "combined with other options" do
    test "combined with inputs" do
      ext_fn = fn [x], _kwargs ->
        assert x == 5
        x * 10
      end

      assert {:ok, %{result: 50, stdout: ""}} =
               MontyEx.run("process(x)",
                 inputs: %{"x" => 5},
                 external_functions: %{"process" => ext_fn}
               )
    end

    test "combined with limits" do
      assert {:ok, %{result: 4, stdout: ""}} =
               MontyEx.run("double(2)",
                 limits: %MontyEx.ResourceLimits{max_allocations: 10_000},
                 external_functions: %{"double" => fn [x], _kwargs -> x * 2 end}
               )
    end

    test "stdout captured across external function calls" do
      code = """
      print("before")
      result = get_value()
      print("after")
      result
      """

      assert {:ok, %{result: 42, stdout: stdout}} =
               MontyEx.run(code,
                 external_functions: %{"get_value" => fn [], _kwargs -> 42 end}
               )

      assert stdout =~ "before"
      assert stdout =~ "after"
    end

    test "atom keys in external_functions map normalized to strings" do
      assert {:ok, %{result: 10, stdout: ""}} =
               MontyEx.run("double(5)",
                 external_functions: %{double: fn [x], _kwargs -> x * 2 end}
               )
    end
  end

  # =============================================================================
  # Error handling tests
  # =============================================================================

  describe "error handling" do
    test "undefined function raises NameError" do
      assert {:error, %MontyEx.RuntimeError{type: "NameError"}} =
               MontyEx.run("missing()", external_functions: %{})
    end

    test "wrong function name raises NameError" do
      # Provide "bar" but call "foo"
      assert {:error, %MontyEx.RuntimeError{type: "NameError"}} =
               MontyEx.run("foo()",
                 external_functions: %{"bar" => fn [], _kwargs -> 1 end}
               )
    end

    test "callback raising propagates as Python exception" do
      ext_fn = fn _args, _kwargs ->
        raise ArgumentError, "bad argument"
      end

      assert {:error, %MontyEx.RuntimeError{type: "ValueError", message: message}} =
               MontyEx.run("fail()", external_functions: %{"fail" => ext_fn})

      assert message =~ "bad argument"
    end

    test "callback exception type preserved" do
      ext_fn = fn _args, _kwargs ->
        raise RuntimeError, "type error message"
      end

      assert {:error, %MontyEx.RuntimeError{type: "RuntimeError", message: message}} =
               MontyEx.run("fail()", external_functions: %{"fail" => ext_fn})

      assert message =~ "type error message"
    end

    test "callback error catchable with try/except in Python" do
      ext_fn = fn _args, _kwargs ->
        raise ArgumentError, "caught error"
      end

      code = """
      try:
          fail()
      except ValueError:
          caught = True
      caught
      """

      assert {:ok, %{result: true, stdout: ""}} =
               MontyEx.run(code, external_functions: %{"fail" => ext_fn})
    end

    test "exception in expression context" do
      ext_fn = fn _args, _kwargs ->
        raise RuntimeError, "mid-expression error"
      end

      assert {:error, %MontyEx.RuntimeError{type: "RuntimeError", message: message}} =
               MontyEx.run("1 + fail() + 2", external_functions: %{"fail" => ext_fn})

      assert message =~ "mid-expression error"
    end

    test "exception after successful call" do
      code = """
      a = success()
      b = fail()
      a + b
      """

      ext_fns = %{
        "success" => fn [], _kwargs -> 10 end,
        "fail" => fn [], _kwargs -> raise RuntimeError, "second call fails" end
      }

      assert {:error, %MontyEx.RuntimeError{type: "RuntimeError", message: message}} =
               MontyEx.run(code, external_functions: ext_fns)

      assert message =~ "second call fails"
    end

    test "exception with finally block" do
      code = """
      finally_ran = False
      try:
          fail()
      except ValueError:
          pass
      finally:
          finally_ran = True
      finally_ran
      """

      ext_fn = fn _args, _kwargs ->
        raise ArgumentError, "error"
      end

      assert {:ok, %{result: true, stdout: ""}} =
               MontyEx.run(code, external_functions: %{"fail" => ext_fn})
    end

    test "exception in nested try with finally" do
      code = """
      outer_caught = False
      finally_ran = False
      try:
          try:
              fail()
          except TypeError:
              pass
          finally:
              finally_ran = True
      except ValueError:
          outer_caught = True
      (outer_caught, finally_ran)
      """

      ext_fn = fn _args, _kwargs ->
        raise ArgumentError, "propagates to outer"
      end

      assert {:ok, %{result: {true, true}, stdout: ""}} =
               MontyEx.run(code, external_functions: %{"fail" => ext_fn})
    end

    test "uncaught callback exception propagates" do
      ext_fn = fn _args, _kwargs ->
        raise ArgumentError, "uncaught error"
      end

      assert {:error, %MontyEx.RuntimeError{type: "ValueError", message: message}} =
               MontyEx.run("fail()", external_functions: %{"fail" => ext_fn})

      assert message =~ "uncaught error"
    end
  end

  # =============================================================================
  # Exception hierarchy tests
  # =============================================================================

  describe "exception hierarchy" do
    @exception_parent_child_pairs [
      {"ZeroDivisionError", "ArithmeticError"},
      {"OverflowError", "ArithmeticError"},
      {"NotImplementedError", "RuntimeError"},
      {"RecursionError", "RuntimeError"},
      {"KeyError", "LookupError"},
      {"IndexError", "LookupError"}
    ]

    for {child_type, parent_type} <- @exception_parent_child_pairs do
      test "#{child_type} caught by parent #{parent_type}" do
        child_type = unquote(child_type)
        parent_type = unquote(parent_type)

        # Raise the child exception in Python and verify the parent handler catches it
        code = """
        try:
            raise #{child_type}("test")
        except #{parent_type}:
            caught = "parent"
        except #{child_type}:
            caught = "child"
        caught
        """

        assert {:ok, %{result: "parent", stdout: ""}} = MontyEx.run(code)
      end
    end
  end

  # =============================================================================
  # run!/2 tests
  # =============================================================================

  describe "run!/2 with external functions" do
    test "returns result on success" do
      assert %{result: 6, stdout: ""} =
               MontyEx.run!("triple(2)",
                 external_functions: %{"triple" => fn [x], _kwargs -> x * 3 end}
               )
    end

    test "raises on callback error" do
      ext_fn = fn _args, _kwargs -> raise "boom" end

      assert_raise MontyEx.RuntimeError, fn ->
        MontyEx.run!("bad()", external_functions: %{"bad" => ext_fn})
      end
    end
  end
end
