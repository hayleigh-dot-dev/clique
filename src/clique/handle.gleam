// IMPORTS ---------------------------------------------------------------------

import clique/internal/context
import clique/internal/dom
import clique/node
import clique/position.{type Position}
import gleam/dynamic/decode
import gleam/int
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

///
///
pub const tag: String = "clique-handle"

///
///
pub fn register() -> Result(Nil, lustre.Error) {
  lustre.register(
    lustre.component(init:, update:, view:, options: options()),
    tag,
  )
}

// TYPES -----------------------------------------------------------------------

///
///
pub type Handle {
  Handle(node: String, name: String)
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
pub fn placement(side: Position) -> Attribute(msg) {
  attribute("placement", position.to_side(side))
}

///
///
pub fn tolerance(value: Int) -> Attribute(msg) {
  case lustre.is_browser() {
    True -> attribute.property("tolerance", json.int(value))
    False -> attribute("tolerance", int.to_string(value))
  }
}

// EVENTS ----------------------------------------------------------------------

///
///
pub fn on_connection_start(handler: fn(Handle) -> msg) -> Attribute(msg) {
  event.on("clique:connection-start", {
    use node <- decode.subfield(["detail", "node"], decode.string)
    use name <- decode.subfield(["detail", "name"], decode.string)

    decode.success(handler(Handle(node:, name:)))
  })
}

fn emit_connection_start(node: String, handle: String) -> Effect(msg) {
  event.emit("clique:connection-start", {
    json.object([
      #("node", json.string(node)),
      #("name", json.string(handle)),
    ])
  })
}

///
///
pub fn on_connection_complete(
  handler: fn(Handle, Handle) -> msg,
) -> Attribute(msg) {
  let handle_decoder = {
    use node <- decode.field("node", decode.string)
    use name <- decode.field("name", decode.string)

    decode.success(Handle(node:, name:))
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
          #("name", json.string(from.1)),
        ])
      }),

      #("to", {
        json.object([
          #("node", json.string(to.0)),
          #("name", json.string(to.1)),
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
    tolerance: Int,
  )
}

fn init(_) -> #(Model, Effect(Msg)) {
  let model =
    Model(node: "", name: "", disabled: False, connection: None, tolerance: 5)

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

    component.on_attribute_change("tolerance", fn(value) {
      case int.parse(value) {
        Ok(v) if v >= 0 -> Ok(ParentSetTolerance(value: v))
        _ -> Ok(ParentSetTolerance(value: 5))
      }
    }),

    component.on_property_change("tolerance", {
      use v <- decode.then(decode.int)

      case v >= 0 {
        True -> decode.success(ParentSetTolerance(value: v))
        False -> decode.success(ParentSetTolerance(value: 5))
      }
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
  ParentSetTolerance(value: Int)
  ParentToggledDisabled
  UserCompletedConnection
  UserStartedConnection
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

    ParentSetTolerance(value:) -> {
      let model = Model(..model, tolerance: value)
      let effect = effect.none()

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

fn view(model: Model) -> Element(Msg) {
  element.fragment([
    html.style([], {
      "
      :host(:state(disabled)), :host(:state(invalid)) {
        pointer-events: none;
      }

      :host(:hover) {
        cursor: crosshair;
      }

      "
    }),
    component.default_slot([], []),
    case model.tolerance {
      0 -> element.none()
      _ -> view_tolerance_box(model.tolerance)
    },
  ])
}

fn view_tolerance_box(value: Int) -> Element(Msg) {
  let tolerance = "calc(100% + " <> int.to_string(value * 2) <> "px)"
  let translate =
    "translate(-"
    <> int.to_string(value)
    <> "px, -"
    <> int.to_string(value)
    <> "px)"

  html.div(
    [
      attribute.style("width", tolerance),
      attribute.style("height", tolerance),
      attribute.style("transform", translate),
    ],
    [],
  )
}
