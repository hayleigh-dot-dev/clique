// TYPES -----------------------------------------------------------------------

///
///
pub type Position {
  Top
  TopLeft
  TopRight
  Right
  Bottom
  BottomLeft
  BottomRight
  Left
}

// CONVERSIONS -----------------------------------------------------------------

///
///
pub fn to_string(value: Position) -> String {
  case value {
    TopLeft -> "top-left"
    Top -> "top"
    TopRight -> "top-right"
    Right -> "right"
    BottomRight -> "bottom-right"
    Bottom -> "bottom"
    BottomLeft -> "bottom-left"
    Left -> "left"
  }
}

///
///
pub fn to_side(value: Position) -> String {
  case value {
    TopLeft | Top | TopRight -> "top"
    Right -> "right"
    BottomRight | Bottom | BottomLeft -> "bottom"
    Left -> "left"
  }
}
