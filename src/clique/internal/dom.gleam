// IMPORTS ---------------------------------------------------------------------

import clique/bounds.{type Bounds}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import lustre/effect.{type Effect}
import lustre/event.{type Handler}

// TYPES -----------------------------------------------------------------------

pub type HtmlElement

// EFFECTS ---------------------------------------------------------------------

pub fn add_event_listener(
  name: String,
  decoder: Decoder(Handler(msg)),
) -> Effect(msg) {
  use dispatch, shadow_root <- effect.before_paint
  use event <- do_add_event_listener(shadow_root, name)

  case decode.run(event, decoder) {
    Ok(handler) -> {
      let _ = do_prevent_default(event, handler.prevent_default)
      let _ = do_stop_propagation(event, handler.stop_propagation)

      dispatch(handler.message)
    }
    Error(_) -> Nil
  }
}

@external(javascript, "./dom.ffi.mjs", "add_event_listener")
fn do_add_event_listener(
  shadow_root: Dynamic,
  name: String,
  callback: fn(Dynamic) -> Nil,
) -> Nil

@external(javascript, "./dom.ffi.mjs", "prevent_default")
fn do_prevent_default(event: Dynamic, yes: Bool) -> Nil

@external(javascript, "./dom.ffi.mjs", "stop_propagation")
fn do_stop_propagation(event: Dynamic, yes: Bool) -> Nil

// ELEMENT PROPERTIES ----------------------------------------------------------

@external(javascript, "./dom.ffi.mjs", "assigned_elements")
pub fn assigned_elements(_slot: HtmlElement) -> List(HtmlElement)

@external(javascript, "./dom.ffi.mjs", "nearest")
pub fn nearest(
  element: HtmlElement,
  selector: String,
) -> Result(HtmlElement, Nil)

@external(javascript, "./dom.ffi.mjs", "tag")
pub fn tag(element: HtmlElement) -> String

@external(javascript, "./dom.ffi.mjs", "text_content")
pub fn text_content(element: HtmlElement) -> String

@external(javascript, "./dom.ffi.mjs", "children")
pub fn children(element: HtmlElement) -> List(HtmlElement)

///
pub fn attribute(element: HtmlElement, name: String) -> Result(String, Nil) {
  do_attribute(element, name)
}

@external(javascript, "./dom.ffi.mjs", "get_attribute")
fn do_attribute(_element: HtmlElement, _name: String) -> Result(String, Nil)

@external(javascript, "./dom.ffi.mjs", "bounding_client_rect")
pub fn bounding_client_rect(element: HtmlElement) -> Bounds

@external(javascript, "./dom.ffi.mjs", "query_selector_all")
pub fn query_selector_all(
  element: HtmlElement,
  selector: String,
) -> List(HtmlElement)

// DECODERS --------------------------------------------------------------------

pub fn element_decoder() -> Decoder(HtmlElement) {
  use dynamic <- decode.new_primitive_decoder("HtmlElement")

  case is_element(dynamic) {
    True -> Ok(as_element(dynamic))
    False -> Error(make_fallback_element())
  }
}

@external(javascript, "./dom.ffi.mjs", "is_element")
fn is_element(_value: Dynamic) -> Bool

@external(javascript, "../../../gleam_stdlib/gleam/function.mjs", "identity")
fn as_element(_: Dynamic) -> HtmlElement

@external(javascript, "./dom.ffi.mjs", "make_fallback_element")
fn make_fallback_element() -> HtmlElement
