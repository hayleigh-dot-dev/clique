// IMPORTS ---------------------------------------------------------------------

import clique/internal/dom.{type HtmlElement}
import clique/internal/drag.{type DragState}
import clique/internal/events
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/float
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

fn provide_scale(scale: Float) -> Effect(msg) {
  effect.provide("clique/transform", json.float(scale))
}

@internal
pub fn on_scale_change(handler: fn(Float) -> msg) -> component.Option(msg) {
  component.on_context_change("clique/transform", {
    use scale <- decode.then(decode.float)
    decode.success(handler(scale))
  })
}

fn provide_handles(
  handles: Dict(String, Dict(String, #(Float, Float))),
) -> Effect(Msg) {
  effect.provide(
    "clique/handles",
    json.object({
      use fields, node, handles <- dict.fold(handles, [])
      use fields, handle, position <- dict.fold(handles, fields)
      let field = #(
        node <> "." <> handle,
        json.array([position.0, position.1], json.float),
      )

      [field, ..fields]
    }),
  )
}

@internal
pub fn on_handles_change(
  handler: fn(Dict(String, #(Float, Float))) -> msg,
) -> component.Option(msg) {
  component.on_context_change("clique/handles", {
    use handles <- decode.then(
      decode.dict(decode.string, {
        use x <- decode.field(0, decode.float)
        use y <- decode.field(1, decode.float)

        decode.success(#(x, y))
      }),
    )

    decode.success(handler(handles))
  })
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(
    transform: Transform,
    observer: Option(NodeResizeObserver),
    handles: Dict(String, Dict(String, #(Float, Float))),
    panning: DragState,
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
      observer: None,
      handles: dict.new(),
      panning: drag.Settled,
    )
  let effect =
    effect.batch([
      provide_scale(model.transform.scale),
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
  NodeMounted(id: String, element: HtmlElement)
  NodeMoved(id: String, x: Float, y: Float, dx: Float, dy: Float)
  NodeResizeObserverStarted(observer: NodeResizeObserver)
  NodesResized(changes: List(#(String, String, Float, Float)))
  UserPannedViewport(x: Float, y: Float)
  UserStartedPanning(x: Float, y: Float)
  UserStoppedPanning
  UserZoomedViewport(x: Float, y: Float, delta: Float)
  InertiaSimulationTicked
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    NodeMounted(id: _, element:) ->
      case model.observer {
        Some(observer) -> #(model, observe_node(observer, element))
        None -> #(model, effect.none())
      }

    NodeMoved(id: node, x: _, y: _, dx:, dy:) ->
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
      let #(panning, dx, dy) = drag.update(model.panning, x, y)
      let translate_x = model.transform.translate_x +. dx
      let translate_y = model.transform.translate_y +. dy
      let transform = Transform(..model.transform, translate_x:, translate_y:)

      let model = Model(..model, transform:, panning:)
      let effect = effect.none()

      #(model, effect)
    }

    UserStartedPanning(x:, y:) -> {
      let model = Model(..model, panning: drag.start(x, y))
      let effect = add_window_mousemove_listener()

      #(model, effect)
    }

    UserStoppedPanning -> {
      let #(panning, effect) = drag.stop(model.panning, InertiaSimulationTicked)
      let model = Model(..model, panning:)

      #(model, effect)
    }

    InertiaSimulationTicked -> {
      let #(panning, vx, vy, effect) =
        drag.tick(model.panning, InertiaSimulationTicked)

      let transform =
        Transform(
          ..model.transform,
          translate_x: model.transform.translate_x +. vx,
          translate_y: model.transform.translate_y +. vy,
        )

      let model = Model(..model, transform:, panning:)

      #(model, effect)
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
      let effect = provide_scale(transform.scale)

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
          [events.on_node_mount(NodeMounted), events.on_node_drag(NodeMoved)],
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
