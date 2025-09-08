// IMPORTS ---------------------------------------------------------------------

import clique/internal/dom.{type HtmlElement}
import clique/internal/handles.{type Handles}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/float
import gleam/function
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre
import lustre/attribute.{type Attribute}
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element, element}
import lustre/element/html
import lustre/event

// COMPONENT -------------------------------------------------------------------

pub const tag: String = "clique-viewport"

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

pub fn behind() -> Attribute(msg) {
  component.slot("behind")
}

pub fn front() -> Attribute(msg) {
  component.slot("front")
}

// EVENTS ----------------------------------------------------------------------

// CONTEXT ---------------------------------------------------------------------

fn provide_transform(transform: Transform) -> Effect(msg) {
  effect.provide("clique/transform", {
    json.object([
      #("translate_x", json.float(transform.translate_x)),
      #("translate_y", json.float(transform.translate_y)),
      #("scale", json.float(transform.scale)),
    ])
  })
}

@internal
pub fn on_transform_change(
  handler: fn(Transform) -> msg,
) -> component.Option(msg) {
  component.on_context_change("clique/transform", {
    use translate_x <- decode.field("translate_x", decode.float)
    use translate_y <- decode.field("translate_y", decode.float)
    use scale <- decode.field("scale", decode.float)

    decode.success(handler(Transform(translate_x:, translate_y:, scale:)))
  })
}

