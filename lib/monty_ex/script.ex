defmodule MontyEx.Script do
  @moduledoc """
  A reusable script configuration for Monty execution.

  Wraps Python source code with configuration parameters like `script_name`.

  ## Examples

      iex> script = MontyEx.Script.new("x + 1", script_name: "agent.py")
      iex> MontyEx.run(script, inputs: %{"x" => 1})
      {:ok, %{result: 2, stdout: ""}}

  """

  defstruct [:code, script_name: "main.py"]

  @type t :: %__MODULE__{code: String.t(), script_name: String.t()}

  @spec new(String.t(), keyword()) :: t()
  def new(code, opts \\ []) when is_binary(code) do
    %__MODULE__{
      code: code,
      script_name: Keyword.get(opts, :script_name, "main.py")
    }
  end
end
