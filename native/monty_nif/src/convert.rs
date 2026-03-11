use monty::MontyObject;
use rustler::{Encoder, Env, MapIterator, Term, TermType};

/// Convert a MontyObject to an Elixir Term.
pub fn monty_to_term<'a>(env: Env<'a>, obj: MontyObject) -> Result<Term<'a>, String> {
    match obj {
        MontyObject::None => Ok(rustler::types::atom::nil().encode(env)),
        MontyObject::Bool(b) => Ok(b.encode(env)),
        MontyObject::Int(i) => Ok(i.encode(env)),
        MontyObject::BigInt(bi) => Ok(bi.encode(env)),
        MontyObject::Float(f) => Ok(f.encode(env)),
        MontyObject::String(s) => Ok(s.encode(env)),
        MontyObject::Bytes(b) => {
            let mut binary = rustler::NewBinary::new(env, b.len());
            binary.as_mut_slice().copy_from_slice(&b);
            Ok(binary.into())
        }
        MontyObject::List(items) => {
            let terms: Vec<Term> = items
                .into_iter()
                .map(|o| monty_to_term(env, o))
                .collect::<Result<_, _>>()?;
            Ok(terms.encode(env))
        }
        MontyObject::Tuple(items) => {
            let terms: Vec<Term> = items
                .into_iter()
                .map(|o| monty_to_term(env, o))
                .collect::<Result<_, _>>()?;
            Ok(rustler::types::tuple::make_tuple(env, &terms))
        }
        MontyObject::Dict(pairs) => {
            let mut map = Term::map_new(env);
            for (k, v) in pairs {
                let key_term = monty_to_term(env, k)?;
                let val_term = monty_to_term(env, v)?;
                map = map
                    .map_put(key_term, val_term)
                    .map_err(|_| "failed to insert entry into dict".to_string())?;
            }
            Ok(map)
        }
        MontyObject::Set(items) | MontyObject::FrozenSet(items) => {
            // Sets have no direct Elixir equivalent; converting to list
            let terms: Vec<Term> = items
                .into_iter()
                .map(|o| monty_to_term(env, o))
                .collect::<Result<_, _>>()?;
            Ok(terms.encode(env))
        }
        MontyObject::Ellipsis => Ok("...".encode(env)),
        MontyObject::Path(p) => Ok(p.encode(env)),
        MontyObject::Repr(s) => Ok(s.encode(env)),
        // All other types: debug string representation
        other => Ok(format!("{other:?}").encode(env)),
    }
}

/// Convert an Elixir Term to a MontyObject.
pub fn term_to_monty<'a>(env: Env<'a>, term: Term<'a>) -> Result<MontyObject, String> {
    match term.get_type() {
        TermType::Atom => {
            // Order matters: true/false are atoms in BEAM, so bool check must
            // precede generic atom-to-string conversion.
            if let Ok(b) = term.decode::<bool>() {
                return Ok(MontyObject::Bool(b));
            }
            // Check for nil
            if term == rustler::types::atom::nil().encode(env) {
                return Ok(MontyObject::None);
            }
            // Convert other atoms to strings (useful for map keys)
            if let Ok(atom) = term.decode::<rustler::types::atom::Atom>() {
                let name = atom.to_term(env).atom_to_string()
                    .map_err(|_| "failed to decode atom name".to_string())?;
                Ok(MontyObject::String(name))
            } else {
                Err("unsupported atom".to_string())
            }
        }
        TermType::Integer => {
            match term.decode::<i64>() {
                Ok(i) => Ok(MontyObject::Int(i)),
                Err(rustler::Error::BadArg) => {
                    let bi = term.decode::<rustler::BigInt>()
                        .map_err(|_| "failed to decode big integer".to_string())?;
                    Ok(MontyObject::BigInt(bi))
                }
                Err(e) => Err(format!("failed to decode integer: {e:?}"))
            }
        }
        TermType::Float => {
            let f: f64 = term.decode().map_err(|_| "failed to decode float".to_string())?;
            Ok(MontyObject::Float(f))
        }
        TermType::Binary => {
            let s: String =
                term.decode().map_err(|_| "failed to decode binary as UTF-8 string".to_string())?;
            Ok(MontyObject::String(s))
        }
        TermType::List => {
            let items: Vec<Term> =
                term.decode().map_err(|_| "failed to decode list".to_string())?;
            let monty_items: Vec<MontyObject> = items
                .into_iter()
                .map(|t| term_to_monty(env, t))
                .collect::<Result<_, _>>()?;
            Ok(MontyObject::List(monty_items))
        }
        TermType::Tuple => {
            let elements = rustler::types::tuple::get_tuple(term)
                .map_err(|_| "failed to decode tuple".to_string())?;
            let monty_items: Vec<MontyObject> = elements
                .into_iter()
                .map(|t| term_to_monty(env, t))
                .collect::<Result<_, _>>()?;
            Ok(MontyObject::Tuple(monty_items))
        }
        TermType::Map => {
            let iter = MapIterator::new(term)
                .ok_or_else(|| "failed to iterate map".to_string())?;
            let mut pairs = Vec::new();
            for (key, value) in iter {
                let monty_key = term_to_monty(env, key)?;
                let monty_value = term_to_monty(env, value)?;
                pairs.push((monty_key, monty_value));
            }
            Ok(MontyObject::Dict(pairs.into()))
        }
        other => Err(format!("unsupported term type: {other:?}")),
    }
}

/// Decode an Elixir map of `%{String.t() => term}` into ordered input names and values.
pub fn decode_inputs<'a>(
    env: Env<'a>,
    inputs: Term<'a>,
) -> Result<(Vec<String>, Vec<MontyObject>), String> {
    let iter =
        MapIterator::new(inputs).ok_or_else(|| "inputs must be a map".to_string())?;

    let mut names = Vec::new();
    let mut values = Vec::new();

    for (key, value) in iter {
        let name: String = key
            .decode()
            .map_err(|_| "input keys must be strings".to_string())?;
        let monty_value = term_to_monty(env, value)?;
        names.push(name);
        values.push(monty_value);
    }

    Ok((names, values))
}
