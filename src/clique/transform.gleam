// IMPORTS ---------------------------------------------------------------------

import clique/bounds.{type Bounds}
import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/json.{type Json}
import gleam/option.{type Option, None}

// TYPES -----------------------------------------------------------------------

///
///
/// Note: for performance reasons, the `Transform` type is a tuple rather than a
/// record. The fields are as follows:
///
/// - 0: x
/// - 1: y
/// - 2: zoom
///
/// Prefer using the [`new`](#new) function for constructing `Transform` values
/// and the [`x`](#x), [`y`](#y), and [`zoom`](#zoom) functions for accessing
/// them.
///
pub type Transform =
  #(Float, Float, Float)

///
///
pub type FitOptions {
  FitOptions(
    padding: #(Float, Float),
    max_zoom: Option(Float),
    min_zoom: Option(Float),
  )
}

// CONSTRUCTORS ----------------------------------------------------------------

///
///
pub fn new(x x: Float, y y: Float, zoom zoom: Float) -> Transform {
  #(x, y, zoom)
}

///
///
pub fn init() -> Transform {
  #(0.0, 0.0, 1.0)
}

///
///
pub fn decoder() -> Decoder(Transform) {
  let tuple_decoder = {
    use x <- decode.field(0, decode.float)
    use y <- decode.field(1, decode.float)
    use zoom <- decode.field(2, decode.float)

    decode.success(#(x, y, zoom))
  }

  let object_decoder = {
    use x <- decode.field("x", decode.float)
    use y <- decode.field("y", decode.float)
    use zoom <- decode.field("zoom", decode.float)

    decode.success(#(x, y, zoom))
  }

  decode.one_of(tuple_decoder, [object_decoder])
}

pub fn fit(into viewport: Bounds, box box: Bounds) -> Transform {
  fit_with(
    viewport,
    box,
    FitOptions(padding: #(0.0, 0.0), min_zoom: None, max_zoom: None),
  )
}

pub fn fit_with(
  into viewport: Bounds,
  box box: Bounds,
  options options: FitOptions,
) -> Transform {
  let scale_x = { viewport.2 -. options.padding.0 *. 2.0 } /. box.2
  let scale_y = { viewport.3 -. options.padding.1 *. 2.0 } /. box.3
  let unclamped_scale = float.min(scale_x, scale_y)

  let min_scale = option.unwrap(options.min_zoom, unclamped_scale)
  let max_scale = option.unwrap(options.max_zoom, unclamped_scale)
  let scale = float.max(min_scale, float.min(max_scale, unclamped_scale))

  let scaled_box_width = box.2 *. scale
  let scaled_box_height = box.3 *. scale

  let center_x = { viewport.2 -. scaled_box_width } /. 2.0
  let center_y = { viewport.3 -. scaled_box_height } /. 2.0

  let translate_x = center_x -. { box.0 *. scale }
  let translate_y = center_y -. { box.1 *. scale }

  #(translate_x, translate_y, scale)
}

// QUERIES ---------------------------------------------------------------------

///
///
pub fn x(transform: Transform) -> Float {
  transform.0
}

///
///
pub fn y(transform: Transform) -> Float {
  transform.1
}

///
///
pub fn zoom(transform: Transform) -> Float {
  transform.2
}

// CONVERSIONS -----------------------------------------------------------------

///
///
pub fn to_css_translate(transform: Transform) -> String {
  "translate("
  <> float.to_string(transform.0)
  <> "px, "
  <> float.to_string(transform.1)
  <> "px) scale("
  <> float.to_string(transform.2)
  <> ")"
}

///
///
pub fn to_css_translate2d(transform: Transform) -> String {
  "translate("
  <> float.to_string(transform.0)
  <> "px, "
  <> float.to_string(transform.1)
  <> "px)"
}

///
///
pub fn to_css_matrix(transform: Transform) -> String {
  "matrix("
  <> float.to_string(transform.2)
  <> ", 0, 0, "
  <> float.to_string(transform.2)
  <> ", "
  <> float.to_string(transform.0)
  <> ", "
  <> float.to_string(transform.1)
  <> ")"
}

///
///
pub fn to_json(transform: Transform) -> Json {
  json.preprocessed_array([
    json.float(transform.0),
    json.float(transform.1),
    json.float(transform.2),
  ])
}

///
///
pub fn to_string(transform: Transform) -> String {
  float.to_string(transform.0)
  <> " "
  <> float.to_string(transform.1)
  <> " "
  <> float.to_string(transform.2)
}
