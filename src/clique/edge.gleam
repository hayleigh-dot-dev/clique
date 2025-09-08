// IMPORTS ---------------------------------------------------------------------

import clique/internal/handles.{type Handles}
import clique/viewport
import gleam/float
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre
import lustre/attribute.{type Attribute, attribute}
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element, element}
import lustre/element/html
import lustre/element/svg

// COMPONENT -------------------------------------------------------------------

const tag: String = "clique-edge"

///
///
pub fn register_defaults() -> Result(Nil, lustre.Error) {
  use _ <- result.try(lustre.register(
    lustre.component(
      init:,
      update:,
      view: view(_, fn(from, to) {
        view_svg([
          svg.line([
            attribute("x1", float.to_string(from.0)),
            attribute("y1", float.to_string(from.1)),
            attribute("x2", float.to_string(to.0)),
            attribute("y2", float.to_string(to.1)),
            attribute("stroke", "black"),
            attribute("stroke-width", "2"),
          ]),
        ])
      }),
      options: options(),
    ),
    tag <> "-linear",
  ))

  use _ <- result.try(lustre.register(
    lustre.component(
      init:,
      update:,
      view: view(_, fn(from, to) {
        view_svg([
          svg.path([
            attribute("d", create_bezier_path(from, to)),
            attribute("stroke", "black"),
            attribute("fill", "none"),
            attribute("stroke-width", "2"),
          ]),
        ])
      }),
      options: options(),
    ),
    tag <> "-bezier",
  ))

  use _ <- result.try(lustre.register(
    lustre.component(
      init:,
      update:,
      view: view(_, fn(from, to) {
        view_svg([
          svg.path([
            attribute("d", create_orthogonal_path(from, to)),
            attribute("stroke", "black"),
            attribute("fill", "none"),
            attribute("stroke-width", "2"),
          ]),
        ])
      }),
      options: options(),
    ),
    tag <> "-orthogonal",
  ))

  Ok(Nil)
}

///
///
pub fn register(
  name: String,
  path: fn(#(Float, Float), #(Float, Float)) -> Element(Msg),
) -> Result(Nil, lustre.Error) {
  lustre.register(
    lustre.component(init:, update:, view: view(_, path), options: options()),
    tag <> "-custom-" <> name,
  )
}

// ELEMENTS --------------------------------------------------------------------

///
///
pub fn linear(attributes: List(Attribute(msg))) -> Element(msg) {
  element(tag <> "-linear", attributes, [])
}

pub fn bezier(attributes: List(Attribute(msg))) -> Element(msg) {
  element(tag <> "-bezier", attributes, [])
}

pub fn orthogonal(attributes: List(Attribute(msg))) -> Element(msg) {
  element(tag <> "-orthogonal", attributes, [])
}

pub fn custom(
  name: String,
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  element(tag <> "-custom-" <> name, attributes, children)
}

// ATTRIBUTES ------------------------------------------------------------------

pub fn from(node: String, name: String) -> Attribute(msg) {
  attribute("from", node <> "." <> name)
}

pub fn to(node: String, name: String) -> Attribute(msg) {
  attribute("to", node <> "." <> name)
}

// EVENTS ----------------------------------------------------------------------

// MODEL -----------------------------------------------------------------------

type Model {
  Model(handles: Handles, from: Option(Handle), to: Option(Handle))
}

type Handle {
  Handle(node: String, name: String)
}

fn init(_) -> #(Model, Effect(Msg)) {
  let model = Model(handles: handles.new(), from: None, to: None)
  let effect = effect.none()

  #(model, effect)
}

fn options() -> List(component.Option(Msg)) {
  [
    viewport.on_handles_change(ParentProvidedHandles),

    component.on_attribute_change("from", fn(value) {
      case value |> string.trim |> string.split(".") {
        [node, name] if name != "" ->
          Ok(ParentSetFrom(Some(Handle(node:, name:))))
        _ -> Ok(ParentSetFrom(None))
      }
    }),

    component.on_attribute_change("to", fn(value) {
      case value |> string.trim |> string.split(".") {
        [node, name] if name != "" ->
          Ok(ParentSetTo(Some(Handle(node:, name:))))
        _ -> Ok(ParentSetTo(None))
      }
    }),
  ]
}

// UPDATE ----------------------------------------------------------------------

pub opaque type Msg {
  ParentProvidedHandles(handles: Handles)
  ParentSetFrom(Option(Handle))
  ParentSetTo(Option(Handle))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ParentProvidedHandles(handles) -> #(Model(..model, handles:), effect.none())
    ParentSetFrom(from) -> #(Model(..model, from:), effect.none())
    ParentSetTo(to) -> #(Model(..model, to:), effect.none())
  }
}

// VIEW ------------------------------------------------------------------------

fn view(
  model: Model,
  path: fn(#(Float, Float), #(Float, Float)) -> Element(Msg),
) -> Element(Msg) {
  case model.from, model.to {
    Some(from), Some(to) -> {
      let result = {
        use from <- result.try(handles.get(model.handles, from.node, from.name))
        use to <- result.try(handles.get(model.handles, to.node, to.name))

        Ok(#(from, to))
      }

      case result {
        Ok(#(from, to)) -> path(from, to)
        Error(_) -> element.none()
      }
    }
    _, _ -> element.none()
  }
}

// PATH CALCULATION HELPERS ----------------------------------------------------

fn create_bezier_path(from: #(Float, Float), to: #(Float, Float)) -> String {
  let dx = to.0 -. from.0
  let control_point1 = #(from.0 +. dx /. 3.0, from.1)
  let control_point2 = #(from.0 +. dx *. 2.0 /. 3.0, to.1)

  "M"
  <> float.to_string(from.0)
  <> ","
  <> float.to_string(from.1)
  <> "C"
  <> float.to_string(control_point1.0)
  <> ","
  <> float.to_string(control_point1.1)
  <> ","
  <> float.to_string(control_point2.0)
  <> ","
  <> float.to_string(control_point2.1)
  <> ","
  <> float.to_string(to.0)
  <> ","
  <> float.to_string(to.1)
}

fn create_orthogonal_path(from: #(Float, Float), to: #(Float, Float)) -> String {
  let mid_x = from.0 +. { to.0 -. from.0 } /. 2.0

  "M"
  <> float.to_string(from.0)
  <> ","
  <> float.to_string(from.1)
  <> "L"
  <> float.to_string(mid_x)
  <> ","
  <> float.to_string(from.1)
  <> "L"
  <> float.to_string(mid_x)
  <> ","
  <> float.to_string(to.1)
  <> "L"
  <> float.to_string(to.0)
  <> ","
  <> float.to_string(to.1)
}

fn view_svg(children: List(Element(Msg))) -> Element(Msg) {
  html.svg(
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
    children,
  )
}
