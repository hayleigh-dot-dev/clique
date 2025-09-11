// IMPORTS ---------------------------------------------------------------------

import clique/internal/dom
import clique/internal/drag.{type DragState}
import clique/internal/events
import clique/internal/prop.{type Prop}
import clique/viewport
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/float
import gleam/int
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
  Model(position: Prop(#(Float, Float)), dragging: DragState, scale: Float)
}

fn init(_) -> #(Model, Effect(Msg)) {
  let model =
    Model(position: prop.new(#(0.0, 0.0)), dragging: drag.Settled, scale: 1.0)

  let effect =
    effect.batch([
      set_transform(model.position),
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

    viewport.on_scale_change(ParentProvidedScale),
  ]
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  BrowserPainted
  InertiaSimulationTicked
  ParentProvidedScale(scale: Float)
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
    BrowserPainted -> #(model, events.emit_node_mount())

    InertiaSimulationTicked -> {
      let #(dragging, vx, vy, inertia_effect) =
        drag.tick(model.dragging, InertiaSimulationTicked)

      let x = model.position.value.0 +. { vx /. model.scale }
      let y = model.position.value.1 +. { vy /. model.scale }

      let dx = x -. model.position.value.0
      let dy = y -. model.position.value.1

      let position = prop.update(model.position, #(x, y))
      let model = Model(..model, position:, dragging:)

      let effect =
        effect.batch([
          inertia_effect,
          events.emit_node_drag(x, y, dx, dy),
          set_transform(model.position),
        ])

      #(model, effect)
    }

    ParentProvidedScale(scale:) -> {
      let model = Model(..model, scale:)
      let effect = effect.none()

      #(model, effect)
    }

    ParentSetInitialX(value:) -> {
      let position =
        prop.uncontrolled(model.position, #(value, model.position.value.1))
      let model = Model(..model, position:)
      let effect = set_transform(model.position)

      #(model, effect)
    }

    ParentSetInitialY(value:) -> {
      let position =
        prop.uncontrolled(model.position, #(model.position.value.0, value))
      let model = Model(..model, position:)
      let effect = set_transform(model.position)

      #(model, effect)
    }

    ParentUpdatedX(value:) -> {
      let position = prop.controlled(#(value, model.position.value.1))
      let model = Model(..model, position:)
      let effect = set_transform(model.position)

      #(model, effect)
    }

    ParentUpdatedY(value:) -> {
      let position = prop.controlled(#(model.position.value.0, value))
      let model = Model(..model, position:)
      let effect = set_transform(model.position)

      #(model, effect)
    }

    UserDraggedNode(x:, y:) -> {
      let #(dragging, dx, dy) = drag.update(model.dragging, x, y)
      let dx = dx /. model.scale
      let dy = dy /. model.scale

      let position =
        prop.update(model.position, #(
          model.position.value.0 +. dx,
          model.position.value.1 +. dy,
        ))

      let model = Model(..model, position:, dragging:)
      let effect =
        effect.batch([
          events.emit_node_drag(x, y, dx, dy),
          set_transform(position),
        ])

      #(model, effect)
    }

    UserStartedDrag(x:, y:) -> {
      let dragging = drag.start(x, y)
      let model = Model(..model, dragging:)
      let effect =
        effect.batch([
          add_window_mousemove_listener(),
          component.set_pseudo_state("dragging"),
        ])

      #(model, effect)
    }

    UserStoppedDrag -> {
      let #(dragging, inertia_effect) =
        drag.stop(model.dragging, InertiaSimulationTicked)

      let model = Model(..model, dragging:)
      let effect =
        effect.batch([inertia_effect, component.remove_pseudo_state("dragging")])

      #(model, effect)
    }
  }
}

// EFFECTS ---------------------------------------------------------------------

fn set_transform(position: Prop(#(Float, Float))) -> Effect(msg) {
  use _, shadow_root <- effect.before_paint
  let transform =
    "translate("
    <> float.to_string(position.value.0)
    <> "px, "
    <> float.to_string(position.value.1)
    <> "px)"

  do_set_transform(shadow_root, transform)
}

@external(javascript, "./node.ffi.mjs", "set_transform")
fn do_set_transform(shadow_root: Dynamic, value: String) -> Nil

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
        min-width: max-content;
        position: absolute;
        top: 0;
        left: 0;
        will-change: transform;
        backface-visibility: hidden;
      }

      :host(:state(dragging)) {
        pointer-events: none;
      }"
    }),

    component.default_slot([event.advanced("mousedown", handle_mousedown)], []),
  ])
}
