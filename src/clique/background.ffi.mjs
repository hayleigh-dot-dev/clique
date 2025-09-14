export const uuid = () => `background-${globalThis.crypto.randomUUID()}`;

export const mod = (x, y) => x % y;
