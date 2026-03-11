defmodule MontyEx.SyntaxError do
  @moduledoc """
  Raised when Python code has a syntax error.
  """

  defexception [:type, :message, :traceback]

  @type t :: %__MODULE__{
          type: String.t(),
          message: String.t(),
          traceback: [map()]
        }

  @impl true
  def message(%__MODULE__{type: type, message: msg}) do
    "#{type}: #{msg}"
  end
end

defmodule MontyEx.RuntimeError do
  @moduledoc """
  Raised when Python code encounters a runtime error.
  """

  defexception [:type, :message, :traceback]

  @type t :: %__MODULE__{
          type: String.t(),
          message: String.t(),
          traceback: [map()]
        }

  @impl true
  def message(%__MODULE__{type: type, message: msg}) do
    "#{type}: #{msg}"
  end
end
