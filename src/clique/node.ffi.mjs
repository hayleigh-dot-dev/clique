export const set_css_property = (shadow_root, property, value) => {
  const host = shadow_root.host;

  if (host) {
    host.style.setProperty(property, value);
  }
};

export const add_window_mousemove_listener = (callback, handle_mouseup) => {
  window.addEventListener("mousemove", callback);
  window.addEventListener(
    "mouseup",
    () => {
      window.removeEventListener("mousemove", callback);
      handle_mouseup();
    },
    { once: true },
  );
};
