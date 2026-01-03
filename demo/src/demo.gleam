// IMPORTS ---------------------------------------------------------------------

import clique
import clique/background
import clique/bounds.{type Bounds}
import clique/edge
import clique/handle.{type Handle, Handle}
import clique/node
import clique/transform.{type Transform, FitOptions}
import gleam/int
import gleam/list
import gleam/option.{Some}
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

// MAIN ------------------------------------------------------------------------

pub fn main() {
  let app = lustre.application(init:, update:, view:)

  let assert Ok(_) = clique.register()
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(
    nodes: List(Node),
    edges: List(Edge),
    viewport: Bounds,
    transform: Transform,
  )
}

type Node {
  Node(id: String, x: Float, y: Float, label: String)
}

type Edge {
  Edge(id: String, source: Handle, target: Handle)
}

const count = 450

const columns = 10

fn init(_) -> #(Model, Effect(Msg)) {
  let nodes =
    list.range(0, count - 1)
    |> list.map(fn(i) {
      Node(
        id: "node-" <> int.to_string(i),
        x: int.to_float({ i % columns } * 100),
        y: int.to_float({ i / columns } * 100),
        label: "Node " <> int.to_string(i),
      )
    })

  let edges =
    list.range(0, count / 4)
    |> list.map(fn(_) {
      let source_index = int.random(count - 1)
      let target_index = int.random(count - 1)

      Edge(
        id: "edge-"
          <> int.to_string(source_index)
          <> "-"
          <> int.to_string(target_index),
        source: Handle("node-" <> int.to_string(source_index), "output"),
        target: Handle("node-" <> int.to_string(target_index), "input"),
      )
    })

  let model =
    Model(nodes:, edges:, viewport: bounds.init(), transform: transform.init())
  let effect = measure_clique_viewport()

  #(model, effect)
}

fn measure_clique_viewport() -> Effect(Msg) {
  use dispatch, _ <- effect.before_paint()
  let bounds = do_measure_clique_viewport()

  dispatch(ViewportChangedSize(bounds))
}

@external(javascript, "./demo.ffi.mjs", "measure_clique_viewport")
fn do_measure_clique_viewport() -> Bounds

// UPDATE ----------------------------------------------------------------------

type Msg {
  UserClickedShuffle
  UserConnectedNodes(source: Handle, target: Handle)
  UserDraggedNode(id: String, x: Float, y: Float)
  UserDroppedConnection(source: Handle, x: Float, y: Float)
  UserPannedViewport(transform: Transform)
  ViewportChangedSize(Bounds)
  UserPannedUp
  UserPannedLeft
  UserPannedRight
  UserPannedDown
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserClickedShuffle -> {
      let nodes =
        list.map(model.nodes, fn(node) {
          Node(
            ..node,
            x: int.to_float(int.random(2000)),
            y: int.to_float(int.random(2000)),
          )
        })

      // let transform = fit(model.viewport, nodes)

      let model = Model(..model, nodes:)
      let effect = effect.none()

      #(model, effect)
    }

    UserConnectedNodes(source:, target:) -> {
      let id = "edge-" <> source.node <> "-" <> target.node
      let edges = [Edge(id:, source:, target:), ..model.edges]

      let model = Model(..model, edges:)
      let effect = effect.none()

      #(model, effect)
    }

    UserDraggedNode(id:, x:, y:) -> {
      let nodes =
        list.map(model.nodes, fn(node) {
          case node.id == id {
            True -> Node(..node, x:, y:)
            False -> node
          }
        })

      let model = Model(..model, nodes:)
      let effect = effect.none()

      #(model, effect)
    }

    UserDroppedConnection(source:, x:, y:) -> {
      let id = int.to_string(list.length(model.nodes) + 1)
      let node = Node(id: "node-" <> id, x:, y:, label: "Node " <> id)
      let edges = [
        Edge(
          id: "edge-" <> source.node <> "-" <> node.id,
          source:,
          target: Handle(node.id, "input"),
        ),
        ..model.edges
      ]
      let model = Model(..model, nodes: [node, ..model.nodes], edges:)
      let effect = effect.none()

      #(model, effect)
    }

    UserPannedDown -> #(
      Model(..model, transform: transform.pan(model.transform, 0.0, 50.0)),
      effect.none(),
    )

    UserPannedLeft -> #(
      Model(..model, transform: transform.pan(model.transform, -50.0, 0.0)),
      effect.none(),
    )

    UserPannedRight -> #(
      Model(..model, transform: transform.pan(model.transform, 50.0, 0.0)),
      effect.none(),
    )

    UserPannedUp -> #(
      Model(..model, transform: transform.pan(model.transform, 0.0, -50.0)),
      effect.none(),
    )

    UserPannedViewport(transform:) -> {
      let model = Model(..model, transform:)
      let effect = effect.none()

      #(model, effect)
    }

    ViewportChangedSize(viewport) -> {
      let model =
        Model(..model, viewport:, transform: fit(viewport, model.nodes))
      let effect = effect.none()

      #(model, effect)
    }
  }
}

