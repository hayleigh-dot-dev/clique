// IMPORTS ---------------------------------------------------------------------

import clique
import clique/edge
import clique/handle
import clique/node
import clique/viewport
import gleam/float
import gleam/list
import lustre
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/keyed

// MAIN ------------------------------------------------------------------------

pub fn main() {
  let app = lustre.simple(init:, update:, view:)

  let assert Ok(_) = viewport.register()
  let assert Ok(_) = node.register()
  let assert Ok(_) = edge.register_defaults()
  let assert Ok(_) = handle.register()
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(nodes: List(Node), edges: List(Edge))
}

type Node {
  Node(id: String, x: Float, y: Float, params: NodeParams)
}

type NodeParams {
  Osc(frequency: Float, kind: String)
  Amp(gain: Float)
}

type Edge =
  #(String, String, String, String)

fn init(_) -> Model {
  let nodes = [
    Node(id: "a", x: 0.0, y: 200.0, params: Osc(frequency: 440.0, kind: "sine")),
    Node(id: "b", x: 250.0, y: 250.0, params: Amp(gain: 0.2)),
    Node(
      id: "c",
      x: -200.0,
      y: 50.0,
      params: Osc(frequency: 20.0, kind: "sine"),
    ),
  ]
  let edges = [#("a", "out", "b", "in"), #("c", "out", "a", "freq")]

  Model(nodes:, edges:)
}

// UPDATE ----------------------------------------------------------------------

type Msg

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    _ -> model
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  viewport.root([attribute.class("w-screen h-screen")], [
    keyed.fragment({
      use edge <- list.map(model.edges)
      let key = edge.0 <> "-" <> edge.1 <> "-" <> edge.2 <> "-" <> edge.3
      let html = case float.random() {
        n if n <. 0.5 ->
          edge.orthogonal([edge.from(edge.0, edge.1), edge.to(edge.2, edge.3)])
        _ -> edge.bezier([edge.from(edge.0, edge.1), edge.to(edge.2, edge.3)])
      }

      #(key, html)
    }),

    keyed.fragment({
      use node <- list.map(model.nodes)
      let html = view_node(node.id, node.x, node.y, node.params)

      #(node.id, html)
    }),
  ])
}

fn view_node(id: String, x: Float, y: Float, params: NodeParams) -> Element(Msg) {
  node.root(
    [
      attribute.id(id),
      node.initial_x(x),
      node.initial_y(y),
      attribute.class("flex flex-col bg-white shadow *:px-2 *:py-2"),
    ],
    case params {
      Osc(..) -> [
        html.header([attribute.class("bg-pink-50 rounded-t")], [
          html.p([attribute.class("font-semibold text-pink-500")], [
            html.text("Oscillator"),
          ]),
        ]),
        html.div([], [
          html.label([], [
            html.p([attribute.class("flex gap-1 items-center")], [
              handle.root(
                [
                  attribute.name("freq"),
                  attribute.class("-ml-3 bg-pink-500 rounded-full size-2"),
                ],
                [],
              ),

              html.text("Freq"),
            ]),

            html.input([
              attribute.type_("range"),
              attribute.min("20"),
              attribute.max("2000"),
              attribute.value(float.to_string(params.frequency)),
              attribute.class("w-full"),
              node.nodrag(),
            ]),
          ]),
        ]),
        html.footer([], [
          html.p([attribute.class("flex gap-1 justify-end items-center")], [
            html.text("Out"),

            handle.root(
              [
                attribute.name("out"),
                attribute.class("-mr-3 bg-pink-500 rounded-full size-2"),
              ],
              [],
            ),
          ]),
        ]),
      ]

      Amp(..) -> [
        html.header([attribute.class("bg-green-50 rounded-t")], [
          html.p([attribute.class("font-semibold text-green-500")], [
            html.text("Oscillator"),
          ]),
        ]),
        html.div([], [
          html.p([attribute.class("flex gap-1 items-center")], [
            handle.root(
              [
                attribute.name("in"),
                attribute.class("-ml-3 bg-green-500 rounded-full size-2"),
              ],
              [],
            ),

            html.text("In"),
          ]),

          html.label([], [
            html.p([attribute.class("flex gap-1 items-center")], [
              handle.root(
                [
                  attribute.name("gain"),
                  attribute.class("-ml-3 bg-green-500 rounded-full size-2"),
                ],
                [],
              ),

              html.text("Gain"),
            ]),

            html.input([
              attribute.type_("range"),
              attribute.min("0"),
              attribute.max("1"),
              attribute.step("0.01"),
              attribute.value(float.to_string(params.gain)),
              attribute.class("w-full"),
              node.nodrag(),
            ]),
          ]),
        ]),
        html.footer([], [
          html.p([attribute.class("flex gap-1 justify-end items-center")], [
            html.text("Out"),
            handle.root(
              [
                attribute.name("out"),
                attribute.class("-mr-3 bg-green-500 rounded-full size-2"),
              ],
              [],
            ),
          ]),
        ]),
      ]
    },
  )
}
