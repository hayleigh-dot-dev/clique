export const set_transform = (shadow_root, value) => {
  const host = shadow_root.host;

  if (host) {
    host.style.transform = value;
  }
};

export const add_window_mousemove_listener = (callback, handle_mouseup) => {
  const style = document.createElement("style");

  style.textContent = `
    * {
      user-select: none !important;
      -webkit-user-select: none !important;
      -moz-user-select: none !important;
      -ms-user-select: none !important;
    }
  `;

  document.head.appendChild(style);

  window.addEventListener("mousemove", callback);
  window.addEventListener(
    "mouseup",
    () => {
      document.head.removeChild(style);
      window.removeEventListener("mousemove", callback);
      handle_mouseup();
    },
    { once: true },
  );
};
