// IMPORTS ---------------------------------------------------------------------

import clique/internal/mutable_dict.{type MutableDict}
import clique/node
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/function
import gleam/json
import lustre
import lustre/attribute.{type Attribute}
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element, element}
import lustre/element/html
import lustre/event

// COMPONENT -------------------------------------------------------------------

pub const tag: String = "clique-node-group"

///
///
pub fn register() -> Result(Nil, lustre.Error) {
  lustre.register(
    lustre.component(init:, update:, view:, options: options()),
    tag,
  )
}

// ELEMENTS --------------------------------------------------------------------

///
///
pub fn root(
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  element(tag, attributes, children)
}

// ATTRIBUTES ------------------------------------------------------------------

// EVENTS ----------------------------------------------------------------------

pub fn on_changes(
  handler: fn(Dict(String, #(Float, Float))) -> msg,
) -> Attribute(msg) {
  event.on("clique:changes", {
    use changes <- decode.subfield(
      ["detail", "changes"],
      decode.dict(decode.string, {
        use dx <- decode.field("dx", decode.float)
        use dy <- decode.field("dy", decode.float)

        decode.success(#(dx, dy))
      }),
    )

    decode.success(handler(changes))
  })
}

fn emit_changes(changes: MutableDict(String, #(Float, Float))) -> Effect(msg) {
  event.emit(
    "clique:changes",
    json.object([
      #("changes", {
        mutable_dict.to_json(changes, function.identity, fn(change) {
          let #(dx, dy) = change

          json.object([
            #("dx", json.float(dx)),
            #("dy", json.float(dy)),
          ])
        })
      }),
    ]),
  )
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(should_accumulate: Bool, changes: MutableDict(String, #(Float, Float)))
}

fn init(_) -> #(Model, Effect(Msg)) {
  let model = Model(should_accumulate: False, changes: mutable_dict.new())
  let effect = effect.none()

  #(model, effect)
}

fn options() -> List(component.Option(Msg)) {
  []
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  MicrotaskTick
  NodeChanged(id: String, dx: Float, dy: Float)
  NodesChanged(changes: Dict(String, #(Float, Float)))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    MicrotaskTick -> {
      let next = Model(should_accumulate: False, changes: mutable_dict.new())
      let effect = emit_changes(model.changes)

      #(next, effect)
    }

    NodeChanged(id:, dx:, dy:) if model.should_accumulate -> {
      let changes = mutable_dict.insert(model.changes, id, #(dx, dy))
      let model = Model(..model, changes:)

      #(model, effect.none())
    }

    NodeChanged(id:, dx:, dy:) -> {
      let changes = mutable_dict.insert(model.changes, id, #(dx, dy))
      let model = Model(changes:, should_accumulate: True)
      let effect = queue_microtask()

      #(model, effect)
    }

    NodesChanged(changes:) if model.should_accumulate -> {
      let changes = dict.fold(changes, model.changes, mutable_dict.insert)
      let model = Model(..model, changes: changes)

      #(model, effect.none())
    }

    NodesChanged(changes:) -> {
      let changes = dict.fold(changes, model.changes, mutable_dict.insert)
      let model = Model(changes:, should_accumulate: True)
      let effect = queue_microtask()

      #(model, effect)
    }
  }
}

fn queue_microtask() -> Effect(Msg) {
  use dispatch <- effect.from
  use <- do_queue_microtask

  dispatch(MicrotaskTick)
}

@external(javascript, "./node_group.ffi.mjs", "queue_microtask")
fn do_queue_microtask(callback: fn() -> Nil) -> Nil

// VIEW ------------------------------------------------------------------------

fn view(_) -> Element(Msg) {
  html.slot([node.on_change(NodeChanged), on_changes(NodesChanged)], [])
}
