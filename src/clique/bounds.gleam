// IMPORTS ---------------------------------------------------------------------

import gleam/dynamic/decode
import gleam/float
import gleam/json.{type Json}

// TYPES -----------------------------------------------------------------------

///
///
/// Note: for performance reasons, the `Bounds` type is a tuple rather than a
/// record. The fields are as follows:
///
/// - 0: x
/// - 1: y
/// - 2: width
/// - 3: height
///
pub type Bounds =
  #(Float, Float, Float, Float)

// CONSTRUCTORS ----------------------------------------------------------------

///
///
pub fn new(
  x x: Float,
  y y: Float,
  width width: Float,
  height height: Float,
) -> Bounds {
  #(x, y, width, height)
}

///
///
pub fn init() -> Bounds {
  #(0.0, 0.0, 0.0, 0.0)
}

///
///
pub fn decoder() -> decode.Decoder(Bounds) {
  let tuple_decoder = {
    use x <- decode.field(0, decode.float)
    use y <- decode.field(0, decode.float)
    use width <- decode.field(0, decode.float)
    use height <- decode.field(0, decode.float)

    decode.success(#(x, y, width, height))
  }

  let object_decoder = {
    use x <- decode.field("x", decode.float)
    use y <- decode.field("y", decode.float)
    use width <- decode.field("width", decode.float)
    use height <- decode.field("height", decode.float)

    decode.success(#(x, y, width, height))
  }

  decode.one_of(tuple_decoder, [object_decoder])
}

// QUERIES ---------------------------------------------------------------------

///
///
pub fn x(bounds: Bounds) -> Float {
  bounds.0
}

///
///
pub fn y(bounds: Bounds) -> Float {
  bounds.1
}

///
///
pub fn width(bounds: Bounds) -> Float {
  bounds.2
}

///
///
pub fn height(bounds: Bounds) -> Float {
  bounds.3
}

///
///
pub fn top(bounds: Bounds) -> Float {
  bounds.1
}

///
///
pub fn bottom(bounds: Bounds) -> Float {
  bounds.1 +. bounds.3
}

///
///
pub fn left(bounds: Bounds) -> Float {
  bounds.0
}

///
///
pub fn right(bounds: Bounds) -> Float {
  bounds.0 +. bounds.2
}

///
///
pub fn contains(bounds: Bounds, x: Float, y: Float) -> Bool {
  bounds.0 <=. x
  && x <=. bounds.0 +. bounds.2
  && bounds.1 <=. y
  && y <=. bounds.1 +. bounds.3
}

///
///
pub fn intersects(a: Bounds, with b: Bounds) -> Bool {
  a.0 <. b.0 +. b.2
  && a.0 +. a.2 >. b.0
  && a.1 <. b.1 +. b.3
  && a.1 +. a.3 >. b.1
}

///
///
pub fn intersection(a: Bounds, with b: Bounds) -> Result(Bounds, Nil) {
  case intersects(a, with: b) {
    True -> {
      let x1 = float.max(a.0, b.0)
      let y1 = float.max(a.1, b.1)
      let x2 = float.min(a.0 +. a.2, b.0 +. b.2)
      let y2 = float.min(a.1 +. a.3, b.1 +. b.3)

      Ok(#(x1, y1, x2 -. x1, y2 -. y1))
    }

    False -> Error(Nil)
  }
}

// MANIPULATIONS ---------------------------------------------------------------

///
///
pub fn set_x(bounds: Bounds, x: Float) -> Bounds {
  #(x, bounds.1, float.max(x, bounds.2), bounds.3)
}

///
///
pub fn set_y(bounds: Bounds, y: Float) -> Bounds {
  #(bounds.0, y, bounds.2, float.max(y, bounds.3))
}

///
///
pub fn set_width(bounds: Bounds, width: Float) -> Bounds {
  case width <. 0.0 {
    True -> #(
      bounds.0 +. width,
      bounds.1,
      float.absolute_value(width),
      bounds.3,
    )

    False -> #(bounds.0, bounds.1, width, bounds.3)
  }
}

///
///
pub fn set_height(bounds: Bounds, height: Float) -> Bounds {
  case height <. 0.0 {
    True -> #(
      bounds.0,
      bounds.1 +. height,
      bounds.2,
      float.absolute_value(height),
    )

    False -> #(bounds.0, bounds.1, bounds.2, height)
  }
}

// CONVERSIONS -----------------------------------------------------------------

///
///
pub fn to_json(bounds: Bounds) -> Json {
  json.preprocessed_array([
    json.float(bounds.0),
    json.float(bounds.1),
    json.float(bounds.2),
    json.float(bounds.3),
  ])
}
