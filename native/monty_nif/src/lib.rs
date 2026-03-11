mod convert;
mod error;
mod limits;

use rustler::{Encoder, Env, NifResult, Term};

mod atoms {
    rustler::atoms! {
        ok,
        error,
        result,
        stdout,
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn run<'a>(env: Env<'a>, code: String, inputs: Term<'a>, limits: Term<'a>, script_name: String) -> NifResult<Term<'a>> {
    run_inner(env, code, inputs, limits, script_name)
        .map_err(|msg| rustler::Error::RaiseTerm(Box::new(msg)))
}

fn run_inner<'a>(
    env: Env<'a>,
    code: String,
    inputs_term: Term<'a>,
    limits_term: Term<'a>,
    script_name: String,
) -> Result<Term<'a>, String> {
    let (input_names, input_values) = convert::decode_inputs(env, inputs_term)?;

    let runner = match monty::MontyRun::new(code, &script_name, input_names) {
        Ok(r) => r,
        Err(exc) => {
            let error_map = error::exception_to_term(env, exc)?;
            return Ok((atoms::error(), error_map).encode(env));
        }
    };

    let resource_limits = limits::decode_limits(env, limits_term)?;
    let tracker = monty::LimitedTracker::new(resource_limits);

    let mut stdout_buf = String::new();

    let result = runner.run(
        input_values,
        tracker,
        monty::PrintWriter::Collect(&mut stdout_buf),
    );

    match result {
        Ok(obj) => {
            let result_term = convert::monty_to_term(env, obj)?;
            let map = Term::map_new(env);
            let map = map
                .map_put(atoms::result().encode(env), result_term)
                .map_err(|_| "failed to build result map".to_string())?;
            let map = map
                .map_put(atoms::stdout().encode(env), stdout_buf.encode(env))
                .map_err(|_| "failed to build result map".to_string())?;
            Ok((atoms::ok(), map).encode(env))
        }
        Err(exc) => {
            let error_map = error::exception_to_term(env, exc)?;
            Ok((atoms::error(), error_map).encode(env))
        }
    }
}

rustler::init!("Elixir.MontyEx.Native");
