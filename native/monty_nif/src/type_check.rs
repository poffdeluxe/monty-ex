use monty_type_checking::SourceFile;
use rustler::{Atom, Encoder, Env, NifResult, Term};

mod atoms {
    rustler::atoms! {
        ok,
        error,
        no_errors,
        nil,
        diagnostics,

        // format atoms
        full,
        concise,
        json,
        pylint,
        gitlab,
        github,
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn type_check<'a>(
    env: Env<'a>,
    code: String,
    stubs: Term<'a>,
    format: Term<'a>,
    script_name: String,
) -> NifResult<Term<'a>> {
    type_check_inner(env, code, stubs, format, script_name)
        .map_err(|msg| rustler::Error::RaiseTerm(Box::new(msg)))
}

fn type_check_inner<'a>(
    env: Env<'a>,
    code: String,
    stubs_term: Term<'a>,
    format_term: Term<'a>,
    script_name: String,
) -> Result<Term<'a>, String> {
    let source = SourceFile {
        source_code: &code,
        path: &script_name,
    };

    let format_atom: Atom = format_term
        .decode()
        .map_err(|_| "format must be an atom".to_string())?;

    let format_str = if format_atom == atoms::full() {
        "full"
    } else if format_atom == atoms::concise() {
        "concise"
    } else if format_atom == atoms::json() {
        "json"
    } else if format_atom == atoms::pylint() {
        "pylint"
    } else if format_atom == atoms::gitlab() {
        "gitlab"
    } else if format_atom == atoms::github() {
        "github"
    } else {
        return Err("format must be one of: :full, :concise, :json, :pylint, :gitlab, :github".to_string());
    };

    let stubs_string: Option<String> = if stubs_term.is_atom() {
        let atom: Atom = stubs_term.decode().map_err(|_| "invalid stubs term".to_string())?;
        if atom == atoms::nil() {
            None
        } else {
            return Err("stubs must be a string or nil".to_string());
        }
    } else {
        Some(stubs_term.decode().map_err(|_| "stubs must be a string or nil".to_string())?)
    };

    let stubs_source = stubs_string.as_ref().map(|s| SourceFile {
        source_code: s.as_str(),
        path: "stubs.pyi",
    });

    let result = monty_type_checking::type_check(&source, stubs_source.as_ref())
        .map_err(|e| e.to_string())?;

    match result {
        None => Ok((atoms::ok(), atoms::no_errors()).encode(env)),
        Some(diags) => {
            let formatted = diags
                .format_from_str(format_str)
                .map_err(|e| e.to_string())?
                .color(false)
                .to_string();

            let map = Term::map_new(env);
            let map = map
                .map_put(atoms::diagnostics().encode(env), formatted.encode(env))
                .map_err(|_| "failed to build diagnostics map".to_string())?;

            Ok((atoms::error(), map).encode(env))
        }
    }
}