fn provide_handles(
  handles: Dict(String, Dict(String, #(Float, Float))),
) -> Effect(Msg) {
  effect.provide("clique/handles", {
    json.dict(handles, function.identity, {
      json.dict(_, function.identity, fn(position: #(Float, Float)) {
        json.preprocessed_array([
          json.float(position.0),
          json.float(position.1),
        ])
      })
    })
  })
}

@internal
pub fn on_handles_change(handler: fn(Handles) -> msg) -> component.Option(msg) {
  component.on_context_change("clique/handles", {
    decode.dynamic
    |> decode.map(handles.unsafe_from_dynamic)
    |> decode.map(handler)
  })
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(
    transform: Transform,
    drag: #(Float, Float),
    observer: Option(NodeResizeObserver),
    handles: Dict(String, Dict(String, #(Float, Float))),
    last_pan_velocity: #(Float, Float),
    is_panning: Bool,
    inertia_id: Option(Int),
  )
}

pub type Transform {
  Transform(translate_x: Float, translate_y: Float, scale: Float)
}

type NodeResizeObserver

fn init(_) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      transform: Transform(translate_x: 0.0, translate_y: 0.0, scale: 1.0),
      drag: #(0.0, 0.0),
      observer: None,
      handles: dict.new(),
      last_pan_velocity: #(0.0, 0.0),
      is_panning: False,
      inertia_id: None,
    )
  let effect =
    effect.batch([
      provide_transform(model.transform),
      provide_handles(model.handles),
      add_resize_observer(),
    ])

  #(model, effect)
}

fn add_resize_observer() -> Effect(Msg) {
  use dispatch, shadow_root <- effect.before_paint
  let observer =
    do_add_resize_observer(shadow_root, fn(changes) {
      dispatch(NodesResized(changes:))
    })

  dispatch(NodeResizeObserverStarted(observer:))
}

@external(javascript, "./viewport.ffi.mjs", "add_resize_observer")
fn do_add_resize_observer(
  shadow_root: Dynamic,
  callback: fn(List(#(String, String, Float, Float))) -> Nil,
) -> NodeResizeObserver

fn options() -> List(component.Option(Msg)) {
  []
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  NodeMounted(element: HtmlElement)
  NodeMoved(id: String, dx: Float, dy: Float)
  NodeResizeObserverStarted(observer: NodeResizeObserver)
  NodesResized(changes: List(#(String, String, Float, Float)))
  UserPannedViewport(x: Float, y: Float)
  UserStartedPanning(x: Float, y: Float)
  UserStoppedPanning
  UserZoomedViewport(x: Float, y: Float, delta: Float)
  InertiaFrame(timestamp: Float, vx: Float, vy: Float, id: Int)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    NodeMounted(element:) ->
      case model.observer {
        Some(observer) -> #(model, observe_node(observer, element))
        None -> #(model, effect.none())
      }

    NodeMoved(id: node, dx:, dy:) ->
      case dict.get(model.handles, node) {
        Ok(node_handles) -> {
          let handles =
            node_handles
            |> dict.map_values(fn(_, position) {
              #(position.0 +. dx, position.1 +. dy)
            })
            |> dict.insert(model.handles, node, _)
          let model = Model(..model, handles:)
          let effect = provide_handles(handles)

          #(model, effect)
        }

        Error(_) -> #(model, effect.none())
      }

    NodesResized(changes:) -> {
      let handles = {
        use all, #(node, handle, x, y) <- list.fold(changes, model.handles)

        case dict.get(all, node) {
          Ok(for_node) ->
            dict.insert(all, node, dict.insert(for_node, handle, #(x, y)))

          Error(_) ->
            dict.insert(all, node, dict.from_list([#(handle, #(x, y))]))
        }
      }

      let model = Model(..model, handles:)
      let effect = provide_handles(handles)

      #(model, effect)
    }

    NodeResizeObserverStarted(observer:) -> {
      let model = Model(..model, observer: Some(observer))
      let effect = effect.none()

      #(model, effect)
    }

    UserPannedViewport(x:, y:) -> {
      let dx = x -. model.drag.0
      let dy = y -. model.drag.1
      let drag = #(x, y)
      let transform =
        Transform(
          ..model.transform,
          translate_x: model.transform.translate_x +. dx,
          translate_y: model.transform.translate_y +. dy,
        )

      // Store velocity for inertia (scaled for smooth feel)
      let last_pan_velocity = #(dx *. 0.8, dy *. 0.8)

      let model = Model(..model, transform:, drag:, last_pan_velocity:)
      let effect = provide_transform(transform)

      #(model, effect)
    }

    UserStartedPanning(x:, y:) -> {
      let drag = #(x, y)
      let model =
        Model(
          ..model,
          drag:,
          last_pan_velocity: #(0.0, 0.0),
          is_panning: True,
          inertia_id: None,
        )
      let effect = add_window_mousemove_listener()

      #(model, effect)
    }

    UserStoppedPanning -> {
      let model = Model(..model, is_panning: False)

      // Use last pan velocity for inertia
      let #(vx, vy) = model.last_pan_velocity
      let velocity_magnitude =
        float.absolute_value(vx) +. float.absolute_value(vy)

      case velocity_magnitude >. 0.5 {
        True -> {
          let inertia_id = generate_inertia_id()
          let updated_model = Model(..model, inertia_id: Some(inertia_id))
          let effect = start_inertia_animation(vx, vy, inertia_id)
          #(updated_model, effect)
        }
        False -> #(model, effect.none())
      }
    }

    InertiaFrame(timestamp: _, vx:, vy:, id:) -> {
      case model.inertia_id {
        Some(current_id) if current_id == id && !model.is_panning -> {
          // Apply strong friction for faster stop
          let friction = 0.85
          let new_vx = vx *. friction
          let new_vy = vy *. friction

          // Stop if velocity is too low
          let min_velocity = 0.2
          case
            float.absolute_value(new_vx) <. min_velocity
            && float.absolute_value(new_vy) <. min_velocity
          {
            True -> {
              let model = Model(..model, inertia_id: None)
              #(model, effect.none())
            }
            False -> {
              // Update transform
              let transform =
                Transform(
                  ..model.transform,
                  translate_x: model.transform.translate_x +. new_vx,
                  translate_y: model.transform.translate_y +. new_vy,
                )
              let model = Model(..model, transform:)
              let effect =
                effect.batch([
                  provide_transform(transform),
                  continue_inertia_animation(new_vx, new_vy, id),
                ])
              #(model, effect)
            }
          }
        }
        _ -> #(model, effect.none())
        // Inertia was cancelled or wrong ID
      }
    }

    UserZoomedViewport(x:, y:, delta:) -> {
      let zoom_factor = case delta >. 0.0 {
        True -> 1.1
        False -> 1.0 /. 1.1
      }
      let min_scale = 0.1
      let max_scale = 5.0
      let new_scale = model.transform.scale *. zoom_factor
      let clamped_scale = case new_scale {
        s if s <. min_scale -> min_scale
        s if s >. max_scale -> max_scale
        s -> s
      }

      // Convert mouse position to world coordinates before zoom
      let world_x =
        { x -. model.transform.translate_x } /. model.transform.scale
      let world_y =
        { y -. model.transform.translate_y } /. model.transform.scale

      // Calculate new translation to keep the world point under the mouse
      let new_translate_x = x -. world_x *. clamped_scale
      let new_translate_y = y -. world_y *. clamped_scale

      let transform =
        Transform(
          translate_x: new_translate_x,
          translate_y: new_translate_y,
          scale: clamped_scale,
        )
      let model = Model(..model, transform:)
      let effect = provide_transform(transform)

      #(model, effect)
    }
  }
}

// EFFECTS ---------------------------------------------------------------------

fn add_window_mousemove_listener() -> Effect(Msg) {
  use dispatch <- effect.from
  use event <- do_add_window_mousemove_listener(fn() {
    dispatch(UserStoppedPanning)
  })

  let decoder = {
    use client_x <- decode.field("clientX", decode.float)
    use client_y <- decode.field("clientY", decode.float)

    decode.success(UserPannedViewport(x: client_x, y: client_y))
  }

  case decode.run(event, decoder) {
    Ok(msg) -> dispatch(msg)
    Error(_) -> Nil
  }
}

@external(javascript, "./viewport.ffi.mjs", "add_window_mousemove_listener")
fn do_add_window_mousemove_listener(
  handle_mouseup: fn() -> Nil,
  callback: fn(Dynamic) -> Nil,
) -> Nil

fn start_inertia_animation(vx: Float, vy: Float, id: Int) -> Effect(Msg) {
  use dispatch <- effect.from
  use new_timestamp <- do_request_animation_frame
  dispatch(InertiaFrame(timestamp: new_timestamp, vx:, vy:, id:))
}

fn continue_inertia_animation(vx: Float, vy: Float, id: Int) -> Effect(Msg) {
  use dispatch <- effect.from
  use new_timestamp <- do_request_animation_frame
  dispatch(InertiaFrame(timestamp: new_timestamp, vx:, vy:, id:))
}

@external(javascript, "./viewport.ffi.mjs", "request_animation_frame")
fn do_request_animation_frame(callback: fn(Float) -> Nil) -> Nil

@external(javascript, "./viewport.ffi.mjs", "generate_inertia_id")
fn generate_inertia_id() -> Int

fn observe_node(
  observer: NodeResizeObserver,
  element: HtmlElement,
) -> Effect(Msg) {
  use _ <- effect.from
  do_observe_node(observer, element)
}

@external(javascript, "./viewport.ffi.mjs", "observe_node")
fn do_observe_node(observer: NodeResizeObserver, node: HtmlElement) -> Nil

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  let handle_node_mount = {
    use target <- decode.field("target", dom.element_decoder())
    decode.success(NodeMounted(element: target))
  }

  let handle_node_drag = {
    use id <- decode.subfield(["target", "id"], decode.string)
    use dx <- decode.subfield(["detail", "dx"], decode.float)
    use dy <- decode.subfield(["detail", "dy"], decode.float)

    decode.success(NodeMoved(id:, dx:, dy:))
  }

  element.fragment([
    html.style([], {
      "
      :host {
          display: block;
          position: relative;
          width: 100%;
          height: 100%;
          contain: layout style paint;
          will-change: scroll-position;
      }

      #container {
          position: relative;
          width: 100%;
          height: 100%;
          overflow: hidden;
          cursor: grab;
          contain: layout paint;
          backface-visibility: hidden;
          transform: translateZ(0);
      }

      :host(:state(dragging)) {
        cursor: grabbing;
      }

      :host(:state(dragging)) #viewport {
        will-change: transform;
      }

      #viewport {
          position: absolute;
          width: 100%;
          height: 100%;
          transform-origin: 0 0;
          transition: none;
          overflow: visible;
          contain: layout style;
          isolation: isolate;
      }
      "
    }),

    view_container([
      component.named_slot("behind", [], []),
      view_viewport(model.transform, [
        component.default_slot(
          [
            event.on("clique:mount", handle_node_mount),
            event.on("clique:drag", handle_node_drag),
          ],
          [],
        ),
      ]),
      component.named_slot("front", [], []),
    ]),
  ])
}

// VIEW CONTAINER --------------------------------------------------------------

fn view_container(children: List(Element(Msg))) -> Element(Msg) {
  let handle_mousedown = {
    use target <- decode.field("target", dom.element_decoder())
    use client_x <- decode.field("clientX", decode.float)
    use client_y <- decode.field("clientY", decode.float)

    let dispatch = UserStartedPanning(x: client_x, y: client_y)

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

  let handle_wheel = {
    use target <- decode.field("currentTarget", dom.element_decoder())
    use client_x <- decode.field("clientX", decode.float)
    use client_y <- decode.field("clientY", decode.float)
    use delta <- decode.field("deltaY", decode.float)

    // Get container bounds to calculate relative mouse position
    let rect = dom.bounding_client_rect(target)
    let x = client_x -. rect.left
    let y = client_y -. rect.top

    decode.success(UserZoomedViewport(x:, y:, delta:))
  }

  html.div(
    [
      attribute.id("container"),
      event.advanced("mousedown", handle_mousedown),
      event.on("wheel", handle_wheel) |> event.prevent_default,
      attribute.style("touch-action", "none"),
    ],
    children,
  )
}

// VIEW VIEWPORT ---------------------------------------------------------------

fn view_viewport(
  transform: Transform,
  children: List(Element(Msg)),
) -> Element(Msg) {
  let translate =
    "translate(${x}px, ${y}px) scale(${scale})"
    |> string.replace("${x}", float.to_string(transform.translate_x))
    |> string.replace("${y}", float.to_string(transform.translate_y))
    |> string.replace("${scale}", float.to_string(transform.scale))

  html.div(
    [attribute.id("viewport"), attribute.style("transform", translate)],
    children,
  )
}
