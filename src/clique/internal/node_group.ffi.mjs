export const queue_microtask = (callback) => {
  window.queueMicrotask(callback);
}
