import { List } from "../gleam.mjs";

export const add_resize_observer = (shadow_root, callback) => {
  const viewportRef = new WeakRef(shadow_root.querySelector("#viewport"));

  let rafId = null;
  let pendingUpdates = new Map();

  const processUpdates = () => {
    const viewport = viewportRef.deref();
    if (!viewport || pendingUpdates.size === 0) return;

    const viewportRect = viewport.getBoundingClientRect();
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

export const add_window_mousemove_listener = (callback) => {
  window.addEventListener("mousemove", callback);
  window.addEventListener(
    "mouseup",
    () => window.removeEventListener("mousemove", callback),
    { once: true },
  );
};
