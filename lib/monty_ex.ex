defmodule MontyEx do
  @moduledoc """
  Elixir bindings for Monty, a secure Python interpreter by Pydantic.

  Execute Python code safely from Elixir with input variables,
  resource limits, and stdout capture.
  """

  alias MontyEx.Native
  alias MontyEx.ResourceLimits
  alias MontyEx.Script

  @type run_opt ::
          {:inputs, %{optional(String.t()) => term()}}
          | {:limits, ResourceLimits.t()}

  @doc """
  Execute Python code and return the result.

  Accepts either a code string or a `%MontyEx.Script{}` struct.

  ## Options

    * `:inputs` - A map of variable names to values to inject into the Python scope.
    * `:limits` - A `%MontyEx.ResourceLimits{}` struct to constrain execution.

  ## Examples

      iex> MontyEx.run("1 + 2")
      {:ok, %{result: 3, stdout: ""}}

      iex> MontyEx.run("x + y", inputs: %{"x" => 10, "y" => 20})
      {:ok, %{result: 30, stdout: ""}}

      iex> script = MontyEx.Script.new("x + 1", script_name: "agent.py")
      iex> MontyEx.run(script, inputs: %{"x" => 1})
      {:ok, %{result: 2, stdout: ""}}

      iex> MontyEx.run("1 / 0")
      {:error, %MontyEx.RuntimeError{type: "ZeroDivisionError", ...}}

  """
  @spec run(String.t() | Script.t(), [run_opt()]) :: {:ok, %{result: term(), stdout: String.t()}} | {:error, Exception.t()}
  def run(code_or_script, opts \\ [])

  def run(code, opts) when is_binary(code) do
    do_run(code, "main.py", opts)
  end

  def run(%Script{code: code, script_name: script_name}, opts) do
    do_run(code, script_name, opts)
  end

  @doc """
  Execute Python code and return the result, raising on error.

  Same as `run/2` but raises `MontyEx.SyntaxError` or `MontyEx.RuntimeError` on failure.
  """
  @spec run!(String.t() | Script.t(), [run_opt()]) :: %{result: term(), stdout: String.t()}
  def run!(code_or_script, opts \\ []) do
    case run(code_or_script, opts) do
      {:ok, result} -> result
      {:error, exception} -> raise exception
    end
  end

  defp do_run(code, script_name, opts) do
    inputs = opts |> Keyword.get(:inputs, %{}) |> normalize_inputs()
    limits = opts |> Keyword.get(:limits, %ResourceLimits{}) |> ResourceLimits.to_map()

    with {:error, error_map} <- Native.run(code, inputs, limits, script_name) do
      {:error, to_exception(error_map)}
    end
  end

  defp normalize_inputs(inputs) when is_map(inputs) do
    Map.new(inputs, fn {k, v} ->
      {to_string(k), v}
    end)
  end

  defp to_exception(%{kind: :syntax, type: type, message: message, traceback: traceback}) do
    %MontyEx.SyntaxError{type: type, message: message, traceback: traceback}
  end

  defp to_exception(%{kind: :runtime, type: type, message: message, traceback: traceback}) do
    %MontyEx.RuntimeError{type: type, message: message, traceback: traceback}
  end
end
