/**
 * Every string the page shows about state, in one place.
 *
 * The product rule this module encodes: service running, discovered, AirPlay
 * broadcast and playback are four different facts, each from its own source, and
 * a fact that was not measured renders as unknown - never as a positive, and
 * never as a negative either. Keeping the wording here (instead of inline in
 * JSX) means the LuCI test suite can assert the contract directly, without a
 * DOM, and a component can only render what this module decides.
 *
 * `createPresentation(t)` takes the translation helper (`_` in LuCI).
 */

export function createPresentation(t) {
  const _ =
    typeof t === 'function'
      ? t
      : function (s) {
          return s;
        };

  /** A status value, or the "not provided" placeholder. */
  function value(input) {
    return input == null || input === '' ? _('Not provided') : String(input);
  }

  /** Seconds since the epoch, as the browser's locale string. */
  function time(seconds) {
    if (!seconds) return _('Not provided');
    const date = new Date(Number(seconds) * 1000);
    return isNaN(date.getTime()) ? _('Not provided') : date.toLocaleString();
  }

  /** The engine's human name. */
  function engineLabel(engine) {
    return engine === 'cast' ? _('Chromecast') : _('UPnP / DLNA');
  }

  // --- the service process ------------------------------------------------
  // This is the process only. Broadcasting is a separate fact with its own row,
  // so a running process can never be read as an AirPlay advertisement.

  function serviceLabel(service) {
    if (!service || !service.enabled) return _('Disabled');
    if (service.running === true) return _('Running');
    if (service.running === false) return _('Stopped');
    return _('Unknown');
  }

  function serviceTone(service) {
    return service && service.running === true ? 'positive' : 'neutral';
  }

  // --- discovery ----------------------------------------------------------

  function onlineLabel(online) {
    if (online === true) return _('Discovered');
    if (online === false) return _('Not currently discovered');
    return _('Discovery unknown');
  }

  function onlineTone(online) {
    return online === true ? 'positive' : 'neutral';
  }

  // --- AirPlay broadcast --------------------------------------------------
  // A measurement with three states: true (advertised), false (measured, not
  // advertised) and null (not measured). The null state must say so.

  /**
   * The one three-state label for a broadcast measurement. Device badges and
   * the diagnostics rows both use it, so the same fact never appears under
   * three different names ("advertised", "unknown", "not measured").
   */
  function broadcastStatus(broadcasting) {
    if (broadcasting === true) return _('Broadcasting');
    if (broadcasting === false) return _('Not broadcasting');
    return _('Unknown');
  }

  function deviceBroadcastBadge(broadcasting) {
    return {
      label: _('AirPlay') + ': ' + broadcastStatus(broadcasting),
      tone: broadcasting === true ? 'positive' : 'neutral',
    };
  }

  /**
   * The observation time is one mDNS scan shared by both engines, so it is one
   * row, not a suffix repeated on every engine's status.
   */
  function broadcastCheckedAt(observedAt) {
    return observedAt ? _('Last broadcast check') + ': ' + time(observedAt) : null;
  }

  /** The failure reason of that shared scan, or null when it completed. */
  function broadcastError(error) {
    return error ? _('Last check error') + ': ' + error : null;
  }

  // --- playback -----------------------------------------------------------
  // Playback is not measurable through the documented upstream surface. It is
  // its own row with its own reason, and is never derived from the broadcast
  // row, so a positive broadcast cannot read as playback.

  function playbackText(data) {
    const playback = (data && data.playback) || {};
    if (playback.known === true && playback.playing === true) return _('Playing');
    if (playback.known === true && playback.playing === false) return _('Not playing');
    return _(
      'Unknown — the engines expose no documented playback status, so this is never inferred from the broadcast state.',
    );
  }

  // --- discovery scan -----------------------------------------------------

  function scanStatus(scan) {
    const state = scan || {};
    if (state.error) return { text: _('Scan failed: ') + state.error, role: 'alert' };
    if (state.running) return { text: _('Discovery is in progress.'), role: 'status' };
    if (state.last_scan) return { text: _('Last scan: ') + time(state.last_scan), role: 'status' };
    return { text: _('No scan has been completed.'), role: 'status' };
  }

  function scanDisabled(scan, services) {
    const state = scan || {};
    const engines = services || {};
    return (
      !!state.running ||
      !((engines.upnp && engines.upnp.enabled) || (engines.cast && engines.cast.enabled))
    );
  }

  return {
    value,
    time,
    engineLabel,
    serviceLabel,
    serviceTone,
    onlineLabel,
    onlineTone,
    deviceBroadcastBadge,
    broadcastStatus,
    broadcastCheckedAt,
    broadcastError,
    playbackText,
    scanStatus,
    scanDisabled,
  };
}
