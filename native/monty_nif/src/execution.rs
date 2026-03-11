use std::sync::Mutex;

use monty::{
    ExtFunctionResult, FunctionCall, LimitedTracker, MontyException, MontyObject, NameLookup,
    NameLookupResult, RunProgress,
};
use rustler::{Encoder, Env, ResourceArc, Term};

use crate::convert;
use crate::error;

pub enum PausedState {
    FunctionCall(FunctionCall<LimitedTracker>),
    NameLookup(NameLookup<LimitedTracker>),
    Consumed,
}

pub struct PausedExecution {
    pub state: Mutex<PausedState>,
    pub stdout_buf: Mutex<String>,
}

#[rustler::resource_impl]
impl rustler::Resource for PausedExecution {}

mod atoms {
    rustler::atoms! {
        ok,
        error,
        result,
        stdout,
        function_call,
        name_lookup,
        function_name,
        args,
        kwargs,
        method_call,
        name,
        call_id,

        not_found,
        value,
        undefined,
    }
}

/// Convert a `RunProgress` into a NIF return term.
///
/// - `Complete(obj)` → `{:ok, %{result: term, stdout: string}}`
/// - `FunctionCall(fc)` → `{:function_call, ref, %{function_name:, args:, kwargs:, call_id:, method_call:}}`
/// - `NameLookup(nl)` → `{:name_lookup, ref, %{name: string}}`
/// - Error cases → `{:error, error_map}`
pub fn handle_progress<'a>(
    env: Env<'a>,
    progress: Result<RunProgress<LimitedTracker>, MontyException>,
    stdout_buf: String,
) -> Result<Term<'a>, String> {
    match progress {
        Ok(RunProgress::Complete(obj)) => {
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
        Ok(RunProgress::FunctionCall(fc)) => {
            // Build info map
            let args_terms: Vec<Term> = fc
                .args
                .iter()
                .map(|o| convert::monty_to_term(env, o.clone()))
                .collect::<Result<_, _>>()?;

            let mut kwargs_map = Term::map_new(env);
            for (k, v) in &fc.kwargs {
                let key_term = convert::monty_to_term(env, k.clone())?;
                let val_term = convert::monty_to_term(env, v.clone())?;
                kwargs_map = kwargs_map
                    .map_put(key_term, val_term)
                    .map_err(|_| "failed to build kwargs map".to_string())?;
            }

            let mut info = Term::map_new(env);
            info = info
                .map_put(
                    atoms::function_name().encode(env),
                    fc.function_name.encode(env),
                )
                .map_err(|_| "failed to build info map".to_string())?;
            info = info
                .map_put(atoms::args().encode(env), args_terms.encode(env))
                .map_err(|_| "failed to build info map".to_string())?;
            info = info
                .map_put(atoms::kwargs().encode(env), kwargs_map)
                .map_err(|_| "failed to build info map".to_string())?;
            info = info
                .map_put(atoms::call_id().encode(env), fc.call_id.encode(env))
                .map_err(|_| "failed to build info map".to_string())?;
            info = info
                .map_put(atoms::method_call().encode(env), fc.method_call.encode(env))
                .map_err(|_| "failed to build info map".to_string())?;

            let resource = ResourceArc::new(PausedExecution {
                state: Mutex::new(PausedState::FunctionCall(fc)),
                stdout_buf: Mutex::new(stdout_buf),
            });

            Ok((atoms::function_call(), resource.encode(env), info).encode(env))
        }
        Ok(RunProgress::NameLookup(nl)) => {
            let mut info = Term::map_new(env);
            info = info
                .map_put(atoms::name().encode(env), nl.name.encode(env))
                .map_err(|_| "failed to build info map".to_string())?;

            let resource = ResourceArc::new(PausedExecution {
                state: Mutex::new(PausedState::NameLookup(nl)),
                stdout_buf: Mutex::new(stdout_buf),
            });

            Ok((atoms::name_lookup(), resource.encode(env), info).encode(env))
        }
        Ok(RunProgress::OsCall(_)) => {
            let exc = MontyException::new(
                monty::ExcType::NotImplementedError,
                Some("OS calls are not supported".to_string()),
            );
            let error_map = error::exception_to_term(env, exc)?;
            Ok((atoms::error(), error_map).encode(env))
        }
        Ok(RunProgress::ResolveFutures(_)) => {
            let exc = MontyException::new(
                monty::ExcType::NotImplementedError,
                Some("Async operations are not supported".to_string()),
            );
            let error_map = error::exception_to_term(env, exc)?;
            Ok((atoms::error(), error_map).encode(env))
        }
        Err(exc) => {
            let error_map = error::exception_to_term(env, exc)?;
            Ok((atoms::error(), error_map).encode(env))
        }
    }
}

