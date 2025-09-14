// IMPORTS ---------------------------------------------------------------------

import clique
import clique/background
import clique/edge
import clique/handle
import clique/node
import gleam/int
import gleam/list
import lustre
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

// MAIN ------------------------------------------------------------------------

pub fn main() {
  let app = lustre.simple(init:, update:, view:)

  let assert Ok(_) = clique.register()
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(nodes: List(Node), edges: List(Edge))
}

type Node {
  Node(id: String, x: Float, y: Float, label: String)
}

type Edge {
  Edge(id: String, source: #(String, String), target: #(String, String))
}

const count = 50

fn init(_) -> Model {
  let nodes =
    list.range(0, count - 1)
    |> list.map(fn(i) {
      Node(
        id: "node-" <> int.to_string(i),
        x: int.to_float({ i % 2 } * 300),
        y: int.to_float({ i / 2 } * 100),
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
        source: #("node-" <> int.to_string(source_index), "output"),
        target: #("node-" <> int.to_string(target_index), "input"),
      )
    })

  Model(nodes:, edges:)
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  NodeDragged(id: String, x: Float, y: Float)
  UserConnectedNodes(source: #(String, String), target: #(String, String))
}

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    NodeDragged(id:, x:, y:) -> {
      let nodes =
        list.map(model.nodes, fn(node) {
          case node.id == id {
            True -> Node(..node, x:, y:)
            False -> node
          }
        })

      Model(..model, nodes:)
    }

    UserConnectedNodes(source:, target:) -> {
      let id = "edge-" <> source.0 <> "-" <> target.0
      let edges = [Edge(id:, source:, target:), ..model.edges]

      Model(..model, edges:)
    }
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("p-24 w-screen h-screen font-mono")], [
    clique.root(
      [
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

        clique.edges({
          use Edge(id:, ..) as data <- list.map(model.edges)
          let key = id
          let html = view_edge(data)

          #(key, html)
        }),

        clique.nodes({
          use Node(id:, ..) as data <- list.map(model.nodes)
          let key = id
          let html = view_node(data, on_drag: NodeDragged)

          #(key, html)
        }),
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
    html.div(
      [attribute.class("flex relative items-center py-1 px-2 aspect-square")],
      [
        clique.handle("input", [
          attribute.class(
            "absolute -left-1 top-1/4 bg-black rounded-full size-2",
          ),
        ]),
        html.text(data.label),
        clique.handle("output", [
          attribute.class(
            "absolute -right-1 top-3/4 bg-black rounded-full size-2",
          ),
        ]),
      ],
    ),
  ])
}

fn view_edge(data: Edge) -> Element(msg) {
  clique.edge(data.source, data.target, [edge.bezier()], [
    html.p([attribute.class("px-1 text-xs bg-yellow-300 rounded")], [
      html.text(data.source.0 <> " → " <> data.target.0),
    ]),
  ])
}
