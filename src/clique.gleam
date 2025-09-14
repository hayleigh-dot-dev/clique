// IMPORTS ---------------------------------------------------------------------

import clique/background
import clique/edge
import clique/handle
import clique/internal/edge_renderer
import clique/node
import clique/viewport
import gleam/result
import lustre
import lustre/attribute.{type Attribute}
import lustre/component
import lustre/element.{type Element}
import lustre/element/keyed

// COMPONENTS ------------------------------------------------------------------

///
///
pub fn register() -> Result(Nil, lustre.Error) {
  use _ <- result.try(background.register())
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
  children: List(Element(msg)),
) -> Element(msg) {
  viewport.root(attributes, children)
}

///
///
pub fn background(attributes: List(Attribute(msg))) -> Element(msg) {
  background.root([component.slot("background"), ..attributes], [])
}

///
///
pub fn edges(all: List(#(String, Element(msg)))) -> Element(msg) {
  keyed.element(edge_renderer.tag, [], all)
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

///
///
pub fn nodes(all: List(#(String, Element(msg)))) -> Element(msg) {
  keyed.fragment(all)
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
