// IMPORTS ---------------------------------------------------------------------

import clique/internal/context
import clique/internal/dom
import clique/node
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

pub const tag: String = "clique-handle"

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

pub type Placement {
  Top
  Right
  Bottom
  Left
}

pub fn placement(value: Placement) -> Attribute(msg) {
  case value {
    Top -> attribute("placement", "top")
    Right -> attribute("placement", "right")
    Bottom -> attribute("placement", "bottom")
    Left -> attribute("placement", "left")
  }
}

// EVENTS ----------------------------------------------------------------------

pub fn on_connection_start(handler: fn(String, String) -> msg) -> Attribute(msg) {
  event.on("clique:connection-start", {
    use node <- decode.subfield(["detail", "node"], decode.string)
    use handle <- decode.subfield(["detail", "handle"], decode.string)

    decode.success(handler(node, handle))
  })
}

fn emit_connection_start(node: String, handle: String) -> Effect(msg) {
  event.emit("clique:connection-start", {
    json.object([
      #("node", json.string(node)),
      #("handle", json.string(handle)),
    ])
  })
}

pub fn on_connection_cancel(handler: msg) -> Attribute(msg) {
  event.on("clique:connection-cancel", decode.success(handler))
}

pub fn on_connection_complete(
  handler: fn(#(String, String), #(String, String)) -> msg,
) -> Attribute(msg) {
  let handle_decoder = {
    use node <- decode.field("node", decode.string)
    use handle <- decode.field("handle", decode.string)

    decode.success(#(node, handle))
  }

  event.on("clique:connection-complete", {
    use from <- decode.subfield(["detail", "from"], handle_decoder)
    use to <- decode.subfield(["detail", "to"], handle_decoder)

    decode.success(handler(from, to))
  })
}

fn emit_connection_complete(
  from: #(String, String),
  to: #(String, String),
) -> Effect(msg) {
  event.emit("clique:connection-complete", {
    json.object([
      #("from", {
        json.object([
          #("node", json.string(from.0)),
          #("handle", json.string(from.1)),
        ])
      }),

      #("to", {
        json.object([
          #("node", json.string(to.0)),
          #("handle", json.string(to.1)),
        ])
      }),
    ])
  })
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(
    node: String,
    name: String,
    disabled: Bool,
    connection: Option(#(String, String)),
  )
}

fn init(_) -> #(Model, Effect(Msg)) {
  let model = Model(node: "", name: "", disabled: False, connection: None)
  let effect =
    effect.batch([
      dom.add_event_listener("mousedown", {
        decode.success(event.handler(UserStartedConnection, False, True))
      }),

      dom.add_event_listener("mouseup", {
        decode.success(event.handler(UserCompletedConnection, False, False))
      }),

      component.set_pseudo_state("invalid"),
    ])

  #(model, effect)
}

fn options() -> List(component.Option(Msg)) {
  [
    component.adopt_styles(False),

    component.on_attribute_change("disabled", fn(value) {
      case string.trim(value) {
        "" -> Ok(ParentToggledDisabled)
        _ -> Ok(ParentSetDisabled)
      }
    }),

    component.on_attribute_change("name", fn(value) {
      Ok(ParentSetName(value: string.trim(value)))
    }),

    node.on_context_change(NodeProvidedContext),
    context.on_connection_change(ViewportProvidedConnection),
  ]
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  NodeProvidedContext(id: String)
  ParentSetDisabled
  ParentSetName(value: String)
  ParentToggledDisabled
  UserStartedConnection
  UserCompletedConnection
  ViewportProvidedConnection(connection: Option(#(String, String)))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    NodeProvidedContext(id:) -> {
      let model = Model(..model, node: id)
      let effect = case model.node, model.name {
        "", _ | _, "" -> component.set_pseudo_state("invalid")
        _, _ -> component.remove_pseudo_state("invalid")
      }

      #(model, effect)
    }

    ParentSetDisabled -> {
      let model = Model(..model, disabled: True)
      let effect = component.set_pseudo_state("disabled")

      #(model, effect)
    }

    ParentSetName(value:) -> {
      let model = Model(..model, name: value)
      let effect = case model.node, model.name {
        "", _ | _, "" -> component.set_pseudo_state("invalid")
        _, _ -> component.remove_pseudo_state("invalid")
      }

      #(model, effect)
    }

    ParentToggledDisabled -> {
      let model = Model(..model, disabled: !model.disabled)
      let effect = case model.disabled {
        True -> component.set_pseudo_state("disabled")
        False -> component.remove_pseudo_state("disabled")
      }

      #(model, effect)
    }

    UserCompletedConnection ->
      case model.disabled, model.node, model.name, model.connection {
        True, _, _, _ | _, "", _, _ | _, _, "", _ | _, _, _, None -> #(
          model,
          effect.none(),
        )

        _, node, name, Some(from) -> #(
          model,
          emit_connection_complete(from, #(node, name)),
        )
      }

    UserStartedConnection ->
      case model.disabled, model.node, model.name {
        True, _, _ | _, "", _ | _, _, "" -> #(model, effect.none())
        _, node, name -> #(model, emit_connection_start(node, name))
      }

    ViewportProvidedConnection(connection:) -> {
      let model = Model(..model, connection: connection)
      let effect = effect.none()

      #(model, effect)
    }
  }
}

// VIEW ------------------------------------------------------------------------

fn view(_) -> Element(Msg) {
  element.fragment([
    html.style([], {
      "
      :host(:state(disabled)), :host(:state(invalid)) {
        pointer-events: none;
      }
      "
    }),
    component.default_slot([], []),
  ])
}
