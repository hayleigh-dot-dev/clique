// IMPORTS ---------------------------------------------------------------------

import clique/internal/dom
import clique/internal/prop.{type Prop}
import clique/viewport.{type Transform, Transform}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import lustre
import lustre/attribute.{type Attribute, attribute}
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element, element}
import lustre/element/html
import lustre/event

// COMPONENT -------------------------------------------------------------------

pub const tag: String = "clique-node"

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

pub fn initial_x(value: Float) -> Attribute(msg) {
  attribute("x", float.to_string(value))
}

pub fn initial_y(value: Float) -> Attribute(msg) {
  attribute("y", float.to_string(value))
}

pub fn nodrag() -> Attribute(msg) {
  attribute.data("clique-disable", "drag")
}

// EVENTS ----------------------------------------------------------------------

// MODEL -----------------------------------------------------------------------

type Model {
  Model(
    position: Prop(#(Float, Float)),
    drag: #(Float, Float),
    transform: Transform,
  )
}

fn init(_) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      position: prop.new(#(0.0, 0.0)),
      drag: #(0.0, 0.0),
      transform: Transform(translate_x: 0.0, translate_y: 0.0, scale: 1.0),
    )

  let effect =
    effect.batch([
      set_css_position(model.position),
      effect.after_paint(fn(dispatch, _) { dispatch(BrowserPainted) }),
    ])

  #(model, effect)
}

