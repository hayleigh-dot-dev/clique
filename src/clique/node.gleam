// IMPORTS ---------------------------------------------------------------------

import clique/internal/context
import clique/internal/dom.{type HtmlElement}
import clique/internal/drag.{type DragState}
import clique/internal/prop.{type Prop, Controlled, Touched, Unchanged}
import gleam/bool
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

pub fn position(x: Float, y: Float) -> Attribute(msg) {
  attribute.property(
    "position",
    json.preprocessed_array([json.float(x), json.float(y)]),
  )
}

pub fn initial_position(x: Float, y: Float) -> Attribute(msg) {
  attribute("position", float.to_string(x) <> " " <> float.to_string(y))
}

pub fn nodrag() -> Attribute(msg) {
  attribute.data("clique-disable", "drag")
}

// EVENTS ----------------------------------------------------------------------

///
///
pub fn on_change(handler: fn(String, Float, Float) -> msg) -> Attribute(msg) {
  event.on("clique:change", {
    use id <- decode.subfield(["target", "id"], decode.string)
    use dx <- decode.subfield(["detail", "dx"], decode.float)
    use dy <- decode.subfield(["detail", "dy"], decode.float)

    decode.success(handler(id, dx, dy))
  })
}

fn emit_change(dx dx: Float, dy dy: Float) -> Effect(msg) {
  use <- bool.guard(dx == 0.0 && dy == 0.0, effect.none())

  event.emit("clique:change", {
    json.object([
      #("dx", json.float(dx)),
      #("dy", json.float(dy)),
    ])
  })
}

///
///
pub fn on_drag(
  handler: fn(String, Float, Float, Float, Float) -> msg,
) -> Attribute(msg) {
  event.on("clique:drag", {
    use id <- decode.subfield(["target", "id"], decode.string)
    use x <- decode.subfield(["detail", "x"], decode.float)
    use y <- decode.subfield(["detail", "y"], decode.float)
    use dx <- decode.subfield(["detail", "dx"], decode.float)
    use dy <- decode.subfield(["detail", "dy"], decode.float)

    decode.success(handler(id, x, y, dx, dy))
  })
}

fn emit_drag(x x: Float, y y: Float, dx dx: Float, dy dy: Float) -> Effect(msg) {
  event.emit("clique:drag", {
    json.object([
      #("x", json.float(x)),
      #("y", json.float(y)),
      #("dx", json.float(dx)),
      #("dy", json.float(dy)),
    ])
  })
}

@internal
pub fn on_mount(handler: fn(HtmlElement, String) -> msg) -> Attribute(msg) {
  event.on("clique:mount", {
    use target <- decode.field("target", dom.element_decoder())
    use id <- decode.subfield(["target", "id"], decode.string)

    decode.success(handler(target, id))
  })
}

fn emit_mount() -> Effect(msg) {
  event.emit("clique:mount", json.null())
}

// CONTEXTS --------------------------------------------------------------------

fn provide(id: String) -> Effect(msg) {
  effect.provide("clique/node", json.object([#("id", json.string(id))]))
}

@internal
pub fn on_context_change(handler: fn(String) -> msg) -> component.Option(msg) {
  component.on_context_change("clique/node", {
    use id <- decode.field("id", decode.string)

    decode.success(handler(id))
  })
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(
    id: String,
    position: Prop(#(Float, Float)),
    dragging: DragState,
    scale: Float,
  )
}

fn init(_) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      id: "",
      position: prop.new(#(0.0, 0.0)),
      dragging: drag.Settled,
      scale: 1.0,
    )

  let effect =
    effect.batch([
      set_transform(model.position),
      effect.after_paint(fn(dispatch, _) { dispatch(BrowserPainted) }),
    ])

  #(model, effect)
}

fn options() -> List(component.Option(Msg)) {
  [
    component.adopt_styles(False),

    component.on_attribute_change("id", fn(value) {
      Ok(ParentSetId(id: string.trim(value)))
    }),

    component.on_attribute_change("position", fn(value) {
      let parse = fn(value) {
        case float.parse(value) {
          Ok(n) -> Ok(n)
          Error(_) ->
            case int.parse(value) {
              Ok(i) -> Ok(int.to_float(i))
              Error(_) -> Error(Nil)
            }
        }
      }

      case string.split(value, " ") |> list.map(string.trim) {
        [x, y] ->
          case parse(x), parse(y) {
            Ok(x), Ok(y) -> Ok(ParentSetInitialPosition(x: x, y: y))
            _, _ -> Error(Nil)
          }
        _ -> Error(Nil)
      }
    }),

    component.on_property_change("position", {
      use x <- decode.field(0, decode.float)
      use y <- decode.field(1, decode.float)

      decode.success(ParentUpdatedPosition(x:, y:))
    }),

    context.on_scale_change(ParentProvidedScale),
  ]
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  BrowserPainted
  InertiaSimulationTicked
  ParentProvidedScale(scale: Float)
  ParentSetId(id: String)
  ParentSetInitialPosition(x: Float, y: Float)
  ParentUpdatedPosition(x: Float, y: Float)
  UserDraggedNode(x: Float, y: Float)
  UserStartedDrag(x: Float, y: Float)
  UserStoppedDrag
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    BrowserPainted -> #(model, emit_mount())

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
          emit_drag(x:, y:, dx:, dy:),
          case position.state {
            Controlled -> effect.none()
            Unchanged | Touched -> emit_change(dx:, dy:)
          },
          set_transform(model.position),
        ])

      #(model, effect)
    }

    ParentProvidedScale(scale:) -> {
      let model = Model(..model, scale:)
      let effect = effect.none()

      #(model, effect)
    }

    ParentSetId(id:) -> {
      let model = Model(..model, id:)
      let effect = provide(id)

      #(model, effect)
    }

    ParentSetInitialPosition(x:, y:) -> {
      let position = prop.uncontrolled(model.position, #(x, y))
      let dx = position.value.0 -. model.position.value.0
      let dy = position.value.1 -. model.position.value.1
      let model = Model(..model, position:)
      let effect =
        effect.batch([set_transform(model.position), emit_change(dx:, dy:)])

      #(model, effect)
    }

    ParentUpdatedPosition(x:, y:) -> {
      let position = prop.controlled(#(x, y))
      let dx = position.value.0 -. model.position.value.0
      let dy = position.value.1 -. model.position.value.1
      let model = Model(..model, position:)
      let effect =
        effect.batch([set_transform(model.position), emit_change(dx:, dy:)])

      #(model, effect)
    }

    UserDraggedNode(x:, y:) -> {
      let #(dragging, dx, dy) = drag.update(model.dragging, x, y)
      let dx = dx /. model.scale
      let dy = dy /. model.scale

      let nx = model.position.value.0 +. dx
      let ny = model.position.value.1 +. dy
      let position = prop.update(model.position, #(nx, ny))

      let model = Model(..model, position:, dragging:)
      let effect =
        effect.batch([
          emit_drag(x: nx, y: ny, dx:, dy:),
          case position.state {
            Controlled -> effect.none()
            Unchanged | Touched -> emit_change(dx:, dy:)
          },
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
        position: absolute !important;
        top: 0 !important;
        left: 0 !important;
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
