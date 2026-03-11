mod convert;
mod error;
mod execution;
mod limits;

use rustler::{Encoder, Env, NifResult, ResourceArc, Term};

use execution::PausedExecution;

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

#[rustler::nif(schedule = "DirtyCpu")]
fn start_run<'a>(
    env: Env<'a>,
    code: String,
    inputs: Term<'a>,
    limits: Term<'a>,
    script_name: String,
) -> NifResult<Term<'a>> {
    start_run_inner(env, code, inputs, limits, script_name)
        .map_err(|msg| rustler::Error::RaiseTerm(Box::new(msg)))
}

fn start_run_inner<'a>(
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

    let progress = runner.start(
        input_values,
        tracker,
        monty::PrintWriter::Collect(&mut stdout_buf),
    );

    execution::handle_progress(env, progress, stdout_buf)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn resume_run<'a>(
    env: Env<'a>,
    resource: ResourceArc<PausedExecution>,
    resume_term: Term<'a>,
) -> NifResult<Term<'a>> {
    resume_run_inner(env, resource, resume_term)
        .map_err(|msg| rustler::Error::RaiseTerm(Box::new(msg)))
}

fn resume_run_inner<'a>(
    env: Env<'a>,
    resource: ResourceArc<PausedExecution>,
    resume_term: Term<'a>,
) -> Result<Term<'a>, String> {
    let state = {
        let mut guard = resource
            .state
            .lock()
            .map_err(|e| format!("failed to lock paused state (mutex poisoned by prior panic): {e}"))?;
        std::mem::replace(&mut *guard, execution::PausedState::Consumed)
    };

    let mut stdout_buf = {
        let mut guard = resource
            .stdout_buf
            .lock()
            .map_err(|e| format!("failed to lock stdout buffer (mutex poisoned by prior panic): {e}"))?;
        std::mem::take(&mut *guard)
    };

    let progress = match state {
        execution::PausedState::NameLookup(nl) => {
            let result = execution::decode_name_lookup_result(env, resume_term)?;
            nl.resume(result, monty::PrintWriter::Collect(&mut stdout_buf))
        }
        execution::PausedState::FunctionCall(fc) => {
            let result = execution::decode_function_call_result(env, resume_term)?;
            fc.resume(result, monty::PrintWriter::Collect(&mut stdout_buf))
        }
        execution::PausedState::Consumed => {
            return Err("paused execution has already been consumed".to_string());
        }
    };

    execution::handle_progress(env, progress, stdout_buf)
}

rustler::init!("Elixir.MontyEx.Native");
