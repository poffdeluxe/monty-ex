defmodule MontyEx.Native do
  @moduledoc false

  use Rustler,
    otp_app: :monty_ex,
    crate: "monty_nif"

  @doc false
  def run(_code, _inputs, _limits, _script_name), do: :erlang.nif_error(:nif_not_loaded)
end
