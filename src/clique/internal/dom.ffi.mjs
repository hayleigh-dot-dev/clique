import { List, Empty, Ok, Error } from "../../gleam.mjs";
import { BoundingClientRect } from "./dom.mjs";

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

  return new BoundingClientRect(
    rect.x,
    rect.y,
    rect.width,
    rect.height,
    rect.top,
    rect.right,
    rect.bottom,
    rect.left,
  );
};

export const query_selector_all = (element, selector) =>
  List.fromArray(Array.from(element.querySelectorAll(selector)));

//

export const is_event = (dynamic) => dynamic instanceof Event;

//
