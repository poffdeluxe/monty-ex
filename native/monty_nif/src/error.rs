use std::str::FromStr;

use monty::MontyException;
use rustler::{Encoder, Env, MapIterator, Term};

mod atoms {
    rustler::atoms! {
        kind,
        syntax,
        runtime,
        type_ = "type",
        message,
        traceback,
        filename,
        line,
        column,
        function_name,
        source_line,
    }
}

/// Convert a MontyException into an Elixir error map.
///
/// Returns: `%{kind: :syntax | :runtime, type: String, message: String, traceback: [map]}`
pub fn exception_to_term<'a>(env: Env<'a>, exc: MontyException) -> Result<Term<'a>, String> {
    let exc_type = exc.exc_type();
    let is_syntax = exc_type == monty::ExcType::SyntaxError;

    let kind_val = if is_syntax {
        atoms::syntax().encode(env)
    } else {
        atoms::runtime().encode(env)
    };

    // Use strum's Into<&'static str> impl for ExcType to get the type name string
    let type_str: &'static str = exc_type.into();

    let message_val = match exc.message() {
        Some(msg) => msg.to_string().encode(env),
        None => "".encode(env),
    };

    // Build traceback entries
    let traceback_entries: Vec<Term> = exc
        .traceback()
        .iter()
        .map(|frame| {
            let mut map = Term::map_new(env);
            map = map
                .map_put(
                    atoms::filename().encode(env),
                    frame.filename.encode(env),
                )
                .map_err(|_| "failed to build traceback frame".to_string())?;
            map = map
                .map_put(
                    atoms::line().encode(env),
                    (frame.start.line as i64).encode(env),
                )
                .map_err(|_| "failed to build traceback frame".to_string())?;
            map = map
                .map_put(
                    atoms::column().encode(env),
                    (frame.start.column as i64).encode(env),
                )
                .map_err(|_| "failed to build traceback frame".to_string())?;
            map = map
                .map_put(
                    atoms::function_name().encode(env),
                    match &frame.frame_name {
                        Some(name) => name.encode(env),
                        None => rustler::types::atom::nil().encode(env),
                    },
                )
                .map_err(|_| "failed to build traceback frame".to_string())?;
            map = map
                .map_put(
                    atoms::source_line().encode(env),
                    match &frame.preview_line {
                        Some(line) => line.encode(env),
                        None => rustler::types::atom::nil().encode(env),
                    },
                )
                .map_err(|_| "failed to build traceback frame".to_string())?;
            Ok(map)
        })
        .collect::<Result<_, String>>()?;

    let mut map = Term::map_new(env);
    map = map
        .map_put(atoms::kind().encode(env), kind_val)
        .map_err(|_| "failed to build error map".to_string())?;
    map = map
        .map_put(atoms::type_().encode(env), type_str.encode(env))
        .map_err(|_| "failed to build error map".to_string())?;
    map = map
        .map_put(atoms::message().encode(env), message_val)
        .map_err(|_| "failed to build error map".to_string())?;
    map = map
        .map_put(
            atoms::traceback().encode(env),
            traceback_entries.encode(env),
        )
        .map_err(|_| "failed to build error map".to_string())?;
    Ok(map)
}

/// Build a `MontyException` from an Elixir error map `%{type: String, message: String}`.
pub fn make_exception<'a>(env: Env<'a>, term: Term<'a>) -> Result<MontyException, String> {
    let iter =
        MapIterator::new(term).ok_or_else(|| "error info must be a map".to_string())?;

    let mut type_str: Option<String> = None;
    let mut message_str: Option<String> = None;

    for (key, value) in iter {
        let key_atom = key
            .decode::<rustler::types::atom::Atom>()
            .map_err(|_| "error map keys must be atoms".to_string())?;
        let key_name = key_atom
            .to_term(env)
            .atom_to_string()
            .map_err(|_| "failed to decode atom name".to_string())?;

        match key_name.as_str() {
            "type" => {
                type_str = Some(
                    value
                        .decode::<String>()
                        .map_err(|_| "type must be a string".to_string())?,
                );
            }
            "message" => {
                message_str = Some(
                    value
                        .decode::<String>()
                        .map_err(|_| "message must be a string".to_string())?,
                );
            }
            _ => {}
        }
    }

    let type_name = type_str.unwrap_or_else(|| "RuntimeError".to_string());
    let exc_type =
        monty::ExcType::from_str(&type_name).unwrap_or(monty::ExcType::RuntimeError);

    Ok(MontyException::new(exc_type, message_str))
}
