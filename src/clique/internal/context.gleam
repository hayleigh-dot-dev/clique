// IMPORTS ---------------------------------------------------------------------

import clique/transform.{type Transform}
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/option
import lustre/component.{type Option}
import lustre/effect.{type Effect}

// SCALE CONTEXT ---------------------------------------------------------------

pub fn provide_scale(value: Float) -> Effect(msg) {
  effect.provide("clique/scale", json.float(value))
}

pub fn on_scale_change(handler: fn(Float) -> msg) -> Option(msg) {
  component.on_context_change("clique/scale", {
    use scale <- decode.then(decode.float)

    decode.success(handler(scale))
  })
}

// TRANSFORM CONTEXT -----------------------------------------------------------

pub fn provide_transform(value: Transform) -> Effect(msg) {
  effect.provide("clique/transform", transform.to_json(value))
}

pub fn on_transform_change(handler: fn(Transform) -> msg) -> Option(msg) {
  component.on_context_change("clique/transform", {
    use transform <- decode.then(transform.decoder())

    decode.success(handler(transform))
  })
}

// CONNECTION CONTEXT ----------------------------------------------------------

pub fn provide_connection(
  value: option.Option(#(String, String)),
) -> Effect(msg) {
  effect.provide("clique/connection", {
    case value {
      option.Some(#(node, handle)) ->
        json.object([
          #("node", json.string(node)),
          #("handle", json.string(handle)),
        ])

      option.None -> json.null()
    }
  })
}

pub fn on_connection_change(
  handler: fn(option.Option(#(String, String))) -> msg,
) -> Option(msg) {
  component.on_context_change("clique/connection", {
    use connection <- decode.then(
      decode.optional({
        use node <- decode.field("node", decode.string)
        use handle <- decode.field("handle", decode.string)

        decode.success(#(node, handle))
      }),
    )

    decode.success(handler(connection))
  })
}

// HANDLES CONTEXT -------------------------------------------------------------

pub fn provide_handles(
  handles: Dict(String, Dict(String, #(Float, Float))),
) -> Effect(msg) {
  effect.provide("clique/handles", {
    json.object({
      use fields, node, handles <- dict.fold(handles, [])
      use fields, handle, position <- dict.fold(handles, fields)
      let field = #(node <> "." <> handle, {
        json.preprocessed_array([json.float(position.0), json.float(position.1)])
      })

      [field, ..fields]
    })
  })
}

pub fn on_handles_change(
  handler: fn(Dict(String, #(Float, Float))) -> msg,
) -> Option(msg) {
  component.on_context_change("clique/handles", {
    use raw_handles <- decode.then(
      decode.dict(decode.string, {
        use x <- decode.field(0, decode.float)
        use y <- decode.field(1, decode.float)

        decode.success(#(x, y))
      }),
    )

    decode.success(handler(raw_handles))
  })
}
