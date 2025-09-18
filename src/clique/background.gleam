// IMPORTS ---------------------------------------------------------------------

import clique/internal/context
import clique/internal/number
import clique/transform.{type Transform}
import gleam/dynamic/decode
import gleam/float
import gleam/json
import gleam/list
import gleam/string
import lustre
import lustre/attribute.{type Attribute, attribute}
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element, element}
import lustre/element/html
import lustre/element/svg

// COMPONENT -------------------------------------------------------------------

///
///
pub const tag: String = "clique-background"

///
///
pub fn register() -> Result(Nil, lustre.Error) {
  lustre.register(
    lustre.component(init:, update:, view:, options: options()),
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

// ATTRIBUTES ------------------------------------------------------------------

///
///
pub type Pattern {
  Dots
  Lines
}

///
///
pub fn pattern(value: Pattern) -> Attribute(msg) {
  attribute("pattern", case value {
    Dots -> "dots"
    Lines -> "lines"
  })
}

///
///
pub fn dots() -> Attribute(msg) {
  pattern(Dots)
}

///
///
pub fn lines() -> Attribute(msg) {
  pattern(Lines)
}

///
///
pub fn gap(x: Float, y: Float) -> Attribute(msg) {
  case lustre.is_browser() {
    True ->
      attribute.property("gap", {
        json.object([#("x", json.float(x)), #("y", json.float(y))])
      })

    False -> attribute("gap", float.to_string(x) <> " " <> float.to_string(y))
  }
}

///
///
pub fn size(value: Float) -> Attribute(msg) {
  case lustre.is_browser() {
    True -> attribute.property("size", json.float(value))
    False -> attribute("size", float.to_string(value))
  }
}

///
///
pub fn offset(x: Float, y: Float) -> Attribute(msg) {
  case lustre.is_browser() {
    True ->
      attribute.property("offset", {
        json.object([#("x", json.float(x)), #("y", json.float(y))])
      })

    False ->
      attribute("offset", float.to_string(x) <> " " <> float.to_string(y))
  }
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(
    id: String,
    pattern: Pattern,
    transform: Transform,
    gap: #(Float, Float),
    scaled_gap: #(Float, Float),
    size: Float,
    scaled_size: Float,
    offset: #(Float, Float),
    scaled_offset: #(Float, Float),
  )
}

fn init(_) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      id: make_id(),
      pattern: Dots,
      transform: transform.init(),
      gap: #(20.0, 20.0),
      scaled_gap: #(20.0, 20.0),
      size: 1.0,
      scaled_size: 1.0,
      offset: #(0.0, 0.0),
      scaled_offset: #(0.0, 0.0),
    )
  let effect = effect.none()

  #(model, effect)
}

@external(javascript, "./background.ffi.mjs", "uuid")
fn make_id() -> String

fn options() -> List(component.Option(Msg)) {
  [
    component.adopt_styles(False),

    component.on_attribute_change("pattern", fn(value) {
      case string.trim(value) {
        "dots" -> Ok(ParentSetPattern(value: Dots))
        "lines" -> Ok(ParentSetPattern(value: Lines))
        _ -> Error(Nil)
      }
    }),

    component.on_attribute_change("gap", fn(value) {
      case string.split(value, " ") |> list.map(string.trim) {
        [gap] ->
          case number.parse(gap) {
            Ok(value) -> Ok(ParentSetGap(x: value, y: value))
            Error(_) -> Error(Nil)
          }

        [gap_x, gap_y] ->
          case number.parse(gap_x), number.parse(gap_y) {
            Ok(x), Ok(y) -> Ok(ParentSetGap(x:, y:))
            _, _ -> Error(Nil)
          }

        _ -> Error(Nil)
      }
    }),

    component.on_property_change("gap", {
      use x <- decode.field("x", decode.float)
      use y <- decode.field("y", decode.float)

      decode.success(ParentSetGap(x:, y:))
    }),

    component.on_attribute_change("offset", fn(value) {
      case string.split(value, " ") |> list.map(string.trim) {
        [offset] ->
          case number.parse(offset) {
            Ok(value) -> Ok(ParentSetOffset(x: value, y: value))
            Error(_) -> Error(Nil)
          }

        [offset_x, offset_y] ->
          case number.parse(offset_x), number.parse(offset_y) {
            Ok(x), Ok(y) -> Ok(ParentSetOffset(x:, y:))
            _, _ -> Error(Nil)
          }

        _ -> Error(Nil)
      }
    }),

    component.on_property_change("offset", {
      use x <- decode.field("x", decode.float)
      use y <- decode.field("y", decode.float)

      decode.success(ParentSetOffset(x:, y:))
    }),

    component.on_attribute_change("size", fn(value) {
      case number.parse(value) {
        Ok(n) -> Ok(ParentSetSize(value: n))
        Error(_) -> Error(Nil)
      }
    }),

    component.on_property_change("size", {
      decode.float
      |> decode.map(ParentSetSize)
    }),

    context.on_transform_change(ViewportProvidedTransform),
  ]
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  ParentSetGap(x: Float, y: Float)
  ParentSetOffset(x: Float, y: Float)
  ParentSetPattern(value: Pattern)
  ParentSetSize(value: Float)
  ViewportProvidedTransform(transform: Transform)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ParentSetGap(x:, y:) -> {
      let gap = #(x, y)
      let scaled_gap = #(x *. model.transform.2, y *. model.transform.2)
      let model = Model(..model, gap:, scaled_gap:)
      let effect = effect.none()

      #(model, effect)
    }

    ParentSetOffset(x:, y:) -> {
      let offset = #(x, y)
      let scaled_offset = #(
        x *. model.transform.2 +. model.scaled_gap.0 /. 2.0,
        y *. model.transform.2 +. model.scaled_gap.1 /. 2.0,
      )
      let model = Model(..model, offset:, scaled_offset:)
      let effect = effect.none()

      #(model, effect)
    }

    ParentSetPattern(value:) -> {
      let model = Model(..model, pattern: value)
      let effect = effect.none()

      #(model, effect)
    }

    ParentSetSize(value:) -> {
      let size = float.max(1.0, value)
      let scaled_size = size *. model.transform.2
      let model = Model(..model, size:, scaled_size:)
      let effect = effect.none()

      #(model, effect)
    }

    ViewportProvidedTransform(transform:) -> {
      let scaled_gap = #(model.gap.0 *. transform.2, model.gap.1 *. transform.2)
      let scaled_size = model.size *. transform.2
      let scaled_offset = #(
        model.offset.0 *. transform.2 +. scaled_gap.0 /. 2.0,
        model.offset.1 *. transform.2 +. scaled_gap.1 /. 2.0,
      )
      let model =
        Model(..model, transform:, scaled_gap:, scaled_size:, scaled_offset:)
      let effect = effect.none()

      #(model, effect)
    }
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  element.fragment([
    html.style([], {
      "
      svg {
        background-color: inherit;
        position: absolute;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        overflow: visible;
        pointer-events: none;
      }

      path {
        stroke: currentcolor;
        stroke-width: 1;
      }

      circle {
        fill: currentcolor;
      }
      "
    }),

    html.svg([], [
      view_pattern(
        model.id,
        model.transform,
        model.scaled_gap,
        [
          attribute("patternTransform", case model.pattern {
            Lines ->
              "translate(-"
              <> float.to_string(model.scaled_offset.0)
              <> ", -"
              <> float.to_string(model.scaled_offset.1)
              <> ")"

            Dots ->
              "translate(-"
              <> float.to_string(
                model.scaled_offset.0 +. { model.scaled_gap.0 /. 2.0 },
              )
              <> ", -"
              <> float.to_string(
                model.scaled_offset.1 +. { model.scaled_gap.1 /. 2.0 },
              )
              <> ") translate(-"
              <> float.to_string(model.scaled_size)
              <> ", -"
              <> float.to_string(model.scaled_size)
              <> ")"
          }),
        ],
        [
          case model.pattern {
            Dots -> view_dot_pattern(model.scaled_size)
            Lines -> view_line_pattern(model.scaled_gap)
          },
        ],
      ),

      view_background(model.id),
    ]),
  ])
}

// VIEW PATTERN ----------------------------------------------------------------

fn view_pattern(
  id: String,
  transform: Transform,
  gap: #(Float, Float),
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  svg.pattern(
    [
      attribute.id(id),
      attribute("x", float.to_string(mod(transform.0, gap.0))),
      attribute("y", float.to_string(mod(transform.1, gap.1))),
      attribute("width", float.to_string(gap.0)),
      attribute("height", float.to_string(gap.1)),
      attribute("patternUnits", "userSpaceOnUse"),
      ..attributes
    ],
    children,
  )
}

@external(javascript, "./background.ffi.mjs", "mod")
fn mod(x: Float, y: Float) -> Float

fn view_dot_pattern(radius: Float) -> Element(msg) {
  svg.circle([
    attribute("cx", float.to_string(radius)),
    attribute("cy", float.to_string(radius)),
    attribute("r", float.to_string(radius)),
  ])
}

fn view_line_pattern(dimensions: #(Float, Float)) -> Element(msg) {
  let path =
    "M"
    <> float.to_string(dimensions.0 /. 2.0)
    <> " 0 V"
    <> float.to_string(dimensions.1)
    <> " M0 "
    <> float.to_string(dimensions.1 /. 2.0)
    <> " H"
    <> float.to_string(dimensions.0)

  svg.path([attribute("d", path), attribute("stroke-width", "1")])
}

// VIEW BACKGROUND -------------------------------------------------------------

fn view_background(id: String) -> Element(msg) {
  svg.rect([
    attribute("x", "0"),
    attribute("y", "0"),
    attribute("width", "100%"),
    attribute("height", "100%"),
    attribute("fill", "url(#" <> id <> ")"),
  ])
}
