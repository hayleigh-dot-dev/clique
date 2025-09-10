// IMPORTS ---------------------------------------------------------------------

import clique/internal/dom.{type HtmlElement}
import gleam/bool
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None}
import gleam/result
import gleam/string
import lustre/attribute.{type Attribute}
import lustre/effect.{type Effect}
import lustre/event

// NODE EVENTS -----------------------------------------------------------------

pub fn emit_node_mount() -> Effect(msg) {
  event.emit("clique:node-mount", json.null())
}

pub fn on_node_mount(handler: fn(String, HtmlElement) -> msg) -> Attribute(msg) {
  event.on("clique:node-mount", {
    use target <- decode.field("target", dom.element_decoder())
    use id <- decode.subfield(["target", "id"], decode.string)

    decode.success(handler(id, target))
  })
}

pub fn emit_node_drag(
  x x: Float,
  y y: Float,
  dx dx: Float,
  dy dy: Float,
) -> Effect(msg) {
  event.emit(
    "clique:node-drag",
    json.object([
      #("x", json.float(x)),
      #("y", json.float(y)),
      #("dx", json.float(dx)),
      #("dy", json.float(dy)),
    ]),
  )
}

pub fn on_node_drag(
  handler: fn(String, Float, Float, Float, Float) -> msg,
) -> Attribute(msg) {
  event.on("clique:node-drag", {
    use id <- decode.subfield(["target", "id"], decode.string)
    use x <- decode.subfield(["detail", "x"], decode.float)
    use y <- decode.subfield(["detail", "y"], decode.float)
    use dx <- decode.subfield(["detail", "dx"], decode.float)
    use dy <- decode.subfield(["detail", "dy"], decode.float)

    decode.success(handler(id, x, y, dx, dy))
  })
}

// EDGE EVENTS -----------------------------------------------------------------

pub fn emit_edge_change(
  prev: Option(#(String, String)),
  next: Option(#(String, String, String)),
) -> Effect(msg) {
  use <- bool.guard(prev == None && next == None, effect.none())

  event.emit(
    "clique:edge-change",
    json.object([
      #("prev", {
        json.nullable(prev, fn(prev) {
          json.object([
            #("from", json.string(prev.0)),
            #("to", json.string(prev.1)),
          ])
        })
      }),
      #("next", {
        json.nullable(next, fn(next) {
          json.object([
            #("from", json.string(next.0)),
            #("to", json.string(next.1)),
            #("kind", json.string(next.2)),
          ])
        })
      }),
    ]),
  )
}

pub fn on_edge_change(
  handler: fn(Option(#(String, String)), Option(#(String, String, String))) ->
    msg,
) -> Attribute(msg) {
  event.on("clique:edge-change", {
    use prev <- decode.field("prev", {
      decode.optional({
        use from <- decode.field("from", decode.string)
        use to <- decode.field("to", decode.string)

        decode.success(#(from, to))
      })
    })

    use next <- decode.field("next", {
      decode.optional({
        use from <- decode.field("from", decode.string)
        use to <- decode.field("to", decode.string)
        use kind <- decode.field("kind", decode.string)

        decode.success(#(from, to, kind))
      })
    })

    decode.success(handler(prev, next))
  })
}

pub fn on_edges_mount(
  handler: fn(List(#(String, String, String))) -> msg,
) -> Attribute(msg) {
  event.on("slotchange", {
    use target <- decode.field("target", dom.element_decoder())
    let assigned_elements = dom.assigned_elements(target)
    let edges =
      list.filter_map(assigned_elements, fn(element) {
        use from <- result.try(dom.attribute(element, "from"))
        use to <- result.try(dom.attribute(element, "to"))
        let kind = dom.attribute(element, "type") |> result.unwrap("bezier")

        case string.split(from, "."), string.split(to, ".") {
          [from_node, from_handle], [to_node, to_handle]
            if from_node != ""
            && from_handle != ""
            && to_node != ""
            && to_handle != ""
          -> Ok(#(from, to, kind))
          _, _ -> Error(Nil)
        }
      })

    decode.success(handler(edges))
  })
}
