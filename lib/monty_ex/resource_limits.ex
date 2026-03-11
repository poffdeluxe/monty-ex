defmodule MontyEx.ResourceLimits do
  @moduledoc """
  Resource limits for Python code execution.

  All fields are optional. When `nil`, no limit is applied for that resource.
  """

  defstruct [
    :max_allocations,
    :max_duration_ms,
    :max_memory,
    :gc_interval,
    max_recursion_depth: 1000
  ]

  @type t :: %__MODULE__{
          max_allocations: non_neg_integer() | nil,
          max_duration_ms: non_neg_integer() | nil,
          max_memory: non_neg_integer() | nil,
          gc_interval: non_neg_integer() | nil,
          max_recursion_depth: non_neg_integer()
        }

  @doc false
  def to_map(%__MODULE__{} = limits) do
    limits
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
