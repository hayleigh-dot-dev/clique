export const measure_clique_viewport = () => {
  const viewport = document.querySelector("clique-viewport");

  if (!viewport) return [0, 0, 0, 0];

  const bounds = viewport.getBoundingClientRect();

  return [bounds.x, bounds.y, bounds.width, bounds.height];
};
