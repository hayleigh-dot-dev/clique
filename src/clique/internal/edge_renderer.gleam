// IMPORTS ---------------------------------------------------------------------

import clique/edge
import clique/internal/context
import clique/internal/dom
import clique/path
import clique/position
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/float
import gleam/list
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

pub const tag: String = "clique-edge-renderer"

///
///
pub fn register(
  // to_path: fn(String, #(Float, Float), #(Float, Float)) ->
  //   #(Float, Float, Element(Msg)),
) -> Result(Nil, lustre.Error) {
  lustre.register(
    lustre.component(
      init:,
      update:,
      view: view(_, to_default_path),
      options: options(),
    ),
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

///
///
pub fn to_default_path(
  kind: String,
  from: #(Float, Float),
  to: #(Float, Float),
) -> #(String, Float, Float) {
  case kind {
    "bezier" ->
      path.bezier(from.0, from.1, position.Right, to.0, to.1, position.Left)
    "step" -> path.step(from.0, from.1, to.0, to.1)
    "linear" | _ -> path.straight(from.0, from.1, to.0, to.1)
  }
}

// ATTRIBUTES ------------------------------------------------------------------

// EVENTS ----------------------------------------------------------------------

// MODEL -----------------------------------------------------------------------

type Model {
  Model(
    edges: Dict(#(String, String), String),
    handles: Dict(String, #(Float, Float)),
  )
}

fn init(_) -> #(Model, Effect(Msg)) {
  let model = Model(edges: dict.new(), handles: dict.new())
  let effect = effect.none()

  #(model, effect)
}

fn options() -> List(component.Option(Msg)) {
  [
    component.adopt_styles(False),
    context.on_handles_change(ParentProvidedHandles),
  ]
}

// UPDATE ----------------------------------------------------------------------

pub opaque type Msg {
  ParentProvidedHandles(handles: Dict(String, #(Float, Float)))
  EdgeDisconnected(from: String, to: String)
  EdgeConnected(from: String, to: String, kind: String)
  EdgeReconnected(
    prev: #(String, String),
    next: #(String, String),
    kind: String,
  )
  EdgesMounted(edges: List(#(String, String, String)))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ParentProvidedHandles(handles) -> {
      let model = Model(..model, handles:)

      #(model, effect.none())
    }

    EdgeDisconnected(from:, to:) -> {
      let edges = dict.delete(model.edges, #(from, to))
      let model = Model(..model, edges:)

      #(model, effect.none())
    }

    EdgeConnected(from:, to:, kind:) -> {
      let edges = dict.insert(model.edges, #(from, to), kind)
      let model = Model(..model, edges:)

      #(model, effect.none())
    }

    EdgeReconnected(prev:, next:, kind:) -> {
      let edges = dict.delete(model.edges, prev)
      let edges = dict.insert(edges, next, kind)
      let model = Model(..model, edges:)

      #(model, effect.none())
    }

    EdgesMounted(edges) -> {
      let edges =
        list.fold(edges, model.edges, fn(acc, edge) {
          dict.insert(acc, #(edge.0, edge.1), edge.2)
        })

      let model = Model(..model, edges:)

      #(model, effect.none())
    }
  }
}

// VIEW ------------------------------------------------------------------------

fn view(
  model: Model,
  to_path: fn(String, #(Float, Float), #(Float, Float)) ->
    #(String, Float, Float),
) -> Element(Msg) {
  let #(positions, edges) =
    dict.fold(model.edges, #([], []), fn(acc, edge, kind) {
      case dict.get(model.handles, edge.0), dict.get(model.handles, edge.1) {
        Ok(from), Ok(to) -> {
          let key = edge.0 <> "-" <> edge.1
          let #(path, cx, cy) = to_path(kind, from, to)
          let path =
            svg.path([
              attribute("d", path),
              attribute("fill", "none"),
              attribute("stroke", "black"),
              attribute("stroke-width", "2"),
              attribute("shape-rendering", "geometricPrecision"),
              attribute("stroke-linecap", "round"),
              attribute("stroke-linejoin", "round"),
              attribute("vector-effect", "non-scaling-stroke"),
            ])
          let edges = [#(key, path), ..acc.1]

          // There's probably a better way than rendering a whole bunch of style
          // tags.
          let positions = [
            #(key, {
              html.style(
                [],
                "::slotted(clique-edge[from=\""
                  <> edge.0
                  <> "\"][to=\""
                  <> edge.1
                  <> "\"]) { --cx: "
                  <> float.to_string(cx)
                  <> "px; --cy: "
                  <> float.to_string(cy)
                  <> "px; }",
              )
            }),
            ..acc.0
          ]

          #(positions, edges)
        }
        _, _ -> acc
      }
    })

  let handle_slotchange = {
    use target <- decode.field("target", dom.element_decoder())
    let assigned_elements = dom.assigned_elements(target)
    let edges =
      list.filter_map(assigned_elements, fn(element) {
        use from <- result.try(dom.attribute(element, "from"))
        use to <- result.try(dom.attribute(element, "to"))
        let kind = dom.attribute(element, "type") |> result.unwrap("bezier")

        case string.split(from, "."), string.split(to, ".") {
          [from_node, from_handle], [to_node, to_handle]
            if from_node != ""
            && from_handle != ""
            && to_node != ""
            && to_handle != ""
          -> Ok(#(from, to, kind))
          _, _ -> Error(Nil)
        }
      })

    decode.success(EdgesMounted(edges))
  }

  element.fragment([
    html.style([], {
      ":host {
        display: contents;
      }"
    }),

    keyed.fragment(positions),

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
        edge.on_connect(EdgeConnected),
        edge.on_disconnect(EdgeDisconnected),
        edge.on_reconnect(EdgeReconnected),
        event.on("slotchange", handle_slotchange),
      ],
      [],
    ),
  ])
}
