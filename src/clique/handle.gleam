// IMPORTS ---------------------------------------------------------------------

import lustre
import lustre/attribute.{type Attribute}
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element, element}
import lustre/element/html

// COMPONENT -------------------------------------------------------------------

pub const tag: String = "clique-handle"

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

// EVENTS ----------------------------------------------------------------------

// MODEL -----------------------------------------------------------------------

type Model {
  Model
}

fn init(_) -> #(Model, Effect(Msg)) {
  let model = Model
  let effect = effect.none()

  #(model, effect)
}

fn options() -> List(component.Option(Msg)) {
  []
}

// UPDATE ----------------------------------------------------------------------

type Msg

fn update(model: Model, _msg: Msg) -> #(Model, Effect(Msg)) {
  #(model, effect.none())
}

// VIEW ------------------------------------------------------------------------

fn view(_) -> Element(Msg) {
  component.default_slot([], [
    html.div([], []),
  ])
}
