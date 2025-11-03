import gleam/list
import gleam/option.{type Option, None, Some}

pub type MutableDict(k, v)

//

@external(javascript, "./mutable_dict.ffi.mjs", "make")
pub fn new() -> MutableDict(k, v)

pub fn from_list(entries: List(#(k, v))) -> MutableDict(k, v) {
  use dict, #(key, value) <- list.fold(entries, new())

  insert(dict, key, value)
}

//

@external(javascript, "./mutable_dict.ffi.mjs", "get")
pub fn get(dict: MutableDict(k, v), key: k) -> Result(v, Nil)

@external(javascript, "./mutable_dict.ffi.mjs", "has_key")
pub fn has_key(dict: MutableDict(k, v), key: k) -> Bool

//

@external(javascript, "./mutable_dict.ffi.mjs", "insert")
pub fn insert(dict: MutableDict(k, v), key: k, value: v) -> MutableDict(k, v)

pub fn upsert(
  dict: MutableDict(k, v),
  key: k,
  f: fn(Option(v)) -> v,
) -> MutableDict(k, v) {
  let current_value = case get(dict, key) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }

  let new_value = f(current_value)

  insert(dict, key, new_value)
}

@external(javascript, "./mutable_dict.ffi.mjs", "remove")
pub fn delete(dict: MutableDict(k, v), key: k) -> MutableDict(k, v)

//

@external(javascript, "./mutable_dict.ffi.mjs", "keys")
pub fn keys(dict: MutableDict(k, v)) -> List(k)

@external(javascript, "./mutable_dict.ffi.mjs", "values")
pub fn values(dict: MutableDict(k, v)) -> List(v)

@external(javascript, "./mutable_dict.ffi.mjs", "to_list")
pub fn to_list(dict: MutableDict(k, v)) -> List(#(k, v))

pub fn fold(dict: MutableDict(k, v), init: a, f: fn(a, k, v) -> a) -> a {
  use acc, #(key, value) <- list.fold(to_list(dict), init)

  f(acc, key, value)
}
