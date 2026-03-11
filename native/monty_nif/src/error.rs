use monty::MontyException;
use rustler::{Encoder, Env, Term};

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
