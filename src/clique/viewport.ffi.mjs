import { List } from "../gleam.mjs";

export const add_resize_observer = (shadow_root, callback) => {
  const viewportRef = new WeakRef(shadow_root.querySelector("#viewport"));

  const observer = new ResizeObserver((entries) => {
    const updates = [];
    const viewport = viewportRef.deref();

    if (!viewport) return;

    const viewportRect = viewport.getBoundingClientRect();
    const scaleX = viewportRect.width / (viewport.clientWidth || 1);
    const scaleY = viewportRect.height / (viewport.clientHeight || 1);

    for (const entry of entries) {
      const node = entry.target.getAttribute("id");

      console.log({ target: entry.target, node });
      if (!node) continue;

      for (const handle of entry.target.querySelectorAll("clique-handle")) {
        const name = handle.getAttribute("name");
        console.log({ handle, name });

        if (!name) continue;

        const bounds = handle.getBoundingClientRect();
        const cx = bounds.left + bounds.width / 2;
        const cy = bounds.top + bounds.height / 2;
        const x = (cx - viewportRect.left) / scaleX;
        const y = (cy - viewportRect.top) / scaleY;

        updates.push([node, name, x, y]);
      }
    }

    callback(List.fromArray(updates));
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
