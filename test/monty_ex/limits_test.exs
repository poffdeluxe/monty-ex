defmodule MontyEx.LimitsTest do
  use ExUnit.Case

  describe "resource limits" do
    test "timeout error" do
      assert {:error, %MontyEx.RuntimeError{}} =
               MontyEx.run("while True: pass",
                 limits: %MontyEx.ResourceLimits{max_duration_ms: 50}
               )
    end

    test "recursion limit" do
      code = """
      def recurse(n):
          return recurse(n + 1)
      recurse(0)
      """

      assert {:error, %MontyEx.RuntimeError{}} =
               MontyEx.run(code, limits: %MontyEx.ResourceLimits{max_recursion_depth: 10})
    end

    test "operations within duration limit succeed" do
      assert {:ok, %{result: 10, stdout: ""}} =
               MontyEx.run("5 + 5", limits: %MontyEx.ResourceLimits{max_duration_ms: 5000})
    end

    test "operations within recursion limit succeed" do
      code = """
      def factorial(n):
          if n <= 1:
              return 1
          return n * factorial(n - 1)
      factorial(5)
      """

      assert {:ok, %{result: 120, stdout: ""}} =
               MontyEx.run(code, limits: %MontyEx.ResourceLimits{max_recursion_depth: 50})
    end

    test "very short duration limit on looping code" do
      code = """
      x = 0
      while x < 10000000:
          x += 1
      """

      assert {:error, %MontyEx.RuntimeError{}} =
               MontyEx.run(code, limits: %MontyEx.ResourceLimits{max_duration_ms: 1})
    end
  end
end
