export const appEvents = new EventTarget();

export function emitAppEvent(type, detail) {
  appEvents.dispatchEvent(new CustomEvent(type, { detail }));
}