fn options() -> List(component.Option(Msg)) {
  [
    component.on_attribute_change("x", fn(value) {
      case float.parse(value), int.parse(value) {
        Ok(x), _ -> Ok(ParentSetInitialX(value: x))
        _, Ok(x) -> Ok(ParentSetInitialX(value: int.to_float(x)))
        _, _ -> Error(Nil)
      }
    }),

    component.on_property_change("x", {
      decode.float
      |> decode.map(ParentUpdatedX(value: _))
    }),

    component.on_attribute_change("y", fn(value) {
      case float.parse(value), int.parse(value) {
        Ok(y), _ -> Ok(ParentSetInitialY(value: y))
        _, Ok(y) -> Ok(ParentSetInitialY(value: int.to_float(y)))
        _, _ -> Error(Nil)
      }
    }),

    component.on_property_change("y", {
      decode.float
      |> decode.map(ParentUpdatedY(value: _))
    }),

    viewport.on_transform_change(ParentProvidedTransform),
  ]
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  BrowserPainted
  ParentProvidedTransform(transform: Transform)
  ParentSetInitialX(value: Float)
  ParentSetInitialY(value: Float)
  ParentUpdatedX(value: Float)
  ParentUpdatedY(value: Float)
  UserDraggedNode(x: Float, y: Float)
  UserStartedDrag(x: Float, y: Float)
  UserStoppedDrag
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    BrowserPainted -> #(model, event.emit("clique:mount", json.null()))

    ParentProvidedTransform(transform:) -> {
      let model = Model(..model, transform:)
      let effect = effect.none()

      #(model, effect)
    }

    ParentSetInitialX(value:) -> {
      let position =
        prop.uncontrolled(model.position, #(value, model.position.value.1))
      let model = Model(..model, position:)
      let effect = set_css_position(model.position)

      #(model, effect)
    }

    ParentSetInitialY(value:) -> {
      let position =
        prop.uncontrolled(model.position, #(model.position.value.0, value))
      let model = Model(..model, position:)
      let effect = set_css_position(model.position)

      #(model, effect)
    }

    ParentUpdatedX(value:) -> {
      let position = prop.controlled(#(value, model.position.value.1))
      let model = Model(..model, position:)
      let effect = set_css_position(model.position)

      #(model, effect)
    }

    ParentUpdatedY(value:) -> {
      let position = prop.controlled(#(model.position.value.0, value))
      let model = Model(..model, position:)
      let effect = set_css_position(model.position)

      #(model, effect)
    }

    UserDraggedNode(x:, y:) -> {
      let dx = { x -. model.drag.0 } /. model.transform.scale
      let dy = { y -. model.drag.1 } /. model.transform.scale
      let drag = #(x, y)
      let #(position, effect) =
        prop.update(
          model.position,
          "clique:drag",
          fn(position) {
            json.object([
              #("x", json.float(position.0)),
              #("dx", json.float(dx)),
              #("y", json.float(position.1)),
              #("dy", json.float(dy)),
            ])
          },
          #(model.position.value.0 +. dx, model.position.value.1 +. dy),
        )

      let model = Model(..model, position:, drag:)
      let effect = effect.batch([effect, set_css_position(position)])

      #(model, effect)
    }

    UserStartedDrag(x:, y:) -> {
      let drag = #(x, y)
      let model = Model(..model, drag:)
      let effect =
        effect.batch([
          add_window_mousemove_listener(),
          component.set_pseudo_state("dragging"),
        ])

      #(model, effect)
    }

    UserStoppedDrag -> {
      let effect = component.remove_pseudo_state("dragging")

      #(model, effect)
    }
  }
}

// EFFECTS ---------------------------------------------------------------------

fn set_css_position(position: Prop(#(Float, Float))) -> Effect(msg) {
  effect.batch([
    set_css_property("--x", float.to_string(position.value.0) <> "px"),
    set_css_property("--y", float.to_string(position.value.1) <> "px"),
  ])
}

fn set_css_property(name: String, value: String) -> Effect(msg) {
  use _, shadow_root <- effect.before_paint
  do_set_css_property(shadow_root, name, value)
}

@external(javascript, "./node.ffi.mjs", "set_css_property")
fn do_set_css_property(shadow_root: Dynamic, name: String, value: String) -> Nil

fn add_window_mousemove_listener() -> Effect(Msg) {
  use dispatch <- effect.from
  use event <- do_add_window_mousemove_listener(on_mouseup: fn() {
    dispatch(UserStoppedDrag)
  })

  let decoder = {
    use client_x <- decode.field("clientX", decode.float)
    use client_y <- decode.field("clientY", decode.float)

    decode.success(UserDraggedNode(x: client_x, y: client_y))
  }

  case decode.run(event, decoder) {
    Ok(msg) -> dispatch(msg)
    Error(_) -> Nil
  }
}

@external(javascript, "./node.ffi.mjs", "add_window_mousemove_listener")
fn do_add_window_mousemove_listener(
  callback: fn(Dynamic) -> Nil,
  on_mouseup handle_mouseup: fn() -> Nil,
) -> Nil

// VIEW ------------------------------------------------------------------------

fn view(_) -> Element(Msg) {
  let handle_mousedown = {
    use target <- decode.field("target", dom.element_decoder())
    use client_x <- decode.field("clientX", decode.float)
    use client_y <- decode.field("clientY", decode.float)

    let dispatch = UserStartedDrag(x: client_x, y: client_y)

    let success =
      decode.success(event.handler(
        dispatch:,
        prevent_default: False,
        stop_propagation: True,
      ))

    let failure =
      decode.failure(
        event.handler(
          dispatch:,
          prevent_default: False,
          stop_propagation: False,
        ),
        "",
      )

    case dom.attribute(target, "data-clique-disable") {
      Ok("") | Error(_) -> success

      Ok(disable) -> {
        let nodrag =
          disable
          |> string.split(" ")
          |> list.map(string.trim)
          |> list.contains("drag")

        case nodrag {
          True -> failure
          False -> success
        }
      }
    }
  }

  element.fragment([
    html.style([], {
      ":host {
        display: block;
        left: var(--x);
        min-width: max-content;
        position: absolute;
        top: var(--y);
      }

      :host(:state(dragging)) {
        pointer-events: none;
      }"
    }),

    component.default_slot([event.advanced("mousedown", handle_mousedown)], []),
  ])
}
