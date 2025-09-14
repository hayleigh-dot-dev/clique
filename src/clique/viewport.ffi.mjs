import { List } from "../gleam.mjs";

export const set_transform = (shadow_root, value) => {
  const viewport = shadow_root.querySelector("#viewport");

  if (viewport) {
    viewport.style.transform = value;
  }
};

export const add_resize_observer = (
  shadow_root,
  on_viewport_resize,
  callback,
) => {
  const viewportRef = new WeakRef(shadow_root.querySelector("#viewport"));

  let rafId = null;
  let pendingUpdates = new Map();
  let viewportRect;

  const viewportObserver = new ResizeObserver(([entry]) => {
    viewportRect = entry.target.getBoundingClientRect();

    on_viewport_resize([
      viewportRect.x,
      viewportRect.y,
      viewportRect.width,
      viewportRect.height,
    ]);
  });

  viewportObserver.observe(viewportRef.deref());

  const processUpdates = () => {
    const viewport = viewportRef.deref();
    if (!viewport || pendingUpdates.size === 0) return;

    const scaleX = viewportRect.width / (viewport.clientWidth || 1);
    const scaleY = viewportRect.height / (viewport.clientHeight || 1);

    const updates = [];

    for (const [node, handles] of pendingUpdates) {
      for (const handle of handles) {
        const name = handle.getAttribute("name");

        if (!name) continue;

        const bounds = handle.getBoundingClientRect();
        const cx = bounds.left + bounds.width / 2;
        const cy = bounds.top + bounds.height / 2;
        const x = (cx - viewportRect.left) / scaleX;
        const y = (cy - viewportRect.top) / scaleY;

        updates.push([node, name, x, y]);
      }
    }

    pendingUpdates.clear();

    if (updates.length > 0) {
      callback(List.fromArray(updates));
    }

    rafId = null;
  };

  const observer = new ResizeObserver((entries) => {
    for (const entry of entries) {
      const node = entry.target.getAttribute("id");

      if (!node) continue;

      const handles = entry.target.querySelectorAll("clique-handle");

      if (handles.length === 0) continue;

      pendingUpdates.set(node, Array.from(handles));
    }

    if (!rafId) {
      rafId = requestAnimationFrame(processUpdates);
    }
  });

  return observer;
};

export const observe_node = (resize_observer, node) => {
  resize_observer.observe(node);
};

export const add_window_mousemove_listener = (handle_mouseup, callback) => {
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

  let rafId = null;
  let data = null;
  let throttledCallback = (event) => {
    data = event;

    if (!rafId) {
      rafId = window.requestAnimationFrame(() => {
        callback(data);
        rafId = data = null;
      });
    }
  };

  window.addEventListener("mousemove", throttledCallback, { passive: true });
  window.addEventListener(
    "mouseup",
    () => {
      document.head.removeChild(style);
      rafId = data = null;
      window.removeEventListener("mousemove", throttledCallback);
      handle_mouseup();
    },
    { once: true },
  );
};
