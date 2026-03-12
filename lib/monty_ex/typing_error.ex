defmodule MontyEx.TypingError do
  @moduledoc """
  Raised when Python code fails type checking.
  """

  defexception [:diagnostics]

  @type t :: %__MODULE__{diagnostics: String.t()}

  @impl true
  def message(%__MODULE__{diagnostics: diagnostics}) do
    "Type checking failed:\n#{diagnostics}"
  end
end
