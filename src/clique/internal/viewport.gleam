// IMPORTS ---------------------------------------------------------------------

import clique/bounds.{type Bounds}
import clique/handle.{type Handle, Handle}
import clique/internal/context
import clique/internal/dom.{type HtmlElement}
import clique/internal/drag.{type DragState}
import clique/internal/number
import clique/internal/path
import clique/internal/prop.{type Prop, Controlled, Touched, Unchanged}
import clique/node
import clique/position
import clique/transform.{type Transform}
import gleam/bool
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

pub fn transform(transform: Transform) -> Attribute(msg) {
  case lustre.is_browser() {
    True -> attribute.property("transform", transform.to_json(transform))
    False -> initial_transform(transform)
  }
}

pub fn initial_transform(transform: Transform) -> Attribute(msg) {
  attribute("transform", transform.to_string(transform))
}

// EVENTS ----------------------------------------------------------------------

///
///
pub fn on_resize(handler: fn(Bounds) -> msg) -> Attribute(msg) {
  event.on("clique:resize", {
    use bounds <- decode.field("detail", bounds.decoder())

    decode.success(handler(bounds))
  })
}

fn emit_resize(bounds: Bounds) -> Effect(msg) {
  event.emit("clique:resize", bounds.to_json(bounds))
}

///
///
pub fn on_connection_cancel(
  handler: fn(Handle, Float, Float) -> msg,
) -> Attribute(msg) {
  event.on("clique:connection-cancel", {
    let handle_decoder = {
      use node <- decode.field("node", decode.string)
      use name <- decode.field("name", decode.string)

      decode.success(Handle(node:, name:))
    }

    use from <- decode.subfield(["detail", "from"], handle_decoder)
    use x <- decode.subfield(["detail", "x"], decode.float)
    use y <- decode.subfield(["detail", "y"], decode.float)

    decode.success(handler(from, x, y))
  })
}

fn emit_connection_cancel(
  from: #(String, String),
  x: Float,
  y: Float,
) -> Effect(msg) {
  event.emit("clique:connection-cancel", {
    json.object([
      #("from", {
        json.object([
          #("node", json.string(from.0)),
          #("name", json.string(from.1)),
        ])
      }),
      #("x", json.float(x)),
      #("y", json.float(y)),
    ])
  })
}

pub fn on_pan(handler: fn(Transform) -> msg) -> Attribute(msg) {
  event.on("clique:pan", {
    use transform <- decode.field("detail", transform.decoder())

    decode.success(handler(transform))
  })
}

fn emit_pan(transform: Transform) -> Effect(msg) {
  event.emit("clique:pan", transform.to_json(transform))
}

pub fn on_zoom(handler: fn(Transform) -> msg) -> Attribute(msg) {
  event.on("clique:zoom", {
    use transform <- decode.field("detail", transform.decoder())

    decode.success(handler(transform))
  })
}

