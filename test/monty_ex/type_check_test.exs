defmodule MontyEx.TypeCheckTest do
  use ExUnit.Case, async: true

  alias MontyEx.TypingError

  describe "type_check/2" do
    test "well-typed code returns :ok" do
      assert :ok = MontyEx.type_check("x: int = 1")
    end

    test "unannotated code returns :ok" do
      assert :ok = MontyEx.type_check("x = 1 + 2")
    end

    test "type mismatch returns error with diagnostics" do
      assert {:error, %TypingError{diagnostics: diags}} =
               MontyEx.type_check("x: int = 'hello'")

      assert is_binary(diags)
      assert diags != ""
    end

    test "stubs option provides type definitions" do
      stubs = """
      def add(a: int, b: int) -> int: ...
      """

      code = """
      result: str = add(1, 2)
      """

      assert {:error, %TypingError{diagnostics: diags}} =
               MontyEx.type_check(code, stubs: stubs)

      assert is_binary(diags)
    end

    test "accepts Script struct" do
      script = MontyEx.Script.new("x: int = 1", script_name: "check.py")
      assert :ok = MontyEx.type_check(script)
    end

    test "format option :concise" do
      assert {:error, %TypingError{diagnostics: diags}} =
               MontyEx.type_check("x: int = 'hello'", format: :concise)

      assert is_binary(diags)
    end

    test "format option :json" do
      assert {:error, %TypingError{diagnostics: diags}} =
               MontyEx.type_check("x: int = 'hello'", format: :json)

      assert is_binary(diags)
    end
  end

  describe "type_check!/2" do
    test "returns :ok on valid types" do
      assert :ok = MontyEx.type_check!("x: int = 1")
    end

    test "raises TypingError on type errors" do
      assert_raise TypingError, fn ->
        MontyEx.type_check!("x: int = 'hello'")
      end
    end
  end
end
