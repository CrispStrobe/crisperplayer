'use strict';
// Metadata only. Fingerprints read at most 256 KiB per track, sequentially.
const ProgressBackup = (() => {
  const invalid = text => { throw new Error(text); };
  const number = (value, min, max) => typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max;
  function parse(data) {
    if (!data || data.browserPlayer !== true || ![1, 2].includes(data.schema)) invalid('Choose a browser progress backup exported by this player. Native library backups need the native app.');
    if (!Array.isArray(data.names) || !data.names.length || data.names.length > 10000 || data.names.some(name => typeof name !== 'string' || !name.length || name.length > 4096)) invalid('Invalid track names in backup.');
    if (!Number.isInteger(data.track) || data.track < 0 || data.track >= data.names.length || !number(data.position, 0, Number.MAX_SAFE_INTEGER) || !number(data.speed, .5, 3)) invalid('Invalid playback position or speed in backup.');
    if (typeof data.title !== 'string' || data.title.length > 4096 || !Array.isArray(data.bookmarks) || data.bookmarks.length > 10000) invalid('Invalid title or bookmarks in backup.');
    const bookmarks = data.bookmarks.map(mark => {
      if (!mark || !Number.isInteger(mark.track) || mark.track < 0 || mark.track >= data.names.length || !number(mark.seconds, 0, Number.MAX_SAFE_INTEGER) || typeof mark.label !== 'string' || mark.label.length > 200) invalid('Invalid bookmark in backup.');
      return {track: mark.track, seconds: mark.seconds, label: mark.label};
    });
    if (data.schema === 2 && (data.fingerprintAlgorithm !== 'sha256-first-last-128k-v1' || !Array.isArray(data.files) || data.files.length !== data.names.length || data.files.some(file => !file || !Number.isSafeInteger(file.size) || file.size <= 0 || typeof file.fingerprint !== 'string' || !/^[a-f0-9]{64}$/.test(file.fingerprint)))) invalid('Invalid audio fingerprints in backup.');
    for (const key of ['volume', 'unmutedVolume']) if (data[key] !== undefined && !number(data[key], key === 'volume' ? 0 : Number.MIN_VALUE, 1)) invalid('Invalid volume in backup.');
    return {schema: data.schema, title: data.title, names: data.names.slice(), track: data.track, position: data.position, speed: data.speed, bookmarks, files: data.files, volume: data.volume, unmutedVolume: data.unmutedVolume};
  }
  async function fingerprint(blob) {
    if (!globalThis.crypto?.subtle) invalid('This browser cannot verify audio fingerprints. Open the player over HTTPS in a current browser.');
    const size = 128 * 1024;
    const head = new Uint8Array(await blob.slice(0, size).arrayBuffer());
    const tail = new Uint8Array(await blob.slice(Math.max(size, blob.size - size)).arrayBuffer());
    const bytes = new Uint8Array(head.length + tail.length);
    bytes.set(head); bytes.set(tail, head.length);
    const digest = await crypto.subtle.digest('SHA-256', bytes);
    return {size: blob.size, fingerprint: [...new Uint8Array(digest)].map(value => value.toString(16).padStart(2, '0')).join('')};
  }
  async function fingerprints(tracks, report = () => {}) {
    const result = [];
    for (let index = 0; index < tracks.length; index++) {
      report(index + 1, tracks.length);
      result.push(await fingerprint(tracks[index].blob));
    }
    return result;
  }
  async function trackDuration(blob) {
    const probe = new Audio(); probe.preload = 'metadata'; probe.muted = true;
    const url = URL.createObjectURL(blob);
    try {
      return await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('Timed out reading a track. Check that this browser supports the original audio.')), 15000);
        const finish = (error, value) => { clearTimeout(timer); error ? reject(error) : resolve(value); };
        probe.onloadedmetadata = () => Number.isFinite(probe.duration) && probe.duration > 0 ? finish(null, probe.duration) : finish(new Error('Track duration is unavailable.'));
        probe.onerror = () => finish(new Error('This browser cannot read a track needed by this backup.'));
        probe.src = url;
      });
    } finally {
      probe.onloadedmetadata = probe.onerror = null;
      probe.removeAttribute('src'); probe.load(); URL.revokeObjectURL(url);
    }
  }
  async function verify(data, names, tracks, report = () => {}) {
    if (JSON.stringify(names) !== JSON.stringify(data.names) || tracks.length !== data.names.length) invalid('The track names or order do not match this book. Add the original audio files and select that book first.');
    if (data.schema === 2) {
      const actual = await fingerprints(tracks, report);
      if (actual.some((file, index) => file.size !== data.files[index].size || file.fingerprint !== data.files[index].fingerprint)) invalid('The audio does not match this backup. This book has not been changed.');
    }
    const positions = new Map([[data.track, data.position]]);
    for (const mark of data.bookmarks) positions.set(mark.track, Math.max(positions.get(mark.track) || 0, mark.seconds));
    for (const [index, position] of positions) {
      report(index + 1, tracks.length);
      const total = await trackDuration(tracks[index].blob);
      if (position > total + .001) invalid(`Backup position exceeds the duration of track ${index + 1}. This book has not been changed.`);
    }
  }
  const markKey = mark => JSON.stringify([mark.track, mark.seconds, mark.label]);
  function mergeBookmarks(existing, incoming) {
    const result = existing.slice(), keys = new Set(existing.map(markKey));
    for (const mark of incoming) if (!keys.has(markKey(mark))) {
      keys.add(markKey(mark)); result.push({...mark, id: crypto.randomUUID()});
    }
    return result;
  }
  return {parse, fingerprints, verify, mergeBookmarks, maxBytes: 5 * 1024 * 1024};
})();
