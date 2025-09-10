// TYPES -----------------------------------------------------------------------

pub type Prop(a) {
  Prop(value: a, state: State)
}

pub type State {
  ///
  ///
  Unchanged

  ///
  ///
  Touched

  ///
  ///
  Controlled
}

// CONSTRUCTORS -----------------------------------------------------------------

///
///
pub fn new(value: a) -> Prop(a) {
  Prop(value:, state: Unchanged)
}

///
///
pub fn controlled(value: a) -> Prop(a) {
  Prop(value:, state: Controlled)
}

/// Update the value of a prop if and only if it is uncontrolled and has not been
/// updated internally by the component (touched).
///
pub fn uncontrolled(prop: Prop(a), value: a) -> Prop(a) {
  case prop.state {
    Unchanged -> Prop(..prop, value:)
    Touched | Controlled -> prop
  }
}

///
///
pub fn update(prop: Prop(a), value: a) -> Prop(a) {
  case prop.state {
    Unchanged | Touched -> Prop(value:, state: Touched)
    Controlled -> prop
  }
}
