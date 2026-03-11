defmodule MontyEx.Native do
  @moduledoc false

  use Rustler,
    otp_app: :monty_ex,
    crate: "monty_nif"

  @doc false
  def run(_code, _inputs, _limits, _script_name), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def start_run(_code, _inputs, _limits, _script_name), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def resume_run(_resource, _resume_result), do: :erlang.nif_error(:nif_not_loaded)
end
