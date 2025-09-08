import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/result

// TYPES -----------------------------------------------------------------------

pub type Handles

pub fn new() -> Handles {
  unsafe_from_dynamic(dynamic.nil())
}

pub fn get(
  handles: Handles,
  node: String,
  handle: String,
) -> Result(#(Float, Float), Nil) {
  let position = {
    use x <- decode.field(0, decode.float)
    use y <- decode.field(1, decode.float)

    decode.success(#(x, y))
  }

  to_dynamic(handles)
  |> decode.run(decode.at([node, handle], position))
  |> result.replace_error(Nil)
}

@external(javascript, "../../../gleam_stdlib/gleam/function.mjs", "identity")
fn to_dynamic(handles: Handles) -> Dynamic

@external(javascript, "../../../gleam_stdlib/gleam/function.mjs", "identity")
pub fn unsafe_from_dynamic(dynamic: Dynamic) -> Handles
