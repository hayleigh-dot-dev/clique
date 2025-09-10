// IMPORTS ---------------------------------------------------------------------

import clique/internal/events
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre
import lustre/attribute.{type Attribute, attribute}
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element, element}
import lustre/element/html

// COMPONENT -------------------------------------------------------------------

pub const tag: String = "clique-edge"

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

pub fn from(node: String, handle: String) -> Attribute(msg) {
  attribute("from", node <> "." <> handle)
}

pub fn to(node: String, handle: String) -> Attribute(msg) {
  attribute("to", node <> "." <> handle)
}

pub fn kind(value: String) -> Attribute(msg) {
  attribute("type", value)
}

// EVENTS ----------------------------------------------------------------------

// MODEL -----------------------------------------------------------------------

type Model {
  Model(from: Option(String), to: Option(String), kind: String)
}

fn init(_) -> #(Model, Effect(Msg)) {
  let model = Model(from: None, to: None, kind: "bezier")
  let effect = effect.none()

  #(model, effect)
}

fn options() -> List(component.Option(Msg)) {
  [
    component.on_attribute_change("from", fn(value) {
      case string.split(value, ".") {
        [node, handle] if node != "" && handle != "" ->
          Ok(ParentSetFrom(value:))
        _ -> Ok(ParentRemovedFrom)
      }
    }),

    component.on_attribute_change("to", fn(value) {
      case string.split(value, ".") {
        [node, handle] if node != "" && handle != "" -> Ok(ParentSetTo(value:))
        _ -> Ok(ParentRemovedTo)
      }
    }),

    component.on_attribute_change("type", fn(value) {
      case value {
        "" -> Ok(ParentSetType(value: "bezier"))
        _ -> Ok(ParentSetType(value:))
      }
    }),
  ]
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  ParentRemovedFrom
  ParentRemovedTo
  ParentSetFrom(value: String)
  ParentSetTo(value: String)
  ParentSetType(value: String)
}

fn update(prev: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ParentRemovedFrom -> {
      let next = Model(..prev, from: None)
      let effect =
        events.emit_edge_change(
          option.then(prev.from, fn(from) {
            option.map(prev.to, fn(to) { #(from, to) })
          }),
          None,
        )

      #(next, effect)
    }

    ParentRemovedTo -> {
      let next = Model(..prev, to: None)
      let effect =
        events.emit_edge_change(
          option.then(prev.from, fn(from) {
            option.map(prev.to, fn(to) { #(from, to) })
          }),
          None,
        )

      #(next, effect)
    }

    ParentSetFrom(value) -> {
      let next = Model(..prev, from: Some(value))
      let effect =
        events.emit_edge_change(
          option.then(prev.from, fn(from) {
            option.map(prev.to, fn(to) { #(from, to) })
          }),
          option.then(next.from, fn(from) {
            option.map(next.to, fn(to) { #(from, to, next.kind) })
          }),
        )

      #(next, effect)
    }

    ParentSetTo(value) -> {
      let next = Model(..prev, to: Some(value))
      let effect =
        events.emit_edge_change(
          option.then(prev.from, fn(from) {
            option.map(prev.to, fn(to) { #(from, to) })
          }),
          option.then(next.from, fn(from) {
            option.map(next.to, fn(to) { #(from, to, next.kind) })
          }),
        )

      #(next, effect)
    }

    ParentSetType(value) -> {
      let next = Model(..prev, kind: value)
      let effect =
        events.emit_edge_change(
          None,
          option.then(next.from, fn(from) {
            option.map(next.to, fn(to) { #(from, to, next.kind) })
          }),
        )

      #(next, effect)
    }
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  element.fragment([
    html.style([], {
      ":host {
        display: contents;
      }

      slot {
        display: inline-block;
        position: absolute;
        transform-origin: center;
        will-change: transform;
        pointer-events: auto;
      }
      "
    }),

    case model.from, model.to {
      Some(_), Some(_) -> {
        let translate_x = "var(--cx)"
        let translate_y = "var(--cy)"
        let transform =
          "translate("
          <> translate_x
          <> ", "
          <> translate_y
          <> ") translate(-50%, -50%)"

        component.default_slot([attribute.style("transform", transform)], [])
      }
      _, _ -> element.none()
    },
  ])
}