fn emit_zoom(transform: Transform) -> Effect(msg) {
  event.emit("clique:zoom", transform.to_json(transform))
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(
    transform: Prop(Transform),
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
      transform: prop.new(transform.init()),
      observer: None,
      handles: dict.new(),
      panning: drag.Settled,
      connection: None,
      bounds: bounds.init(),
    )

  let effect =
    effect.batch([
      context.provide_transform(model.transform.value),
      context.provide_scale(model.transform.value.2),
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
  [
    component.adopt_styles(False),

    component.on_attribute_change("transform", fn(value) {
      case string.split(value, " ") |> list.map(string.trim) {
        [x, y, zoom] -> {
          case number.parse(x), number.parse(y), number.parse(zoom) {
            Ok(x), Ok(y), Ok(zoom) ->
              Ok(ParentSetInitialTransform(transform.new(x:, y:, zoom:)))
            _, _, _ -> Error(Nil)
          }
        }
        _ -> Error(Nil)
      }
    }),

    component.on_property_change("transform", {
      transform.decoder()
      |> decode.map(ParentUpdatedTransform)
    }),
  ]
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  InertiaSimulationTicked
  NodeMounted(element: HtmlElement, id: String)
  NodeMoved(id: String, dx: Float, dy: Float)
  NodeResizeObserverStarted(observer: NodeResizeObserver)
  NodesResized(changes: List(#(String, String, Float, Float)))
  ParentSetInitialTransform(transform: Transform)
  ParentUpdatedTransform(transform: Transform)
  UserCompletedConnection
  UserPannedViewport(x: Float, y: Float)
  UserStartedConnection(source: Handle)
  UserStartedPanning(x: Float, y: Float)
  UserStoppedPanning(x: Float, y: Float)
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
        let x = { x -. model.transform.value.0 } /. model.transform.value.2
        let y = { y -. model.transform.value.1 } /. model.transform.value.2
        let position = #(x, y)

        case dict.get(all, node) {
          Ok(for_node) ->
            dict.insert(all, node, dict.insert(for_node, handle, position))

          Error(_) ->
            dict.insert(all, node, dict.from_list([#(handle, position)]))
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
          effect.batch([
            context.provide_connection(None),
            component.remove_pseudo_state("connecting"),
          ]),
        )

        None -> #(model, effect.none())
      }

    ParentSetInitialTransform(transform: new_transform) -> {
      let transform = prop.uncontrolled(model.transform, new_transform)
      let model = Model(..model, transform:)
      let effect =
        effect.batch([
          set_transform(model.transform),
          context.provide_transform(model.transform.value),
          context.provide_scale(model.transform.value.2),
        ])

      #(model, effect)
    }

    ParentUpdatedTransform(transform: new_transform) -> {
      let transform = prop.controlled(new_transform)
      let model = Model(..model, transform:)
      let effect =
        effect.batch([
          set_transform(model.transform),
          context.provide_transform(model.transform.value),
          context.provide_scale(model.transform.value.2),
        ])

      #(model, effect)
    }

    UserPannedViewport(x:, y:) ->
      case model.connection {
        Some(#(connection, _)) -> {
          let world_x =
            { x -. model.bounds.0 -. model.transform.value.0 }
            /. model.transform.value.2
          let world_y =
            { y -. model.bounds.1 -. model.transform.value.1 }
            /. model.transform.value.2

          let position = #(world_x, world_y)
          let model = Model(..model, connection: Some(#(connection, position)))
          let effect = effect.none()

          #(model, effect)
        }

        None -> {
          let #(panning, dx, dy) = drag.update(model.panning, x, y)
          use <- bool.guard(dx == 0.0 && dy == 0.0, #(
            Model(..model, panning:),
            effect.none(),
          ))

          let nx = model.transform.value.0 +. dx
          let ny = model.transform.value.1 +. dy
          let new_transform = #(nx, ny, model.transform.value.2)

          let model =
            Model(
              ..model,
              transform: prop.update(model.transform, new_transform),
              panning:,
            )

          let effect = case model.transform.state {
            Controlled -> emit_pan(new_transform)
            Unchanged | Touched ->
              effect.batch([
                set_transform(model.transform),
                context.provide_transform(model.transform.value),
                emit_pan(new_transform),
              ])
          }

          #(model, effect)
        }
      }

    UserStartedConnection(source:) -> {
      let result = {
        use handles <- result.try(dict.get(model.handles, source.node))
        use start <- result.try(dict.get(handles, source.name))

        let connection = #(source.node, source.name)
        let model = Model(..model, connection: Some(#(connection, start)))
        let effect =
          effect.batch([
            context.provide_connection(Some(connection)),
            component.set_pseudo_state("connecting"),
            add_window_mousemove_listener(),
          ])

        Ok(#(model, effect))
      }

      case result {
        Ok(update) -> update
        Error(_) -> #(model, effect.none())
      }
    }

    UserStartedPanning(x:, y:) -> {
      let model = Model(..model, panning: drag.start(x, y))
      let effect =
        effect.batch([
          add_window_mousemove_listener(),
          component.set_pseudo_state("dragging"),
        ])

      #(model, effect)
    }

    UserStoppedPanning(x:, y:) -> {
      let #(panning, effect) = drag.stop(model.panning, InertiaSimulationTicked)
      let world_x =
        { x -. model.bounds.0 -. model.transform.value.0 }
        /. model.transform.value.2
      let world_y =
        { y -. model.bounds.1 -. model.transform.value.1 }
        /. model.transform.value.2

      let effect = case model.connection {
        Some(from) ->
          effect.batch([
            emit_connection_cancel(from.0, world_x, world_y),
            component.remove_pseudo_state("connecting"),
            context.provide_connection(None),
          ])
        None ->
          effect.batch([effect, component.remove_pseudo_state("dragging")])
      }

      let model = Model(..model, panning:, connection: None)

      #(model, effect)
    }

    InertiaSimulationTicked -> {
      let #(panning, vx, vy, inertia_effect) =
        drag.tick(model.panning, InertiaSimulationTicked)

      let nx = model.transform.value.0 +. vx
      let ny = model.transform.value.1 +. vy
      let new_transform =
        transform.new(x: nx, y: ny, zoom: model.transform.value.2)

      let model =
        Model(
          ..model,
          transform: prop.update(model.transform, new_transform),
          panning:,
        )

      let effect = case model.transform.state {
        Controlled -> effect.batch([inertia_effect, emit_pan(new_transform)])
        Unchanged | Touched ->
          effect.batch([
            inertia_effect,
            set_transform(model.transform),
            context.provide_transform(model.transform.value),
            emit_pan(new_transform),
          ])
      }

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
      let new_scale = model.transform.value.2 *. zoom_factor
      let clamped_scale = case new_scale {
        s if s <. min_scale -> min_scale
        s if s >. max_scale -> max_scale
        s -> s
      }

      use <- bool.guard(clamped_scale == model.transform.value.2, #(
        model,
        effect.none(),
      ))

      // Convert mouse position to world coordinates before zoom
      let world_x = { x -. model.transform.value.0 } /. model.transform.value.2
      let world_y = { y -. model.transform.value.1 } /. model.transform.value.2

      // Calculate new translation to keep the world point under the mouse
      let nx = x -. world_x *. clamped_scale
      let ny = y -. world_y *. clamped_scale
      let new_transform = transform.new(x: nx, y: ny, zoom: clamped_scale)
      let model =
        Model(..model, transform: prop.update(model.transform, new_transform))

      let effect = case model.transform.state {
        Controlled -> emit_zoom(new_transform)
        Unchanged | Touched ->
          effect.batch([
            context.provide_scale(model.transform.value.2),
            set_transform(model.transform),
            context.provide_transform(model.transform.value),
            emit_zoom(new_transform),
          ])
      }

      #(model, effect)
    }

    ViewportReszied(bounds:) -> {
      let model = Model(..model, bounds:)
      let effect = emit_resize(bounds)

      #(model, effect)
    }
  }
}

// EFFECTS ---------------------------------------------------------------------

fn set_transform(transform: Prop(Transform)) -> Effect(Msg) {
  use _, shadow_root <- effect.before_paint
  let matrix = transform.to_css_matrix(transform.value)

  do_set_transform(shadow_root, matrix)
}

@external(javascript, "./viewport.ffi.mjs", "set_transform")
fn do_set_transform(shadow_root: Dynamic, value: String) -> Nil

fn add_window_mousemove_listener() -> Effect(Msg) {
  use dispatch <- effect.from
  let decoder = fn(msg) {
    use client_x <- decode.field("clientX", decode.float)
    use client_y <- decode.field("clientY", decode.float)

    decode.success(msg(client_x, client_y))
  }

  use event <- do_add_window_mousemove_listener(fn(event) {
    case decode.run(event, decoder(UserStoppedPanning)) {
      Ok(msg) -> dispatch(msg)
      Error(_) -> Nil
    }
  })

  case decode.run(event, decoder(UserPannedViewport)) {
    Ok(msg) -> dispatch(msg)
    Error(_) -> Nil
  }
}

@external(javascript, "./viewport.ffi.mjs", "add_window_mousemove_listener")
fn do_add_window_mousemove_listener(
  handle_mouseup: fn(Dynamic) -> Nil,
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
          cursor: grab;
          display: block;
          position: relative;
          width: 100%;
          height: 100%;
          contain: layout style paint;
          will-change: scroll-position;
      }

      :host(:state(dragging)), :host(:state(connecting)) {
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
