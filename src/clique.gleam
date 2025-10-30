// IMPORTS ---------------------------------------------------------------------

import clique/background
import clique/bounds.{type Bounds}
import clique/edge
import clique/handle.{type Handle}
import clique/internal/edge_renderer
import clique/internal/viewport
import clique/node
import clique/transform.{type Transform}
import gleam/result
import lustre
import lustre/attribute.{type Attribute}
import lustre/component
import lustre/element.{type Element}
import lustre/element/keyed

// COMPONENTS ------------------------------------------------------------------

/// Register the custom elements used by clique. This must be called before you
/// can render the viewport or any other clique element.
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

/// Render the main viewport. This is a pannable and zoomable container for nodes
/// and edges.
///
pub fn root(
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  viewport.root(attributes, children)
}

/// Render a patterned [background](https://hexdocs.pm/clique/clique/background.html)
/// for the graph.
///
pub fn background(attributes: List(Attribute(msg))) -> Element(msg) {
  background.root([component.slot("background"), ..attributes], [])
}

/// A container for all the [edges](#edge) in the graph. Children of this element
/// should be a keyed list of [`edge`](#edge) elements where every key is unique.
///
///
pub fn edges(all: List(#(String, Element(msg)))) -> Element(msg) {
  keyed.element(edge_renderer.tag, [], all)
}

/// An [edge](https://hexdocs.pm/clique/clique/edge.html) connects two nodes together.
/// The source and target parameters are tuples containing the id of a node in
/// the graph and the name of one of its handles.
///
/// Children of the edge element will be rendered as _labels_ on the edge and
/// automatically placed at the midpoint of the edge's path.
///
/// > Note: The `edge` element must be a child of the [`edges`](#edges) container
/// > to be rendered.
///
pub fn edge(
  source: Handle,
  target: Handle,
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  edge.root(
    [
      edge.from(source.node, source.name),
      edge.to(target.node, target.name),
      ..attributes
    ],
    children,
  )
}

/// A container for all the [nodes](#node) in the graph. Children of this element
/// should be a keyed list of [`node`](#node) elements where every key is a unique
/// id.
///
pub fn nodes(all: List(#(String, Element(msg)))) -> Element(msg) {
  keyed.fragment(all)
}

/// A node is a draggable element in the graph. By rendering one or more [handles](#handle)
/// inside the node, you can create connection points to form edges between nodes.
///
pub fn node(
  id: String,
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  node.root([attribute.id(id), ..attributes], children)
}

/// A handle is a connection point on a node that edges can connect to. Handles
/// must have a unique name within the node they belong to
///
pub fn handle(name: String, attributes: List(Attribute(msg))) -> Element(msg) {
  handle.root([attribute.name(name), ..attributes], [])
}

// ATTRIBUTES ------------------------------------------------------------------

/// Set the "transform" of the viewport. This is how you can control the pan and
/// zoom state of the clique canvas: a positive `x` transform will pan the viewport
/// to the left as all the elements are moved right and a positive `y` transform
/// will pan the viewport to the right as all the elements are moved down.
///
/// > Note: setting this attribute will place the viewport in a "controlled" state.
/// > This means the transform value is entirely owned by your application and
/// > must be updated in order for the viewport to pan. If you want the viewport
/// > to remain interactive, you should listen to the [`on_pan`](#on_pan) and
/// > [`on_zoom`](#on_zoom) events.
///
pub fn transform(value: Transform) -> Attribute(msg) {
  viewport.transform(value)
}

///
///
/// > Note: setting this attribute will only affect the transform of the viewport
/// > when it _first renders_. Subsequent changes to this attribute will have no
/// > effect.
///
pub fn initial_transform(value: Transform) -> Attribute(msg) {
  viewport.initial_transform(value)
}

/// Use this attribute to overlay an element over the top of the viewport. This
/// is suitable for elements like controls that should remain fixed in place
/// while the rest of the viewport pans and zooms.
///
pub fn overlay() -> Attribute(msg) {
  viewport.overlay()
}

// EVENTS ----------------------------------------------------------------------

/// This event is emit whenever the user pans the viewport. If your application
/// controls the [`transform`](#transform) of the viewport you must listen to
/// this event if you want to support panning.
///
pub fn on_pan(handler: fn(Transform) -> msg) -> Attribute(msg) {
  viewport.on_pan(handler)
}

/// This event is emit whenever the user zooms the viewport in or out. If your
/// application controls the [`transform`](#transform) of the viewport you must
/// listen to this event if you want to support zooming.
///
pub fn on_zoom(handler: fn(Transform) -> msg) -> Attribute(msg) {
  viewport.on_zoom(handler)
}

///
///
pub fn on_resize(handler: fn(Bounds) -> msg) -> Attribute(msg) {
  viewport.on_resize(handler)
}

///
///
pub fn on_connection_start(handler: fn(Handle) -> msg) -> Attribute(msg) {
  handle.on_connection_start(handler)
}

///
///
pub fn on_connection_cancel(
  handler: fn(Handle, Float, Float) -> msg,
) -> Attribute(msg) {
  viewport.on_connection_cancel(handler)
}

///
///
pub fn on_connection_complete(
  handler: fn(Handle, Handle) -> msg,
) -> Attribute(msg) {
  handle.on_connection_complete(handler)
}
