// IMPORTS ---------------------------------------------------------------------

import gleam/float
import gleam/int

// CONSTRUCTORS ----------------------------------------------------------------

pub fn parse(value: String) {
  case int.parse(value) {
    Ok(n) -> Ok(int.to_float(n))
    Error(_) -> float.parse(value)
  }
}
