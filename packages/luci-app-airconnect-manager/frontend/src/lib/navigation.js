/** Resolve the in-app page from a URL hash, including legacy route links. */
export function modeFromLocation(location) {
  return location.hash === '#settings' || /\/settings\/?$/.test(location.pathname)
    ? 'settings'
    : 'overview';
}
