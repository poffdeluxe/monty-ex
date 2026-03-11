use monty::ResourceLimits;
use rustler::{Encoder, Env, MapIterator, Term};
use std::time::Duration;

mod atoms {
    rustler::atoms! {
        max_allocations,
        max_duration_ms,
        max_memory,
        gc_interval,
        max_recursion_depth,
    }
}

/// Decode an Elixir map into monty ResourceLimits.
///
/// Expects a map with optional keys: max_allocations, max_duration_ms, max_memory,
/// gc_interval, max_recursion_depth. Missing or nil keys use defaults.
pub fn decode_limits<'a>(env: Env<'a>, term: Term<'a>) -> Result<ResourceLimits, String> {
    let mut limits = ResourceLimits::new();

    let iter = match MapIterator::new(term) {
        Some(iter) => iter,
        None => return Ok(limits), // empty or not a map → use defaults
    };

    for (key, value) in iter {
        if value == rustler::types::atom::nil().encode(env) {
            continue;
        }

        let key_atom = key
            .decode::<rustler::types::atom::Atom>()
            .map_err(|_| "limit keys must be atoms".to_string())?;

        if key_atom == atoms::max_allocations() {
            let v: u64 = value
                .decode()
                .map_err(|_| "max_allocations must be an integer".to_string())?;
            limits = limits.max_allocations(v as usize);
        } else if key_atom == atoms::max_duration_ms() {
            let v: u64 = value
                .decode()
                .map_err(|_| "max_duration_ms must be an integer".to_string())?;
            limits = limits.max_duration(Duration::from_millis(v));
        } else if key_atom == atoms::max_memory() {
            let v: u64 = value
                .decode()
                .map_err(|_| "max_memory must be an integer".to_string())?;
            limits = limits.max_memory(v as usize);
        } else if key_atom == atoms::gc_interval() {
            let v: u64 = value
                .decode()
                .map_err(|_| "gc_interval must be an integer".to_string())?;
            limits = limits.gc_interval(v as usize);
        } else if key_atom == atoms::max_recursion_depth() {
            let v: u64 = value
                .decode()
                .map_err(|_| "max_recursion_depth must be an integer".to_string())?;
            limits = limits.max_recursion_depth(Some(v as usize));
        }
    }

    Ok(limits)
}
