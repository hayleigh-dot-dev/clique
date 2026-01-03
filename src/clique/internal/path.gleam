import clique/position.{
  type Position, Bottom, BottomLeft, BottomRight, Left, Right, Top, TopLeft,
  TopRight,
}
import gleam/float

//

///
///
pub fn default(
  kind: String,
  from: #(Float, Float),
  to: #(Float, Float),
) -> #(String, Float, Float) {
  case kind {
    "bezier" ->
      bezier(from.0, from.1, position.Right, to.0, to.1, position.Left)
    "step" -> step(from.0, from.1, to.0, to.1)
    "linear" | _ -> straight(from.0, from.1, to.0, to.1)
  }
}

// STRAIGHT PATH ---------------------------------------------------------------

///
///
pub fn straight(
  from_x: Float,
  from_y: Float,
  to_x: Float,
  to_y: Float,
) -> #(String, Float, Float) {
  let path =
    "M"
    <> format(from_x)
    <> ","
    <> format(from_y)
    <> " L"
    <> format(to_x)
    <> ","
    <> format(to_y)

  let label_x = float.to_precision({ from_x +. to_x } /. 2.0, 2)
  let label_y = float.to_precision({ from_y +. to_y } /. 2.0, 2)

  #(path, label_x, label_y)
}

// BEZIER PATH -----------------------------------------------------------------

///
///
pub fn bezier(
  from_x: Float,
  from_y: Float,
  from_position: Position,
  to_x: Float,
  to_y: Float,
  to_position: Position,
) -> #(String, Float, Float) {
  let curvature = 0.25

  let #(cx1, cy1) =
    bezier_control_point(from_x, from_y, from_position, to_x, to_y, curvature)

  let #(cx2, cy2) =
    bezier_control_point(to_x, to_y, to_position, from_x, from_y, curvature)

  let path =
    "M"
    <> format(from_x)
    <> ","
    <> format(from_y)
    <> "C"
    <> format(cx1)
    <> ","
    <> format(cy1)
    <> " "
    <> format(cx2)
    <> ","
    <> format(cy2)
    <> " "
    <> format(to_x)
    <> ","
    <> format(to_y)

  let label_x = from_x *. 0.125 +. cx1 *. 0.375 +. cx2 *. 0.375 +. to_x *. 0.125
  let label_y = from_y *. 0.125 +. cy1 *. 0.375 +. cy2 *. 0.375 +. to_y *. 0.125

  #(path, float.to_precision(label_x, 2), float.to_precision(label_y, 2))
}

fn bezier_control_point(
  from_x: Float,
  from_y: Float,
  from_position: Position,
  to_x: Float,
  to_y: Float,
  curvature: Float,
) -> #(Float, Float) {
  case from_position {
    TopLeft | Top | TopRight -> #(
      from_x,
      from_y -. bezier_control_point_offset(from_y -. to_y, curvature),
    )

    Right -> #(
      from_x +. bezier_control_point_offset(to_x -. from_x, curvature),
      from_y,
    )

    BottomLeft | Bottom | BottomRight -> #(
      from_x,
      from_y +. bezier_control_point_offset(to_y -. from_y, curvature),
    )

    Left -> #(
      from_x -. bezier_control_point_offset(from_x -. to_x, curvature),
      from_y,
    )
  }
}

fn bezier_control_point_offset(distance: Float, curvature: Float) -> Float {
  case distance >=. 0.0 {
    True -> 0.5 *. distance
    False -> curvature *. 25.0 *. sqrt(0.0 -. distance)
  }
}

@external(javascript, "./path.ffi.mjs", "sqrt")
fn sqrt(value: Float) -> Float

// SMOOTHSTEP PATH -------------------------------------------------------------

///
///
pub fn step(
  from_x: Float,
  from_y: Float,
  to_x: Float,
  to_y: Float,
) -> #(String, Float, Float) {
  let mid_x = float.to_precision(from_x +. { to_x -. from_x } /. 2.0, 2)
  let mid_y = float.to_precision(from_y +. { to_y -. from_y } /. 2.0, 2)
  let dx1 = mid_x -. from_x
  let dy1 = 0.0
  let dx2 = 0.0
  let dy2 = to_y -. from_y
  let dx3 = to_x -. mid_x
  let dy3 = 0.0

  let path =
    "M"
    <> format(from_x)
    <> ","
    <> format(from_y)
    <> "l"
    <> format(dx1)
    <> ","
    <> format(dy1)
    <> "l"
    <> format(dx2)
    <> ","
    <> format(dy2)
    <> "l"
    <> format(dx3)
    <> ","
    <> format(dy3)

  let label_x = mid_x
  let label_y = mid_y

  #(path, label_x, label_y)
}

// UTILS -----------------------------------------------------------------------

fn format(value: Float) -> String {
  value |> float.to_precision(2) |> float.to_string
}
