// IMPORTS ---------------------------------------------------------------------

import clique/edge
import clique/edge_renderer
import clique/handle
import clique/node
import clique/viewport
import gleam/int
import gleam/list
import lustre
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

// MAIN ------------------------------------------------------------------------

pub fn main() {
  let app = lustre.simple(init:, update:, view:)

  let assert Ok(_) = viewport.register()
  let assert Ok(_) = node.register()
  let assert Ok(_) = edge.register()
  let assert Ok(_) = edge_renderer.register()
  let assert Ok(_) = handle.register()
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
        x: int.to_float({ i % 20 } * 300),
        y: int.to_float({ i / 20 } * 400),
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
      attribute.class("p-12 w-screen h-screen bg-gray-50"),
    ],
    [
      viewport.root(
        [attribute.class("w-full h-full bg-white rounded-lg shadow")],
        [
          edge_renderer.root(
            [],
            list.map(model.edges, fn(edge) {
              edge.root(
                [
                  edge.from(edge.source.0, edge.source.1),
                  edge.to(edge.target.0, edge.target.1),
                  edge.kind("bezier"),
                ],
                [
                  html.p(
                    [
                      attribute.class("px-1 text-xs bg-yellow-300 rounded"),
                    ],
                    [html.text(edge.source.0 <> " → " <> edge.target.0)],
                  ),
                ],
              )
            }),
          ),
          ..list.map(model.nodes, fn(node) {
            node.root(
              [
                attribute.id(node.id),
                node.initial_x(node.x),
                node.initial_y(node.y),
              ],
              [
                html.div(
                  [
                    attribute.class(
                      "flex relative items-center py-1 px-2 rounded border aspect-square",
                    ),
                  ],
                  [
                    handle.root(
                      [
                        attribute.name("input"),
                        attribute.class(
                          "absolute left-0 top-1/4 bg-black rounded-full -translate-x-1/2 size-2",
                        ),
                      ],
                      [],
                    ),
                    html.text(node.label),
                    handle.root(
                      [
                        attribute.name("output"),
                        attribute.class(
                          "absolute right-0 top-3/4 bg-black rounded-full translate-x-1/2 size-2",
                        ),
                      ],
                      [],
                    ),
                  ],
                ),
              ],
            )
          })
        ],
      ),
    ],
  )
}