fn fit(viewport: Bounds, nodes: List(Node)) -> Transform {
  transform.fit_with(
    box: list.fold(nodes, bounds.init(), fn(bounds, node) {
      bounds.extend(bounds, bounds.new(node.x, node.y, 100.0, 100.0))
    }),
    into: viewport,
    options: FitOptions(
      padding: #(10.0, 10.0),
      max_zoom: Some(2.0),
      min_zoom: Some(0.5),
    ),
  )
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("w-screen h-screen font-mono")], [
    clique.root(
      [
        clique.initial_transform(model.transform),
        clique.on_resize(ViewportChangedSize),
        // clique.on_pan(UserPannedViewport),
        // clique.on_zoom(UserPannedViewport),
        clique.on_connection_cancel(UserDroppedConnection),
        attribute.class("w-full h-full bg-white rounded-lg shadow-md"),
        handle.on_connection_complete(UserConnectedNodes),
      ],
      [
        clique.background([
          background.lines(),
          attribute.class("text-pink-100 bg-slate-50"),
          background.gap(50.0, 50.0),
        ]),

        clique.background([
          background.dots(),
          attribute.class("text-pink-200"),
          background.size(2.0),
          background.gap(50.0, 50.0),
        ]),

        clique.nodes({
          use Node(id:, ..) as data <- list.map(model.nodes)
          let key = id
          let html = view_node(data, on_drag: UserDraggedNode)

          #(key, html)
        }),

        clique.edges({
          use Edge(id:, ..) as data <- list.map(model.edges)
          let key = id
          let html = view_edge(data)

          #(key, html)
        }),
        html.div([clique.overlay(), attribute.class("absolute top-8 left-8")], [
          html.button(
            [
              event.on_click(UserClickedShuffle),
              attribute.class(
                "py-2 px-4 text-white bg-blue-500 rounded shadow hover:bg-blue-600 active:translate-y-px",
              ),
            ],
            [html.text("Shuffle Nodes")],
          ),
        ]),

        html.div(
          [
            clique.overlay(),
            attribute.class("absolute right-8 bottom-8"),
            attribute.class("grid grid-cols-3 grid-rows-3 gap-1"),
            attribute.class(
              "*:size-6 *:bg-white *:rounded *:shadow *:active:translate-y-px",
            ),
          ],
          [
            html.button(
              [event.on_click(UserPannedUp), attribute.class("col-start-2")],
              [html.text("↑")],
            ),
            html.button(
              [event.on_click(UserPannedLeft), attribute.class("row-start-2")],
              [html.text("←")],
            ),
            html.button(
              [
                event.on_click(UserPannedRight),
                attribute.class("col-start-3 row-start-2"),
              ],
              [
                html.text("→"),
              ],
            ),
            html.button(
              [
                event.on_click(UserPannedDown),
                attribute.class("col-start-2 row-start-3"),
              ],
              [
                html.text("↓"),
              ],
            ),
          ],
        ),
      ],
    ),
  ])
}

fn view_node(
  data: Node,
  on_drag handle_drag: fn(String, Float, Float) -> msg,
) -> Element(msg) {
  let attributes = [
    node.position(data.x, data.y),
    node.on_drag(fn(id, x, y, _, _) { handle_drag(id, x, y) }),
    attribute.class("bg-pink-50 rounded border-2 border-pink-500"),
  ]

  clique.node(data.id, attributes, [
    html.div([attribute.class("flex relative items-center py-1 px-2 size-16")], [
      clique.handle("input", [
        attribute.class("absolute -left-1 top-1/4 bg-black rounded-full size-2"),
      ]),
      html.text(data.label),
      clique.handle("output", [
        attribute.class(
          "absolute -right-1 top-3/4 bg-black rounded-full size-2",
        ),
      ]),
    ]),
  ])
}

fn view_edge(data: Edge) -> Element(msg) {
  clique.edge(data.source, data.target, [edge.linear()], [
    html.p([attribute.class("px-1 text-xs bg-yellow-300 rounded")], [
      html.text(data.source.node <> " → " <> data.target.node),
    ]),
  ])
}
