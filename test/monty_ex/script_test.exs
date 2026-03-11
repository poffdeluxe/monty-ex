defmodule MontyEx.ScriptTest do
  use ExUnit.Case

  alias MontyEx.Script

  describe "Script.new/2" do
    test "creates script with default script_name" do
      script = Script.new("1 + 1")
      assert script.code == "1 + 1"
      assert script.script_name == "main.py"
    end

    test "creates script with custom script_name" do
      script = Script.new("1 + 1", script_name: "agent.py")
      assert script.code == "1 + 1"
      assert script.script_name == "agent.py"
    end
  end

  describe "run/2 with Script" do
    test "basic execution" do
      script = Script.new("1 + 2")
      assert {:ok, %{result: 3, stdout: ""}} = MontyEx.run(script)
    end

    test "with inputs" do
      script = Script.new("x + y")
      assert {:ok, %{result: 30, stdout: ""}} = MontyEx.run(script, inputs: %{"x" => 10, "y" => 20})
    end

    test "with limits" do
      script = Script.new("while True: pass")

      assert {:error, %MontyEx.RuntimeError{}} =
               MontyEx.run(script, limits: %MontyEx.ResourceLimits{max_duration_ms: 100})
    end

    test "custom script_name appears in error traceback" do
      script = Script.new("1 / 0", script_name: "custom.py")
      assert {:error, %MontyEx.RuntimeError{traceback: traceback}} = MontyEx.run(script)
      filenames = Enum.map(traceback, & &1.filename)
      assert "custom.py" in filenames
    end
  end

  describe "run!/2 with Script" do
    test "returns result on success" do
      script = Script.new("1 + 2")
      assert %{result: 3, stdout: ""} = MontyEx.run!(script)
    end

    test "raises on error" do
      script = Script.new("1 / 0")

      assert_raise MontyEx.RuntimeError, fn ->
        MontyEx.run!(script)
      end
    end
  end
end
