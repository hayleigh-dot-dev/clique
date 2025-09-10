// IMPORTS ---------------------------------------------------------------------

import gleam/float
import lustre/attribute.{attribute}
import lustre/element.{type Element}
import lustre/element/svg

// ELEMENTS --------------------------------------------------------------------

pub fn linear(
  from: #(Float, Float),
  to: #(Float, Float),
) -> #(Float, Float, Element(msg)) {
  let mid_x = from.0 +. { to.0 -. from.0 } /. 2.0
  let mid_y = from.1 +. { to.1 -. from.1 } /. 2.0

  #(mid_x, mid_y, {
    svg.line([
      attribute("x1", float.to_string(from.0)),
      attribute("y1", float.to_string(from.1)),
      attribute("x2", float.to_string(to.0)),
      attribute("y2", float.to_string(to.1)),
      attribute("stroke", "black"),
      attribute("stroke-width", "2"),
    ])
  })
}

pub fn bezier(
  from: #(Float, Float),
  to: #(Float, Float),
) -> #(Float, Float, Element(msg)) {
  let dx = to.0 -. from.0
  let control_point1 = #(from.0 +. dx /. 3.0, from.1)
  let control_point2 = #(from.0 +. dx *. 2.0 /. 3.0, to.1)

  // Calculate midpoint of bezier curve
  // For cubic bezier, the midpoint (t=0.5) can be calculated using the formula:
  // B(0.5) = (1-0.5)^3 * P0 + 3*(1-0.5)^2*0.5 * P1 + 3*(1-0.5)*0.5^2 * P2 + 0.5^3 * P3
  // Which simplifies to:
  // B(0.5) = 0.125*P0 + 0.375*P1 + 0.375*P2 + 0.125*P3
  let mid_x =
    0.125
    *. from.0
    +. 0.375
    *. control_point1.0
    +. 0.375
    *. control_point2.0
    +. 0.125
    *. to.0

  let mid_y =
    0.125
    *. from.1
    +. 0.375
    *. control_point1.1
    +. 0.375
    *. control_point2.1
    +. 0.125
    *. to.1

  let path =
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

  #(mid_x, mid_y, {
    svg.path([
      attribute("d", path),
      attribute("fill", "none"),
      attribute("stroke", "black"),
      attribute("stroke-width", "2"),
    ])
  })
}

pub fn step(
  from: #(Float, Float),
  to: #(Float, Float),
) -> #(Float, Float, Element(msg)) {
  let mid_x = from.0 +. { to.0 -. from.0 } /. 2.0
  let mid_y = from.1 +. { to.1 -. from.1 } /. 2.0

  let path =
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

  #(mid_x, mid_y, {
    svg.path([
      attribute("d", path),
      attribute("fill", "none"),
      attribute("stroke", "black"),
      attribute("stroke-width", "2"),
    ])
  })
}
