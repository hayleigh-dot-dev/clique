// IMPORTS ---------------------------------------------------------------------

import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre
import lustre/attribute.{type Attribute, attribute}
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element, element}
import lustre/element/html
import lustre/event

// COMPONENT -------------------------------------------------------------------

pub const tag: String = "clique-edge"

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

///
///
pub fn from(node: String, handle: String) -> Attribute(msg) {
  attribute("from", node <> "." <> handle)
}

///
///
pub fn to(node: String, handle: String) -> Attribute(msg) {
  attribute("to", node <> "." <> handle)
}

///
///
pub fn bezier() -> Attribute(msg) {
  attribute("type", "bezier")
}

///
///
pub fn linear() -> Attribute(msg) {
  attribute("type", "linear")
}

///
///
pub fn step() -> Attribute(msg) {
  attribute("type", "step")
}

///
///
// pub fn custom(value: String) -> Attribute(msg) {
//   attribute("type", value)
// }

// EVENTS ----------------------------------------------------------------------

pub fn on_disconnect(handler: fn(String, String) -> msg) -> Attribute(msg) {
  event.on("clique:disconnect", {
    use from <- decode.subfield(["detail", "from"], decode.string)
    use to <- decode.subfield(["detail", "to"], decode.string)

    decode.success(handler(from, to))
  })
}

fn emit_disconnect(from: String, to: String) -> Effect(msg) {
  event.emit("clique:disconnect", {
    json.object([
      #("from", json.string(from)),
      #("to", json.string(to)),
    ])
  })
}

pub fn on_reconnect(
  handler: fn(#(String, String), #(String, String), String) -> msg,
) -> Attribute(msg) {
  event.on("clique:reconnect", {
    use old <- decode.subfield(["detail", "old"], {
      use from <- decode.field("from", decode.string)
      use to <- decode.field("to", decode.string)

      decode.success(#(from, to))
    })

    use new <- decode.subfield(["detail", "new"], {
      use from <- decode.field("from", decode.string)
      use to <- decode.field("to", decode.string)

      decode.success(#(from, to))
    })

    use kind <- decode.subfield(["detail", "type"], decode.string)

    decode.success(handler(old, new, kind))
  })
}

fn emit_reconnect(
  old: #(String, String),
  new: #(String, String),
  new_kind: String,
) -> Effect(msg) {
  event.emit("clique:reconnect", {
    json.object([
      #(
        "old",
        json.object([#("from", json.string(old.0)), #("to", json.string(old.1))]),
      ),
      #(
        "new",
        json.object([#("from", json.string(new.0)), #("to", json.string(new.1))]),
      ),
      #("type", json.string(new_kind)),
    ])
  })
}

pub fn on_connect(handler: fn(String, String, String) -> msg) -> Attribute(msg) {
  event.on("clique:connect", {
    use from <- decode.subfield(["detail", "from"], decode.string)
    use to <- decode.subfield(["detail", "to"], decode.string)
    use kind <- decode.subfield(["detail", "type"], decode.string)

    decode.success(handler(from, to, kind))
  })
}

fn emit_connect(from: String, to: String, kind: String) -> Effect(msg) {
  event.emit("clique:connect", {
    json.object([
      #("from", json.string(from)),
      #("to", json.string(to)),
      #("type", json.string(kind)),
    ])
  })
}

fn emit_change(
  old_from: Option(String),
  old_to: Option(String),
  new_from: Option(String),
  new_to: Option(String),
  kind: String,
) -> Effect(msg) {
  let new_kind = case kind {
    "" -> "bezier"
    k -> k
  }

  case old_from, old_to, new_from, new_to {
    Some(old_from), Some(old_to), Some(new_from), Some(new_to) ->
      emit_reconnect(#(old_from, old_to), #(new_from, new_to), new_kind)

    Some(old_from), Some(old_to), _, _ -> emit_disconnect(old_from, old_to)

    _, _, Some(new_from), Some(new_to) ->
      emit_connect(new_from, new_to, new_kind)

    _, _, _, _ -> effect.none()
  }
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(from: Option(String), to: Option(String), kind: String)
}

fn init(_) -> #(Model, Effect(Msg)) {
  let model = Model(from: None, to: None, kind: "bezier")
  let effect = effect.none()

  #(model, effect)
}

fn options() -> List(component.Option(Msg)) {
  [
    //
    //
    component.adopt_styles(False),

    //
    //
    component.on_attribute_change("from", fn(value) {
      case string.split(value, ".") {
        [node, handle] if node != "" && handle != "" ->
          Ok(ParentSetFrom(value:))
        _ -> Ok(ParentRemovedFrom)
      }
    }),

    //
    //
    component.on_attribute_change("to", fn(value) {
      case string.split(value, ".") {
        [node, handle] if node != "" && handle != "" -> Ok(ParentSetTo(value:))
        _ -> Ok(ParentRemovedTo)
      }
    }),

    //
    //
    component.on_attribute_change("type", fn(value) {
      case value {
        "" -> Ok(ParentSetType(value: "bezier"))
        _ -> Ok(ParentSetType(value:))
      }
    }),
  ]
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  ParentRemovedFrom
  ParentRemovedTo
  ParentSetFrom(value: String)
  ParentSetTo(value: String)
  ParentSetType(value: String)
}

fn update(prev: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ParentRemovedFrom -> {
      let next = Model(..prev, from: None)
      let effect =
        emit_change(prev.from, prev.to, next.from, next.to, next.kind)

      #(next, effect)
    }

    ParentRemovedTo -> {
      let next = Model(..prev, to: None)
      let effect =
        emit_change(prev.from, prev.to, next.from, next.to, next.kind)

      #(next, effect)
    }

    ParentSetFrom(value) -> {
      let next = Model(..prev, from: Some(value))
      let effect =
        emit_change(prev.from, prev.to, next.from, next.to, next.kind)

      #(next, effect)
    }

    ParentSetTo(value) -> {
      let next = Model(..prev, to: Some(value))
      let effect =
        emit_change(prev.from, prev.to, next.from, next.to, next.kind)

      #(next, effect)
    }

    ParentSetType(value) -> {
      let next = Model(..prev, kind: value)
      let effect =
        emit_change(prev.from, prev.to, next.from, next.to, next.kind)

      #(next, effect)
    }
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  element.fragment([
    html.style([], {
      ":host {
        display: contents;
      }

      slot {
        display: inline-block;
        position: absolute;
        transform-origin: center;
        will-change: transform;
        pointer-events: auto;
      }
      "
    }),

    case model.from, model.to {
      Some(_), Some(_) -> {
        let translate_x = "var(--cx)"
        let translate_y = "var(--cy)"
        let transform =
          "translate("
          <> translate_x
          <> ", "
          <> translate_y
          <> ") translate(-50%, -50%)"

        component.default_slot([attribute.style("transform", transform)], [])
      }
      _, _ -> element.none()
    },
  ])
}
