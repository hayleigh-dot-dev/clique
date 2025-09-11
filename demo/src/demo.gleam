// IMPORTS ---------------------------------------------------------------------

import clique
import clique/edge
import clique/node
import gleam/int
import gleam/list
import gleam/string
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
  Edge(source: #(String, String), target: #(String, String))
}

const count = 100

fn init(_) -> Model {
  let nodes =
    list.range(0, count - 1)
    |> list.map(fn(i) {
      Node(
        id: "node-" <> int.to_string(i),
        x: int.to_float({ i % 10 } * 300),
        y: int.to_float({ i / 10 } * 100),
        label: "Node " <> int.to_string(i + 1),
      )
    })

  let edges =
    list.range(0, count - 2)
    |> list.map(fn(i) {
      Edge(source: #("node-" <> int.to_string(i), "output"), target: #(
        "node-" <> int.to_string({ i + 1 }),
        "input",
      ))
    })

  Model(nodes:, edges:)
}

// UPDATE ----------------------------------------------------------------------

type Msg

fn update(model: Model, _msg: Msg) -> Model {
  model
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.class("p-24 w-screen h-screen bg-gray-100"),
    ],
    [
      clique.root(
        [attribute.class("w-full h-full bg-white rounded-lg shadow-md")],
        list.map(model.edges, fn(edge) {
          let key =
            string.join(
              [edge.source.0, edge.source.1, edge.target.0, edge.target.1],
              ".",
            )

          let html =
            clique.edge(edge.source, edge.target, [edge.bezier()], [
              html.p([attribute.class("px-1 text-xs bg-yellow-300 rounded")], [
                html.text(edge.source.0 <> " → " <> edge.target.0),
              ]),
            ])

          #(key, html)
        }),
        list.map(model.nodes, fn(node) {
          let key = node.id

          let html =
            clique.node(
              node.id,
              [
                node.initial_x(node.x),
                node.initial_y(node.y),
                attribute.class("bg-pink-50 rounded border-2 border-pink-500"),
              ],
              [
                html.div(
                  [
                    attribute.class(
                      "flex relative items-center py-1 px-2 aspect-square",
                    ),
                  ],
                  [
                    clique.handle("input", [
                      attribute.class(
                        "absolute left-0 top-1/4 bg-black rounded-full -translate-x-1/2 size-2",
                      ),
                    ]),
                    html.text(node.label),
                    clique.handle("output", [
                      attribute.class(
                        "absolute right-0 top-3/4 bg-black rounded-full translate-x-1/2 size-2",
                      ),
                    ]),
                  ],
                ),
              ],
            )

          #(key, html)
        }),
      ),
    ],
  )
}
