// IMPORTS ---------------------------------------------------------------------

import gleam/float
import lustre/effect.{type Effect}

// TYPES -----------------------------------------------------------------------

///
///
pub type DragState {
  Settled
  Active(x: Float, y: Float, vx: Float, vy: Float)
  Inertia(vx: Float, vy: Float)
}

// CONSTANTS -------------------------------------------------------------------

const friction: Float = 0.85

const min_velocity: Float = 0.2

const threshold: Float = 5.0

//

///
///
pub fn start(x: Float, y: Float) -> DragState {
  Active(x:, y:, vx: 0.0, vy: 0.0)
}

///
///
pub fn update(
  state: DragState,
  x: Float,
  y: Float,
) -> #(DragState, Float, Float) {
  case state {
    Active(..) -> {
      let dx = x -. state.x
      let dy = y -. state.y
      let vx = dx *. friction
      let vy = dy *. friction

      #(Active(x:, y:, vx:, vy:), dx, dy)
    }

    Settled | Inertia(..) -> #(start(x, y), 0.0, 0.0)
  }
}

///
///
pub fn stop(state: DragState, tick: msg) -> #(DragState, Effect(msg)) {
  case state {
    Settled | Inertia(..) -> #(Settled, effect.none())

    Active(vx:, vy:, ..) -> {
      let vx_abs = float.absolute_value(vx)
      let vy_abs = float.absolute_value(vy)
      let velocity_magnitude = vx_abs +. vy_abs

      case velocity_magnitude >. threshold {
        True -> #(Inertia(vx:, vy:), on_animation_frame(tick))
        False -> #(Settled, effect.none())
      }
    }
  }
}

///
///
pub fn tick(
  state: DragState,
  tick: msg,
) -> #(DragState, Float, Float, Effect(msg)) {
  case state {
    Inertia(vx:, vy:) -> {
      let vx = vx *. friction
      let vx_abs = float.absolute_value(vx)
      let vy = vy *. friction
      let vy_abs = float.absolute_value(vy)

      case vx_abs <. min_velocity && vy_abs <. min_velocity {
        True -> #(Settled, vx, vy, effect.none())
        False -> #(Inertia(vx:, vy:), vx, vy, on_animation_frame(tick))
      }
    }

    Active(..) | Settled -> #(state, 0.0, 0.0, effect.none())
  }
}

fn on_animation_frame(handler: msg) -> Effect(msg) {
  use dispatch, _ <- effect.after_paint

  dispatch(handler)
}
