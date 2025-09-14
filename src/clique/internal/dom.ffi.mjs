import { List, Empty, Ok, Error } from "../../gleam.mjs";

//

export const is_element = (dynamic) => dynamic instanceof HTMLElement;

export const get_attribute = (element, key) => {
  if (element.hasAttribute(key)) {
    return new Ok(element.getAttribute(key));
  } else {
    return new Error(undefined);
  }
};

//

export const make_fallback_element = () => document.createElement("div");

export const assigned_elements = (slot) => {
  if (slot instanceof HTMLSlotElement) {
    return List.fromArray(Array.from(slot.assignedElements()));
  } else {
    return new Empty();
  }
};

export const tag = (element) => element.localName;

export const text_content = (element) => element.textContent;

export const children = (element) =>
  List.fromArray(Array.from(element.children));

export const bounding_client_rect = (element) => {
  const rect = element.getBoundingClientRect();

  return [rect.x, rect.y, rect.width, rect.height];
};

export const query_selector_all = (element, selector) =>
  List.fromArray(Array.from(element.querySelectorAll(selector)));

//

export const is_event = (dynamic) => dynamic instanceof Event;

//

export const add_event_listener = (shadow_root, name, handler) => {
  const host = shadow_root.host;

  if (host) {
    host.addEventListener(name, handler);
  }
};

export const prevent_default = (event, yes) => {
  if (yes) event.preventDefault();
};

export const stop_propagation = (event, yes) => {
  if (yes) event.stopPropagation();
};
