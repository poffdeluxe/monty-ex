# MontyEx
Execute Python from Elixir using Rust!

Elixir bindings for [Monty](https://github.com/pydantic/monty), a minimal, secure Python interpreter written in Rust by [Pydantic](https://pydantic.dev).
Monty runs as an in-process Rust NIF, so there's no subprocess overhead or IPC.


## Quick Start

Add `monty_ex` to your `mix.exs`:

```elixir
def deps do
  [
    {:monty_ex, path: "path/to/monty_ex"}
  ]
end
```

```elixir
# Basic execution
{:ok, %{result: 3, stdout: ""}} = MontyEx.run("1 + 2")

# Input variables
{:ok, %{result: 42, stdout: ""}} = MontyEx.run("x * 2", inputs: %{"x" => 21})

# Stdout capture
{:ok, %{result: nil, stdout: "hello\n"}} = MontyEx.run("print('hello')")

# Resource limits
{:error, %MontyEx.RuntimeError{type: "TimeoutError"}} =
  MontyEx.run("while True: pass", limits: %MontyEx.ResourceLimits{max_duration_ms: 100})

# Reusable script with custom filename
script = MontyEx.Script.new("x + 1", script_name: "agent.py")
{:ok, %{result: 2, stdout: ""}} = MontyEx.run(script, inputs: %{"x" => 1})

# External function callbacks
{:ok, %{result: 42, stdout: ""}} =
  MontyEx.run("result = double(21)\nresult",
    external_functions: %{"double" => fn [x], _kwargs -> x * 2 end})

# Bang variant raises on error
%{result: 3} = MontyEx.run!("1 + 2")
```

## Features

- **Execute Python code** from Elixir via `MontyEx.run/2`
- **Pass input variables** — inject Elixir values into the Python scope
- **External function callbacks** — Python code can call Elixir functions
- **Resource limits** — cap memory, duration, allocations, and recursion depth
- **Stdout capture** — collect `print()` output
- **Reusable scripts** — wrap code with a custom `script_name` via `MontyEx.Script`
- **Error handling** — syntax and runtime errors returned as Elixir exceptions with tracebacks
- **Type conversion** — automatic conversion between Python and Elixir types

## API

### `MontyEx.run/2`

```elixir
MontyEx.run(code, opts \\ [])
```

Executes Python code and returns `{:ok, %{result: term, stdout: string}}` or `{:error, exception}`.

**Options:**

- `:inputs` — `%{String.t() => term}` map of variables to inject (atom keys are converted to strings)
- `:limits` — `%MontyEx.ResourceLimits{}` struct
- `:external_functions` — `%{String.t() => (args, kwargs -> term)}` map of functions that Python code can call. Each function receives a list of positional args and a map of keyword args with string keys. Elixir exceptions raised in callbacks propagate as Python exceptions.

### `MontyEx.run!/2`

Same as `run/2` but raises `MontyEx.SyntaxError` or `MontyEx.RuntimeError` on failure.

### `MontyEx.Script`

```elixir
script = MontyEx.Script.new(code, script_name: "agent.py")
MontyEx.run(script, inputs: %{"x" => 1})
```

Wraps Python source code with a `script_name` (defaults to `"main.py"`). The script name appears in error tracebacks. Both `run/2` and `run!/2` accept a `%MontyEx.Script{}` in place of a code string.

### `MontyEx.ResourceLimits`

```elixir
%MontyEx.ResourceLimits{
  max_allocations: nil,       # max object allocations
  max_duration_ms: nil,       # max execution time in milliseconds
  max_memory: nil,            # max memory in bytes
  gc_interval: nil,           # garbage collection interval
  max_recursion_depth: 1000   # max recursion depth (default: 1000)
}
```

All fields except `max_recursion_depth` default to `nil` (unlimited).

### Error Types

- `MontyEx.SyntaxError` — raised for Python syntax errors
- `MontyEx.RuntimeError` — raised for Python runtime errors

Both include `:type` (e.g. `"ZeroDivisionError"`), `:message`, and `:traceback` fields.

Traceback entries are maps with `:filename`, `:line`, `:column`, `:function_name`, and `:source_line`.

## Type Conversion

| Python | Elixir | Notes |
|--------|--------|-------|
| `None` | `nil` | |
| `True` / `False` | `true` / `false` | |
| `int` | `integer` | Arbitrary precision via Rustler `big_integer` |
| `float` | `float` | |
| `str` | `String` | |
| `bytes` | `binary` | |
| `list` | `list` | |
| `tuple` | `tuple` | |
| `dict` | `map` | |
| `set` | `list` | MapSet planned for the future |

When passing Elixir maps to Python, atom keys are automatically converted to string keys.

## Requirements

- **Rust** 1.85+ (for edition 2024 support required by the monty crate)
- **Elixir** 1.16+
- **Erlang/OTP** 26+

## TODO

- REPL mode (`MontyRepl`)
- State serialization/deserialization
- Type checking mode
- Async/await support
- `set` / `frozenset` → `MapSet` conversion
- `NamedTuple` / `Dataclass` → Elixir struct mapping
- Precompiled NIF binaries (`rustler_precompiled`)

## License

MIT