/// Decode an Elixir term into a `NameLookupResult`.
///
/// - `:undefined` → `NameLookupResult::Undefined`
/// - `{:value, name_string}` → `NameLookupResult::Value(MontyObject::Function { name, docstring: None })`
pub fn decode_name_lookup_result<'a>(
    env: Env<'a>,
    term: Term<'a>,
) -> Result<NameLookupResult, String> {
    // Check for :undefined atom
    if let Ok(atom) = term.decode::<rustler::types::atom::Atom>() {
        let atom_str = atom
            .to_term(env)
            .atom_to_string()
            .map_err(|_| "failed to decode atom".to_string())?;
        if atom_str == "undefined" {
            return Ok(NameLookupResult::Undefined);
        }
        return Err(format!("unexpected atom: {atom_str}"));
    }

    // Check for {:value, name} tuple
    let elements = rustler::types::tuple::get_tuple(term)
        .map_err(|_| "name lookup result must be :undefined or {:value, name}".to_string())?;
    if elements.len() != 2 {
        return Err("name lookup result tuple must have 2 elements".to_string());
    }

    let tag: rustler::types::atom::Atom = elements[0]
        .decode()
        .map_err(|_| "first element must be an atom".to_string())?;
    let tag_str = tag
        .to_term(env)
        .atom_to_string()
        .map_err(|_| "failed to decode atom".to_string())?;
    if tag_str != "value" {
        return Err(format!("unexpected tag: {tag_str}"));
    }

    let name: String = elements[1]
        .decode()
        .map_err(|_| "name must be a string".to_string())?;

    Ok(NameLookupResult::Value(MontyObject::Function {
        name,
        docstring: None,
    }))
}

/// Decode an Elixir term into an `ExtFunctionResult`.
///
/// - `{:return, value}` → `ExtFunctionResult::Return(monty_object)`
/// - `{:error, %{type: string, message: string}}` → `ExtFunctionResult::Error(exception)`
/// - `{:not_found, name}` → `ExtFunctionResult::NotFound(name)`
pub fn decode_function_call_result<'a>(
    env: Env<'a>,
    term: Term<'a>,
) -> Result<ExtFunctionResult, String> {
    let elements = rustler::types::tuple::get_tuple(term)
        .map_err(|_| "function call result must be a tuple".to_string())?;
    if elements.len() != 2 {
        return Err("function call result tuple must have 2 elements".to_string());
    }

    let tag: rustler::types::atom::Atom = elements[0]
        .decode()
        .map_err(|_| "first element must be an atom".to_string())?;
    let tag_str = tag
        .to_term(env)
        .atom_to_string()
        .map_err(|_| "failed to decode tag atom".to_string())?;

    match tag_str.as_str() {
        "return" => {
            let obj = convert::term_to_monty(env, elements[1])?;
            Ok(ExtFunctionResult::Return(obj))
        }
        "error" => {
            let exc = error::make_exception(env, elements[1])?;
            Ok(ExtFunctionResult::Error(exc))
        }
        "not_found" => {
            let name: String = elements[1]
                .decode()
                .map_err(|_| "not_found name must be a string".to_string())?;
            Ok(ExtFunctionResult::NotFound(name))
        }
        other => Err(format!("unexpected function call result tag: {other}")),
    }
}
