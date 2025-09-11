// IMPORTS ---------------------------------------------------------------------

import clique/edge
import clique/edge_renderer
import clique/handle
import clique/node
import clique/viewport
import gleam/result
import lustre
import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/element/keyed

// TYPES -----------------------------------------------------------------------

///
///
pub type Transform =
  viewport.Transform

// COMPONENTS ------------------------------------------------------------------

///
///
pub fn register() -> Result(Nil, lustre.Error) {
  use _ <- result.try(edge.register())
  use _ <- result.try(edge_renderer.register())
  use _ <- result.try(handle.register())
  use _ <- result.try(node.register())
  use _ <- result.try(viewport.register())

  Ok(Nil)
}

// ELEMENTS --------------------------------------------------------------------

///
///
pub fn root(
  attributes: List(Attribute(msg)),
  edges: List(#(String, Element(msg))),
  nodes: List(#(String, Element(msg))),
) -> Element(msg) {
  viewport.root(attributes, [
    keyed.element(edge_renderer.tag, [], edges),
    keyed.fragment(nodes),
  ])
}

///
///
pub fn node(
  id: String,
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  node.root([attribute.id(id), ..attributes], children)
}

///
///
pub fn handle(name: String, attributes: List(Attribute(msg))) -> Element(msg) {
  handle.root([attribute.name(name), ..attributes], [])
}

///
///
pub fn edge(
  source: #(String, String),
  target: #(String, String),
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  edge.root(
    [edge.from(source.0, source.1), edge.to(target.0, target.1), ..attributes],
    children,
  )
}
