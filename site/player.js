'use strict';
const $ = id => document.getElementById(id);
const audio = $('audio');
const order = new Intl.Collator(undefined, {numeric: true, sensitivity: 'base'});
const message = text => { $('status').textContent = text; };
const duration = value => {
  const s = Math.max(0, Math.floor(Number.isFinite(value) ? value : 0));
  return s >= 3600 ? `${Math.floor(s / 3600)}:${String(Math.floor(s % 3600 / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}` : `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
};
const request = req => new Promise((resolve, reject) => {
  req.onsuccess = () => resolve(req.result);
  req.onerror = () => reject(req.error);
});
const finished = tx => new Promise((resolve, reject) => {
  tx.oncomplete = resolve;
  tx.onerror = tx.onabort = () => reject(tx.error || new Error('Storage transaction interrupted.'));
});
const database = new Promise((resolve, reject) => {
  const req = indexedDB.open('crisperplayer-browser', 1);
  req.onupgradeneeded = () => {
    req.result.createObjectStore('books', {keyPath: 'id'});
    const tracks = req.result.createObjectStore('tracks', {keyPath: 'id'});
    tracks.createIndex('bookId', 'bookId');
  };
  req.onsuccess = () => {
    req.result.onversionchange = () => req.result.close();
    resolve(req.result);
  };
  req.onerror = () => reject(req.error);
  req.onblocked = () => message('Close other CrisperPlayer tabs to update browser storage.');
});
let books = [], selected = null, tracks = [], objectUrl = null;
let loading = false, pendingPosition = 0, playWhenReady = false, generation = 0;
let lastCheckpoint = 0;
const safe = fn => (...args) => Promise.resolve().then(() => fn(...args)).catch(e => message(e.message || String(e)));

async function saveBook(book) {
  const db = await database;
  const tx = db.transaction('books', 'readwrite');
  const done = finished(tx);
  tx.objectStore('books').put(book);
  await done;
}
async function checkpoint() {
  if (!selected || loading) return;
  const book = selected;
  book.position = Number.isFinite(audio.currentTime) ? audio.currentTime : 0;
  book.speed = audio.playbackRate;
  book.volume = audio.volume;
  book.updatedAt = Date.now();
  await saveBook(book);
}
function controls() {
  for (const id of ['play', 'rewind', 'forward', 'bookmark', 'export', 'delete']) $(id).disabled = !selected || loading;
  $('previous').disabled = !selected || loading || selected.track === 0;
  $('next').disabled = !selected || loading || selected.track >= tracks.length - 1;
  $('play').textContent = audio.paused ? 'Play' : 'Pause';
}
function progress() {
  const total = Number.isFinite(audio.duration) ? audio.duration : 0;
  const pos = Number.isFinite(audio.currentTime) ? audio.currentTime : 0;
  $('seek').max = total;
  $('seek').value = pos;
  $('seek').disabled = !selected || loading || total <= 0;
  $('seek').setAttribute('aria-valuetext', `${duration(pos)} of ${duration(total)}`);
  $('elapsed').textContent = duration(pos);
  $('duration').textContent = duration(total);
}
function renderBooks() {
  const query = $('search').value.trim().toLocaleLowerCase();
  const list = $('books'); list.replaceChildren();
  for (const book of [...books].sort((a,b) => b.updatedAt - a.updatedAt)) {
    if (!book.title.toLocaleLowerCase().includes(query)) continue;
    const li = document.createElement('li'), button = document.createElement('button');
    button.textContent = `${book.title} · ${book.names.length} ${book.names.length === 1 ? 'track' : 'tracks'}`;
    button.setAttribute('aria-current', String(selected?.id === book.id));
    button.onclick = safe(() => selectBook(book.id, true));
    li.append(button); list.append(li);
  }
  $('empty').hidden = list.children.length !== 0;
  $('empty').textContent = books.length ? 'No matching books.' : 'Your next listen starts here. Add an audiobook.';
}
function renderTracks() {
  $('tracks').replaceChildren();
  if (!selected) return;
  selected.names.forEach((name, index) => {
    const li = document.createElement('li'), button = document.createElement('button');
    button.textContent = `${index + 1}. ${name}`;
    button.setAttribute('aria-current', String(index === selected.track));
    button.onclick = safe(() => switchTrack(index, 0, !audio.paused));
    li.append(button); $('tracks').append(li);
  });
}
function renderBookmarks() {
  $('bookmarks').replaceChildren();
  for (const mark of selected?.bookmarks || []) {
    const li = document.createElement('li'), button = document.createElement('button');
    button.textContent = `${mark.label || 'Bookmark'} · Track ${mark.track + 1}, ${duration(mark.seconds)}`;
    button.onclick = safe(() => switchTrack(mark.track, mark.seconds, false));
    li.append(button); $('bookmarks').append(li);
  }
}
async function switchTrack(index, position = 0, autoplay = false) {
  if (!selected || index < 0 || index >= tracks.length) return;
  await checkpoint();
  loading = true;
  audio.pause();
  selected.track = index; selected.position = position;
  pendingPosition = position; playWhenReady = autoplay;
  if (objectUrl) URL.revokeObjectURL(objectUrl);
  objectUrl = URL.createObjectURL(tracks[index].blob);
  audio.src = objectUrl;
  audio.defaultPlaybackRate = selected.speed || 1;
  audio.playbackRate = selected.speed || 1;
  audio.volume = selected.volume ?? 1;
  $('speed').value = String(audio.playbackRate);
  $('volume').value = audio.volume;
  $('title').textContent = selected.title;
  $('track-name').textContent = `Track ${index + 1} of ${tracks.length} · ${selected.names[index]}`;
  audio.load(); renderTracks(); controls(); progress();
}
async function selectBook(id, scroll = false) {
  await checkpoint();
  loading = true; audio.pause();
  const token = ++generation;
  const book = books.find(b => b.id === id);
  if (!book) return;
  const db = await database;
  const loaded = await request(db.transaction('tracks').objectStore('tracks').index('bookId').getAll(id));
  if (token !== generation) return;
  selected = book; tracks = loaded.sort((a,b) => a.index - b.index);
  // Do not checkpoint the previous audio position into the newly selected book.
  await switchTrack(book.track || 0, book.position || 0, false);
  renderBooks(); renderBookmarks();
  if (scroll) $('player').scrollIntoView({block: 'start'});
}
async function importBook(files) {
  files = [...files].filter(f => f.size > 0 && (f.type.startsWith('audio/') || /\.(m4b|m4a|mp3|flac|ogg|wav|aac|opus|aiff?|wma)$/i.test(f.name)))
    .sort((a,b) => order.compare(a.name, b.name));
  if (!files.length) throw new Error('Select an audio file, or the tracks of one book.');
  message('Saving audio in this browser…');
  const db = await database;
  const book = {id: crypto.randomUUID(), title: files[0].name.replace(/\.[^.]+$/, ''), names: files.map(f => f.name), track: 0, position: 0, speed: 1, bookmarks: [], updatedAt: Date.now()};
  const tx = db.transaction(['books', 'tracks'], 'readwrite'), done = finished(tx);
  tx.objectStore('books').put(book);
  files.forEach((file, index) => tx.objectStore('tracks').put({id: `${book.id}:${index}`, bookId: book.id, index, blob: file}));
  try { await done; } catch (e) { throw new Error(`Could not save this book. Browser storage may be full or unavailable. ${e.message}`); }
  books.push(book); await selectBook(book.id, true);
  message('Book saved in this browser. Press Play to listen.');
  navigator.storage?.persist?.().catch(() => {});
}
$('add-book').onclick = () => $('files').click();
$('files').onchange = safe(async event => {
  try { await importBook(event.target.files); } finally { event.target.value = ''; }
});
$('search').oninput = renderBooks;
$('play').onclick = safe(async () => { if (audio.paused) await audio.play(); else audio.pause(); });
$('previous').onclick = safe(() => switchTrack(selected.track - 1, 0, !audio.paused));
$('next').onclick = safe(() => switchTrack(selected.track + 1, 0, !audio.paused));
$('rewind').onclick = safe(async () => { audio.currentTime = Math.max(0, audio.currentTime - 30); await checkpoint(); progress(); });
$('forward').onclick = safe(async () => { audio.currentTime = Math.min(audio.duration || 0, audio.currentTime + 30); await checkpoint(); progress(); });
$('seek').oninput = safe(async event => { audio.currentTime = Number(event.target.value); await checkpoint(); progress(); });
$('speed').onchange = safe(async event => { audio.playbackRate = Number(event.target.value); await checkpoint(); });
$('volume').oninput = safe(async event => { audio.volume = Number(event.target.value); await checkpoint(); });
$('bookmark-form').onsubmit = safe(async event => {
  if (!selected || loading) return;
  selected.bookmarks.push({id: crypto.randomUUID(), track: selected.track, seconds: audio.currentTime, label: $('bookmark-label').value.trim()});
  $('bookmark-label').value = ''; await checkpoint(); renderBookmarks(); message('Bookmark saved.');
});
// preventDefault must run synchronously, before the safe async handler yields.
$('bookmark-form').addEventListener('submit', event => event.preventDefault());
$('export').onclick = safe(async () => {
  await checkpoint();
  const {id, title, names, track, position, speed, bookmarks} = selected;
  const url = URL.createObjectURL(new Blob([JSON.stringify({schema: 1, browserPlayer: true, id, title, names, track, position, speed, bookmarks}, null, 2)], {type: 'application/json'}));
  const link = document.createElement('a'); link.href = url; link.download = `${title.replace(/[^\p{L}\p{N} ._-]/gu, '_')}-progress.json`; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});
$('delete').onclick = safe(async () => {
  if (!selected || !confirm(`Remove “${selected.title}” from this browser? Original files are unchanged.`)) return;
  const id = selected.id;
  loading = true; audio.pause(); selected = null; tracks = []; generation++;
  if (objectUrl) { URL.revokeObjectURL(objectUrl); objectUrl = null; }
  audio.removeAttribute('src'); audio.load();
  const db = await database, tx = db.transaction(['books', 'tracks'], 'readwrite'), done = finished(tx);
  tx.objectStore('books').delete(id);
  const cursor = tx.objectStore('tracks').index('bookId').openKeyCursor(IDBKeyRange.only(id));
  cursor.onsuccess = () => { if (cursor.result) { tx.objectStore('tracks').delete(cursor.result.primaryKey); cursor.result.continue(); } };
  await done; books = books.filter(b => b.id !== id); loading = false;
  $('title').textContent = 'Choose a book'; $('track-name').textContent = 'Progress and bookmarks are saved locally.';
  renderBooks(); renderTracks(); renderBookmarks(); controls(); progress(); message('Book removed from this browser.');
});
audio.onloadedmetadata = safe(async () => {
  if (!selected) return;
  audio.currentTime = Math.max(0, Math.min(pendingPosition, Number.isFinite(audio.duration) ? audio.duration : pendingPosition));
  loading = false; controls(); progress(); await checkpoint();
  if (playWhenReady) { playWhenReady = false; await audio.play(); }
});
audio.ontimeupdate = () => { progress(); if (Date.now() - lastCheckpoint > 5000) { lastCheckpoint = Date.now(); safe(checkpoint)(); } };
audio.onplay = controls;
audio.onpause = () => { controls(); safe(checkpoint)(); };
audio.onseeked = () => { progress(); safe(checkpoint)(); };
audio.onended = safe(async () => { await checkpoint(); if (selected && selected.track + 1 < tracks.length) await switchTrack(selected.track + 1, 0, true); else controls(); });
audio.onerror = () => { if (audio.getAttribute('src')) { loading = false; controls(); message('This browser could not decode this track. Try a supported MP3/M4A/WAV file or use the native app.'); } };
document.addEventListener('visibilitychange', () => { if (document.hidden) safe(checkpoint)(); });
window.addEventListener('pagehide', () => { safe(checkpoint)(); });
$('about-open').onclick = () => $('about').showModal();
$('about-close').onclick = () => $('about').close();
if ('mediaSession' in navigator) {
  for (const [action, handler] of Object.entries({play: () => audio.play(), pause: () => audio.pause(), seekbackward: () => { audio.currentTime = Math.max(0, audio.currentTime - 30); }, seekforward: () => { audio.currentTime = Math.min(audio.duration || 0, audio.currentTime + 30); }, previoustrack: () => switchTrack(selected.track - 1, 0, true), nexttrack: () => switchTrack(selected.track + 1, 0, true)})) {
    try { navigator.mediaSession.setActionHandler(action, safe(handler)); } catch (_) { /* Browser-specific support. */ }
  }
}
$('files').disabled = true; $('add-book').disabled = true;
safe(async () => {
  const db = await database;
  books = await request(db.transaction('books').objectStore('books').getAll());
  $('files').disabled = false; $('add-book').disabled = false; renderBooks();
  if (books.length) await selectBook([...books].sort((a,b) => b.updatedAt - a.updatedAt)[0].id);
})();
