// IMPORTS ---------------------------------------------------------------------

import clique/bounds.{type Bounds}
import clique/handle
import clique/internal/context
import clique/internal/dom.{type HtmlElement}
import clique/internal/drag.{type DragState}
import clique/node
import clique/path
import clique/position
import clique/transform.{type Transform}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/float
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre
import lustre/attribute.{type Attribute, attribute}
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element, element}
import lustre/element/html
import lustre/element/svg
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

pub fn overlay() -> Attribute(msg) {
  component.slot("overlay")
}

// EVENTS ----------------------------------------------------------------------

pub fn on_resize(handler: fn(Bounds) -> msg) -> Attribute(msg) {
  event.on("clique:resize", {
    use bounds <- decode.field("detail", bounds.decoder())

    decode.success(handler(bounds))
  })
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(
    transform: Transform,
    observer: Option(NodeResizeObserver),
    handles: Dict(String, Dict(String, #(Float, Float))),
    panning: DragState,
    connection: Option(#(#(String, String), #(Float, Float))),
    bounds: Bounds,
  )
}

type NodeResizeObserver

fn init(_) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      transform: transform.init(),
      observer: None,
      handles: dict.new(),
      panning: drag.Settled,
      connection: None,
      bounds: bounds.init(),
    )

  let effect =
    effect.batch([
      context.provide_transform(model.transform),
      context.provide_scale(model.transform.2),
      context.provide_connection(None),
      set_transform(model.transform),
      context.provide_handles(model.handles),
      add_resize_observer(),
    ])

  #(model, effect)
}

fn add_resize_observer() -> Effect(Msg) {
  use dispatch, shadow_root <- effect.before_paint
  let observer =
    do_add_resize_observer(
      shadow_root,
      fn(bounds) { dispatch(ViewportReszied(bounds:)) },
      fn(changes) { dispatch(NodesResized(changes:)) },
    )

  dispatch(NodeResizeObserverStarted(observer:))
}

@external(javascript, "./viewport.ffi.mjs", "add_resize_observer")
fn do_add_resize_observer(
  shadow_root: Dynamic,
  on_viewport_change: fn(Bounds) -> Nil,
  on_nodes_change: fn(List(#(String, String, Float, Float))) -> Nil,
) -> NodeResizeObserver

fn options() -> List(component.Option(Msg)) {
  [component.adopt_styles(False)]
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  InertiaSimulationTicked
  NodeMounted(element: HtmlElement, id: String)
  NodeMoved(id: String, dx: Float, dy: Float)
  NodeResizeObserverStarted(observer: NodeResizeObserver)
  NodesResized(changes: List(#(String, String, Float, Float)))
  UserCompletedConnection
  UserPannedViewport(x: Float, y: Float)
  UserStartedConnection(node: String, handle: String)
  UserStartedPanning(x: Float, y: Float)
  UserStoppedPanning
  UserZoomedViewport(client_x: Float, client_y: Float, delta: Float)
  ViewportReszied(bounds: Bounds)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    NodeMounted(id: _, element:) ->
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
          let effect = context.provide_handles(handles)

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
      let effect = context.provide_handles(handles)

      #(model, effect)
    }

    NodeResizeObserverStarted(observer:) -> {
      let model = Model(..model, observer: Some(observer))
      let effect = effect.none()

      #(model, effect)
    }

    UserCompletedConnection ->
      case model.connection {
        Some(_) -> #(
          Model(..model, connection: None),
          context.provide_connection(None),
        )

        None -> #(model, effect.none())
      }

    UserPannedViewport(x:, y:) ->
      case model.connection {
        Some(#(connection, _)) -> {
          let world_x =
            { x -. model.bounds.0 -. model.transform.0 } /. model.transform.2
          let world_y =
            { y -. model.bounds.1 -. model.transform.1 } /. model.transform.2

          let position = #(world_x, world_y)
          let model = Model(..model, connection: Some(#(connection, position)))
          let effect = effect.none()

          #(model, effect)
        }

        None -> {
          let #(panning, dx, dy) = drag.update(model.panning, x, y)
          let transform =
            transform.new(
              x: model.transform.0 +. dx,
              y: model.transform.1 +. dy,
              zoom: model.transform.2,
            )

          let model = Model(..model, transform:, panning:)
          let effect =
            effect.batch([
              set_transform(transform),
              context.provide_transform(model.transform),
            ])

          #(model, effect)
        }
      }

    UserStartedConnection(node:, handle:) ->
      case dict.get(model.handles, node) |> result.try(dict.get(_, handle)) {
        Ok(start) -> {
          let connection = #(node, handle)
          let model = Model(..model, connection: Some(#(connection, start)))
          let effect =
            effect.batch([
              context.provide_connection(Some(#(node, handle))),
              add_window_mousemove_listener(),
            ])

          #(model, effect)
        }

        Error(_) -> #(model, effect.none())
      }

    UserStartedPanning(x:, y:) -> {
      let model = Model(..model, panning: drag.start(x, y))
      let effect = add_window_mousemove_listener()

      #(model, effect)
    }

    UserStoppedPanning -> {
      let #(panning, effect) = drag.stop(model.panning, InertiaSimulationTicked)
      let effect = case model.connection {
        Some(_) ->
          effect.batch([
            effect,
            event.emit("clique:connection-cancel", json.null()),
            context.provide_connection(None),
          ])
        None -> effect
      }

      let model = Model(..model, panning:, connection: None)

      #(model, effect)
    }

    InertiaSimulationTicked -> {
      let #(panning, vx, vy, effect) =
        drag.tick(model.panning, InertiaSimulationTicked)

      let transform =
        transform.new(
          x: model.transform.0 +. vx,
          y: model.transform.1 +. vy,
          zoom: model.transform.2,
        )

      let model = Model(..model, transform:, panning:)
      let effect =
        effect.batch([
          effect,
          set_transform(model.transform),
          context.provide_transform(model.transform),
        ])

      #(model, effect)
    }

    UserZoomedViewport(client_x:, client_y:, delta:) -> {
      let x = client_x -. model.bounds.0
      let y = client_y -. model.bounds.1

      let zoom_factor = case delta >. 0.0 {
        True -> 1.0 +. { delta *. 0.01 }
        False -> 1.0 /. { 1.0 +. { float.absolute_value(delta) *. 0.01 } }
      }

      let min_scale = 0.5
      let max_scale = 2.0
      let new_scale = model.transform.2 *. zoom_factor
      let clamped_scale = case new_scale {
        s if s <. min_scale -> min_scale
        s if s >. max_scale -> max_scale
        s -> s
      }

      // Convert mouse position to world coordinates before zoom
      let world_x = { x -. model.transform.0 } /. model.transform.2
      let world_y = { y -. model.transform.1 } /. model.transform.2

      // Calculate new translation to keep the world point under the mouse
      let new_translate_x = x -. world_x *. clamped_scale
      let new_translate_y = y -. world_y *. clamped_scale

      let transform =
        transform.new(
          x: new_translate_x,
          y: new_translate_y,
          zoom: clamped_scale,
        )
      let model = Model(..model, transform:)
      let effect =
        effect.batch([
          context.provide_scale(model.transform.2),
          set_transform(model.transform),
          context.provide_transform(model.transform),
        ])

      #(model, effect)
    }

    ViewportReszied(bounds:) -> {
      let model = Model(..model, bounds:)
      let effect = effect.none()

      #(model, effect)
    }
  }
}

// EFFECTS ---------------------------------------------------------------------

fn set_transform(transform: Transform) -> Effect(Msg) {
  use _, shadow_root <- effect.before_paint
  let matrix = transform.to_css_matrix(transform)

  do_set_transform(shadow_root, matrix)
}

@external(javascript, "./viewport.ffi.mjs", "set_transform")
fn do_set_transform(shadow_root: Dynamic, value: String) -> Nil

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

      :host(:state(dragging)) {
        cursor: grabbing;
      }

      :host(:state(dragging)) #viewport {
        will-change: transform;
      }

      #container {
          position: relative;
          width: 100%;
          height: 100%;
          overflow: hidden;
          cursor: grab;
          contain: layout paint;
          backface-visibility: hidden;
          transform: translate3d(0, 0, 0);
          position: relative;
      }

      #viewport {
          -moz-osx-font-smoothing: grayscale;
          -webkit-font-smoothing: antialiased;
          contain: layout style;
          height: 100%;
          image-rendering: -webkit-optimize-contrast;
          image-rendering: crisp-edges;
          isolation: isolate;
          overflow: visible;
          position: absolute;
          text-rendering: optimizeLegibility;
          transform-origin: 0 0;
          transition: none;
          width: 100%;
      }

      #connection-line {
        width: 100%;
        height: 100%;
        overflow: visible;
        position: absolute;
        top: 0;
        left: 0;
        will-change: transform;
        pointer-events: none;
      }
      "
    }),

    view_container([
      component.named_slot("background", [], []),

      view_viewport([
        component.default_slot(
          [
            node.on_mount(NodeMounted),
            node.on_change(NodeMoved),
            handle.on_connection_start(UserStartedConnection),
            handle.on_connection_complete(fn(_, _) { UserCompletedConnection }),
          ],
          [],
        ),

        case model.connection {
          Some(#(#(node, handle), end)) ->
            view_connection_line(model.handles, node, handle, end)
          None -> element.none()
        },
      ]),

      component.named_slot("overlay", [], []),
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
    use client_x <- decode.field("clientX", decode.float)
    use client_y <- decode.field("clientY", decode.float)
    use delta <- decode.field("deltaY", decode.float)

    decode.success(UserZoomedViewport(client_x:, client_y:, delta:))
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

fn view_viewport(children: List(Element(Msg))) -> Element(Msg) {
  html.div([attribute.id("viewport")], children)
}

// VIEW CONNECTION LINE --------------------------------------------------------

fn view_connection_line(
  handles: Dict(String, Dict(String, #(Float, Float))),
  from_node: String,
  from_handle: String,
  to: #(Float, Float),
) -> Element(msg) {
  let result = {
    use handles <- result.try(dict.get(handles, from_node))
    use from <- result.try(dict.get(handles, from_handle))
    let #(path, _, _) =
      path.bezier(from.0, from.1, position.Right, to.0, to.1, position.Left)

    Ok(
      html.svg([attribute.id("connection-line")], [
        svg.path([
          attribute("d", path),
          attribute("fill", "none"),
          attribute("stroke", "#000"),
          attribute("stroke-width", "2"),
        ]),
      ]),
    )
  }

  case result {
    Ok(svg) -> svg
    Error(_) -> element.none()
  }
}
