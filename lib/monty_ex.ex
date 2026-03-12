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
          | {:external_functions, %{optional(String.t()) => function()}}

  @doc """
  Execute Python code and return the result.

  Accepts either a code string or a `%MontyEx.Script{}` struct.

  ## Options

    * `:inputs` - A map of variable names to values to inject into the Python scope.
    * `:limits` - A `%MontyEx.ResourceLimits{}` struct to constrain execution.
    * `:external_functions` - A map of function names to Elixir functions that Python code
      can call. Each function receives `(args, kwargs)` where `args` is a list of positional
      arguments and `kwargs` is a map of keyword arguments with string keys.

  ## Examples

      iex> MontyEx.run("1 + 2")
      {:ok, %{result: 3, stdout: ""}}

      iex> MontyEx.run("x + y", inputs: %{"x" => 10, "y" => 20})
      {:ok, %{result: 30, stdout: ""}}

      iex> MontyEx.run("result = add(1, 2)\\nresult",
      ...>   external_functions: %{"add" => fn [a, b], _kwargs -> a + b end})
      {:ok, %{result: 3, stdout: ""}}

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
    ext_fns = opts |> Keyword.get(:external_functions, nil) |> normalize_ext_fns()

    if ext_fns do
      do_run_with_callbacks(code, inputs, limits, script_name, ext_fns)
    else
      with {:error, error_map} <- Native.run(code, inputs, limits, script_name) do
        {:error, to_exception(error_map)}
      end
    end
  end

  defp do_run_with_callbacks(code, inputs, limits, script_name, ext_fns) do
    code
    |> Native.start_run(inputs, limits, script_name)
    |> execute_loop(ext_fns)
  rescue
    e in ErlangError ->
      {:error,
       %MontyEx.RuntimeError{
         type: "NifError",
         message: "NIF execution failed: #{inspect(e.original)}",
         traceback: []
       }}
  end

  defp execute_loop({:ok, result_map}, _ext_fns), do: {:ok, result_map}
  defp execute_loop({:error, error_map}, _ext_fns), do: {:error, to_exception(error_map)}

  defp execute_loop({:name_lookup, ref, %{name: name}}, ext_fns) do
    resume_result =
      if Map.has_key?(ext_fns, name),
        do: {:value, name},
        else: :undefined

    ref
    |> Native.resume_run(resume_result)
    |> execute_loop(ext_fns)
  end

  defp execute_loop({:function_call, ref, info}, ext_fns) do
    %{function_name: name, args: args, kwargs: kwargs} = info

    resume_result =
      case Map.fetch(ext_fns, name) do
        {:ok, func} ->
          try do
            {:return, func.(args, kwargs)}
          rescue
            e in FunctionClauseError ->
              reraise ArgumentError,
                      "external function \"#{name}\" callback failed: expected fn(args, kwargs) " <>
                        "with 2 arguments. Got: #{Exception.message(e)}",
                      __STACKTRACE__

            e ->
              {:error, %{type: exception_type_name(e), message: Exception.message(e)}}
          end

        :error ->
          {:not_found, name}
      end

    ref
    |> Native.resume_run(resume_result)
    |> execute_loop(ext_fns)
  end

  defp normalize_inputs(inputs) when is_map(inputs) do
    Map.new(inputs, fn {k, v} ->
      {to_string(k), v}
    end)
  end

  defp normalize_ext_fns(nil), do: nil

  defp normalize_ext_fns(ext_fns) when ext_fns == %{}, do: nil

  defp normalize_ext_fns(ext_fns) when is_map(ext_fns) do
    Map.new(ext_fns, fn {k, v} ->
      {to_string(k), v}
    end)
  end

  # Map Elixir exception module names to Python exception type names.
  @elixir_to_python_exc %{
    ArgumentError => "ValueError",
    ArithmeticError => "ArithmeticError",
    RuntimeError => "RuntimeError",
    KeyError => "KeyError"
  }

  defp exception_type_name(e) do
    Map.get(@elixir_to_python_exc, e.__struct__, "RuntimeError")
  end

  @type type_check_opt ::
          {:stubs, String.t()}
          | {:format, :full | :concise | :json | :pylint | :gitlab | :github}

  @doc """
  Perform static type checking on Python code.

  Accepts either a code string or a `%MontyEx.Script{}` struct.

  ## Options

    * `:stubs` - A string of type stub definitions (`.pyi` style) to use during type checking.
    * `:format` - The diagnostic output format. One of `:full`, `:concise`, `:json`,
      `:pylint`, `:gitlab`, `:github`. Defaults to `:full`.

  ## Examples

      iex> MontyEx.type_check("x: int = 1")
      :ok

      iex> {:error, %MontyEx.TypingError{}} = MontyEx.type_check("x: int = 'hello'")

  """
  @spec type_check(String.t() | Script.t(), [type_check_opt()]) ::
          :ok | {:error, MontyEx.TypingError.t()}
  def type_check(code_or_script, opts \\ [])

  def type_check(code, opts) when is_binary(code) do
    do_type_check(code, "main.py", opts)
  end

  def type_check(%Script{code: code, script_name: script_name}, opts) do
    do_type_check(code, script_name, opts)
  end

  @doc """
  Perform static type checking on Python code, raising on type errors.

  Same as `type_check/2` but raises `MontyEx.TypingError` on failure.
  """
  @spec type_check!(String.t() | Script.t(), [type_check_opt()]) :: :ok
  def type_check!(code_or_script, opts \\ []) do
    case type_check(code_or_script, opts) do
      :ok -> :ok
      {:error, exception} -> raise exception
    end
  end

  defp do_type_check(code, script_name, opts) do
    stubs = Keyword.get(opts, :stubs, nil)
    format = Keyword.get(opts, :format, :full)

    case Native.type_check(code, stubs, format, script_name) do
      {:ok, :no_errors} -> :ok
      {:error, %{diagnostics: diags}} -> {:error, %MontyEx.TypingError{diagnostics: diags}}
    end
  end

  defp to_exception(%{kind: :syntax, type: type, message: message, traceback: traceback}) do
    %MontyEx.SyntaxError{type: type, message: message, traceback: traceback}
  end

  defp to_exception(%{kind: :runtime, type: type, message: message, traceback: traceback}) do
    %MontyEx.RuntimeError{type: type, message: message, traceback: traceback}
  end
end
