// IMPORTS ---------------------------------------------------------------------

import clique/internal/events
import clique/internal/path
import clique/viewport
import gleam/dict.{type Dict}
import gleam/float
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre
import lustre/attribute.{type Attribute, attribute}
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element, element}
import lustre/element/html
import lustre/element/keyed
import lustre/element/svg

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
) -> #(Float, Float, Element(msg)) {
  case kind {
    "bezier" -> path.bezier(from, to)
    "step" -> path.step(from, to)
    "linear" | _ -> path.linear(from, to)
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
  [viewport.on_handles_change(ParentProvidedHandles)]
}

// UPDATE ----------------------------------------------------------------------

pub opaque type Msg {
  ParentProvidedHandles(handles: Dict(String, #(Float, Float)))
  EdgeChanged(
    prev: Option(#(String, String)),
    next: Option(#(String, String, String)),
  )
  EdgesMounted(edges: List(#(String, String, String)))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ParentProvidedHandles(handles) -> {
      let model = Model(..model, handles: handles)
      #(model, effect.none())
    }

    EdgeChanged(prev: Some(prev), next: None) -> {
      let edges = dict.delete(model.edges, prev)
      let model = Model(..model, edges:)

      #(model, effect.none())
    }

    EdgeChanged(prev: None, next: Some(next)) -> {
      let edges = dict.insert(model.edges, #(next.0, next.1), next.2)
      let model = Model(..model, edges:)

      #(model, effect.none())
    }

    EdgeChanged(prev: Some(prev), next: Some(next)) -> {
      let edges = dict.delete(model.edges, prev)
      let edges = dict.insert(edges, #(next.0, next.1), next.2)
      let model = Model(..model, edges:)

      #(model, effect.none())
    }

    EdgeChanged(prev: None, next: None) -> #(model, effect.none())

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
    #(Float, Float, Element(Msg)),
) -> Element(Msg) {
  let #(positions, edges) =
    dict.fold(model.edges, #([], []), fn(acc, edge, kind) {
      case dict.get(model.handles, edge.0), dict.get(model.handles, edge.1) {
        Ok(from), Ok(to) -> {
          let key = edge.0 <> "-" <> edge.1
          let #(cx, cy, path) = to_path(kind, from, to)
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
      [events.on_edge_change(EdgeChanged), events.on_edges_mount(EdgesMounted)],
      [],
    ),
  ])
}
