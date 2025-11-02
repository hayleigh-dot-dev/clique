// IMPORTS ---------------------------------------------------------------------

import clique/bounds.{type Bounds}
import clique/edge
import clique/handle.{type Handle, Handle}
import clique/internal/context
import clique/internal/dom.{type HtmlElement}
import clique/internal/drag.{type DragState}
import clique/internal/edge_lookup.{type EdgeLookup}
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
import lustre/element/keyed
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
    handles: Dict(Handle, #(Float, Float)),
    edges: EdgeLookup,
    panning: DragState,
    connection: Option(#(Handle, #(Float, Float))),
    bounds: Bounds,
    selected: Option(Selected),
  )
}

type Selected {
  Node(id: String)
  Edge(id: String)
}

type NodeResizeObserver

fn init(_) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      transform: prop.new(transform.init()),
      observer: None,
      handles: dict.new(),
      edges: edge_lookup.new(),
      panning: drag.Settled,
      connection: None,
      bounds: bounds.init(),
      selected: None,
    )

  let effect =
    effect.batch([
      context.provide_transform(model.transform.value),
      context.provide_scale(model.transform.value.2),
      context.provide_connection(None),
      set_transform(model.transform),
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
  EdgeDisconnected(from: Handle, to: Handle)
  EdgeConnected(from: Handle, to: Handle, kind: String)
  EdgeReconnected(
    prev: #(Handle, Handle),
    next: #(Handle, Handle),
    kind: String,
  )
  EdgesMounted(edges: List(#(Handle, Handle, String)))
  InertiaSimulationTicked
  NodeMounted(element: HtmlElement, id: String)
  NodeMoved(id: String, dx: Float, dy: Float)
  NodeResizeObserverStarted(observer: NodeResizeObserver)
  NodesResized(changes: List(#(String, String, Float, Float)))
  ParentSetInitialTransform(transform: Transform)
  ParentUpdatedTransform(transform: Transform)
  UserCompletedConnection
  UserPannedViewport(x: Float, y: Float)
  UserSelectedEdge(id: String)
  UserSelectedNode(id: String)
  UserStartedConnection(source: Handle)
  UserStartedPanning(x: Float, y: Float)
  UserStoppedPanning(x: Float, y: Float)
  UserZoomedViewport(client_x: Float, client_y: Float, delta: Float)
  ViewportReszied(bounds: Bounds)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    EdgeDisconnected(from:, to:) -> {
      let edges = edge_lookup.delete(model.edges, from, to)
      let model = Model(..model, edges:)
      let effect = effect.none()

      #(model, effect)
    }

    EdgeConnected(from: source, to: target, kind:) -> {
      case dict.get(model.handles, source), dict.get(model.handles, target) {
        Ok(from), Ok(to) -> {
          let edges =
            edge_lookup.insert(model.edges, source, from, target, to, kind)
          let model = Model(..model, edges:)
          let effect = effect.none()

          #(model, effect)
        }

        _, _ -> #(model, effect.none())
      }
    }

    EdgeReconnected(prev:, next:, kind:) -> {
      let edges = edge_lookup.delete(model.edges, prev.0, prev.1)

      case dict.get(model.handles, next.0), dict.get(model.handles, next.1) {
        Ok(from), Ok(to) -> {
          let edges = edge_lookup.insert(edges, next.0, from, next.1, to, kind)
          let model = Model(..model, edges:)
          let effect = effect.none()

          #(model, effect)
        }

        _, _ -> {
          let model = Model(..model, edges:)
          let effect = effect.none()

          #(model, effect)
        }
      }
    }

    EdgesMounted(edges:) -> {
      let edges =
        list.fold(edges, edge_lookup.new(), fn(edges, edge) {
          let source = edge.0
          let target = edge.1

          case edge_lookup.get(model.edges, source, target) {
            Ok(existing) ->
              edge_lookup.insert_edge(edges, source, target, existing)

            Error(_) -> {
              let from = dict.get(model.handles, edge.0)
              let to = dict.get(model.handles, edge.1)

              case from, to {
                Ok(from), Ok(to) ->
                  edge_lookup.insert(edges, edge.0, from, edge.1, to, edge.2)

                Ok(from), Error(_) ->
                  edge_lookup.insert(
                    edges,
                    edge.0,
                    from,
                    edge.1,
                    #(0.0, 0.0),
                    edge.2,
                  )

                Error(_), Ok(to) ->
                  edge_lookup.insert(
                    edges,
                    edge.0,
                    #(0.0, 0.0),
                    edge.1,
                    to,
                    edge.2,
                  )

                _, _ ->
                  edge_lookup.insert(
                    edges,
                    edge.0,
                    #(0.0, 0.0),
                    edge.1,
                    #(0.0, 0.0),
                    edge.2,
                  )
              }
            }
          }
        })

      let model = Model(..model, edges:)
      let effect = effect.none()

      #(model, effect)
    }

    NodeMounted(id: _, element:) ->
      case model.observer {
        Some(observer) -> #(model, observe_node(observer, element))
        None -> #(model, effect.none())
      }

    NodeMoved(id: node, dx:, dy:) -> {
      let handles =
        dict.fold(model.handles, dict.new(), fn(handles, key, position) {
          case key.node == node {
            True ->
              dict.insert(handles, key, #(position.0 +. dx, position.1 +. dy))
            False -> dict.insert(handles, key, position)
          }
        })

      let edges = edge_lookup.update_node(model.edges, node, #(dx, dy))
      let model = Model(..model, handles:, edges:)
      let effect = effect.none()

      #(model, effect)
    }

    NodesResized(changes:) -> {
      let #(handles, edges) =
        list.fold(changes, #(model.handles, model.edges), fn(acc, change) {
          let position = #(
            { change.2 -. model.transform.value.0 } /. model.transform.value.2,
            { change.3 -. model.transform.value.1 } /. model.transform.value.2,
          )

          let handle = Handle(change.0, change.1)
          let handles = dict.insert(acc.0, handle, position)
          let edges = edge_lookup.update(acc.1, handle, position)

          #(handles, edges)
        })

      let model = Model(..model, handles:, edges:)
      let effect = effect.none()

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

    UserSelectedEdge(id:) -> {
      let model = Model(..model, selected: Some(Edge(id:)))
      let effect = effect.none()

      #(model, effect)
    }

    UserSelectedNode(id:) -> {
      let model = Model(..model, selected: Some(Node(id:)))
      let effect = effect.none()

      #(model, effect)
    }

    UserStartedConnection(source:) -> {
      case dict.get(model.handles, source) {
        Ok(from) -> {
          let model = Model(..model, connection: Some(#(source, from)))
          let effect =
            effect.batch([
              context.provide_connection(Some(#(source.node, source.name))),
              component.set_pseudo_state("connecting"),
              add_window_mousemove_listener(),
            ])

          #(model, effect)
        }

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
            emit_connection_cancel(
              #({ from.0 }.node, { from.0 }.name),
              world_x,
              world_y,
            ),
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
  let handle_slotchange = {
    use target <- decode.field("target", dom.element_decoder())
    let assigned_elements = dom.assigned_elements(target)
    let edges =
      list.filter_map(assigned_elements, fn(element) {
        use from <- result.try(dom.attribute(element, "from"))
        use to <- result.try(dom.attribute(element, "to"))
        let kind = dom.attribute(element, "type") |> result.unwrap("bezier")

        case string.split(from, " "), string.split(to, " ") {
          [from_node, from_name], [to_node, to_name]
            if from_node != ""
            && from_name != ""
            && to_node != ""
            && to_name != ""
          -> Ok(#(Handle(from_node, from_name), Handle(to_node, to_name), kind))

          _, _ -> Error(Nil)
        }
      })

    decode.success(EdgesMounted(edges))
  }

  let #(positions, edges) =
    edge_lookup.fold(model.edges, #([], []), fn(acc, key, edge) {
      let edges = [
        #(
          key,
          svg.path([
            attribute("d", edge.path),
            attribute("fill", "none"),
            attribute("stroke", "black"),
            attribute("stroke-width", "2"),
            attribute("shape-rendering", "geometricPrecision"),
            attribute("stroke-linecap", "round"),
            attribute("stroke-linejoin", "round"),
            attribute("vector-effect", "non-scaling-stroke"),
          ]),
        ),
        ..acc.1
      ]

      // There's probably a better way than rendering a whole bunch of style
      // tags.
      let positions = [
        #(key, {
          html.style(
            [],
            "::slotted(clique-edge[from=\""
              <> edge.source.node
              <> " "
              <> edge.source.name
              <> "\"][to=\""
              <> edge.target.node
              <> " "
              <> edge.target.name
              <> "\"]) { --cx: "
              <> float.to_string(edge.cx)
              <> "px; --cy: "
              <> float.to_string(edge.cy)
              <> "px; }",
          )
        }),
        ..acc.0
      ]

      #(positions, edges)
    })

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

      slot[name=\"edges\"] {
        display: none;
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
      component.named_slot(
        "edges",
        [
          event.on("slotchange", handle_slotchange),
          edge.on_connect(EdgeConnected),
          edge.on_disconnect(EdgeDisconnected),
          edge.on_reconnect(EdgeReconnected),
        ],
        [],
      ),

      keyed.fragment(positions),

      view_viewport([
        keyed.namespaced(
          svg.namespace,
          "svg",
          [
            attribute("width", "100%"),
            attribute("height", "100%"),
            attribute("shape-rendering", "geometricPrecision"),
            attribute.styles([
              #("overflow", "visible"),
              #("position", "absolute"),
              #("top", "0"),
              #("left", "0"),
              #("will-change", "transform"),
              #("pointer-events", "none"),
            ]),
          ],
          edges,
        ),

        component.default_slot(
          [
            node.on_mount(NodeMounted),
            node.on_change(NodeMoved),
            node.on_select(UserSelectedNode),
            handle.on_connection_start(UserStartedConnection),
            handle.on_connection_complete(fn(_, _) { UserCompletedConnection }),
          ],
          [],
        ),

        case model.connection {
          Some(#(handle, end)) ->
            view_connection_line(model.handles, handle, end)
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

    let ignore =
      dom.nearest(target, "[data-clique-disable~=\"drag\"]")
      |> result.lazy_or(fn() { dom.nearest(target, "[slot=\"overlay\"]") })
      |> result.is_ok

    case ignore {
      True -> failure
      False -> success
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
  handles: Dict(Handle, #(Float, Float)),
  handle: Handle,
  to: #(Float, Float),
) -> Element(msg) {
  case dict.get(handles, handle) {
    Ok(from) -> {
      let #(path, _, _) =
        path.bezier(from.0, from.1, position.Right, to.0, to.1, position.Left)

      html.svg([attribute.id("connection-line")], [
        svg.path([
          attribute("d", path),
          attribute("fill", "none"),
          attribute("stroke", "#000"),
          attribute("stroke-width", "2"),
        ]),
      ])
    }

    Error(_) -> element.none()
  }
}
