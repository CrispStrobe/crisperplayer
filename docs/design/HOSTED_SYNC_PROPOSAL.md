# Archived hosted sync proposal (unimplemented)

> **Status:** Future hosted-backend design only. Current provider/folder progress sync is documented in [Cloud sync](../CLOUD_SYNC.md). Cloud sync and accounts are unavailable in the app. The earlier simulated sign-in UI and unused experimental engine (including custom XOR encryption) have been removed. No replacement backend is configured. Offline-first. Drift (SQLite) is the single source of truth on device. Cloud is a thin state mirror for multi-device continuity.

## 1. Goals & non-goals

**Goals**
- Resume on any device (position, speed, sleep timer prefs, finished flag).
- Roam manual bookmarks and listening history (when-we-played-what).
- Work fully offline; sync opportunistically when online.
- No audio file uploads. Library files stay local; sync only metadata + content hashes.
- End-to-end privacy: progress/bookmarks encrypted before leaving device.
- Cheap to run: custom REST, Supabase, or Firebase all work; design is backend-agnostic.

**Non-goals (v1)**
- Uploading/streaming m4b/m4a/mp3 content.
- Real-time collaborative editing / shared libraries.
- Server-side transcoding or chapter parsing.

---

## 2. Architecture — offline-first

```
Device A (Drift) ──► Sync Engine ──► Remote Store (Supabase / Firebase / custom REST)
Device B (Drift) ──► Sync Engine ──►                ▲
                                     encrypted payload, hash-matched library
```

### 2.1 Source of truth

- **Drift (`AppDatabase`) is authoritative.** Every read in UI goes through `watchAllBooks/watchBook/watchChapters/watchBookmarks/watchHistory`. Cloud never drives UI directly.
- Local writes happen immediately and are never blocked on network.
- Each mutating table carries sync metadata (see §3). A single `SyncOutbox` / dirty-flag column per row tracks what needs pushing.

### 2.2 Sync engine (on-device)

Single place: `lib/services/sync/sync_service.dart` (proposed).

Responsibilities:
- Observe Drift change streams and mark rows dirty (`updatedAtMs`, bump vector clock).
- Debounce pushes (e.g. progress: at most once per 30 s or on pause/stop/bookmark — avoids churning on the 2 s persist timer).
- Pull on: app resume/foreground, sign-in, manual pull-to-refresh, and periodic background fetch.
- Push on: dirty rows + connectivity.
- Apply remote changes into Drift inside a `batch`, preserving local deletions via tombstones.
- Expose `SyncState` (idle / syncing / offline / error / conflict) for UI badge.

Ordering: **pull then push** within one sync cycle to reduce lost-update window. All cycles are idempotent.

```text
syncCycle():
  if !signedIn or !online → return
  state = syncing
  pullRemoteSince(lastPulledAt) → mergeIntoDrift()
  pushDirtyRows()               → confirm + clear dirty
  lastPulledAt = now
  state = idle
```

No migrations should block sync: engine skips unknown fields (forward compat) and fills missing ones with defaults.

### 2.3 Backend options (pick one at build time)

| Backend | Fit | Auth | Notes |
|---------|-----|------|-------|
| **Supabase** (Postgres + Auth + Realtime) | Recommended default | Supabase Auth (email/magic link/OAuth) + RLS per `user_id` | `supabase_flutter` SDK; Realtime for push-to-pull. Tiny bill. |
| **Firebase** (Firestore + Auth) | Good if already on Firebase | Firebase Auth | Firestore offline cache duplicates Drift — disable it and use Drift; or use only for transport. |
| **Custom REST** | Cheapest / self-host | JWT (issue on sign-in), refresh tokens | Any Postgres/MySQL + row per entity; implement `GET /sync/pull?since=` + `POST /sync/push`. Easiest to keep private. |

Interface behind `SyncRemote` so switching does not touch Drift code.

### 2.4 Large audio files — hash, don't upload

- On import, compute `sha256` (already have `crypto: ^3.0.3`) + `sizeBytes` + `durationMs` per file. Store in `books.fileFingerprintsJson` (or new `LibraryFiles` table for multi-file books).
- Sync payload carries **fingerprints only**: `{ fileHash, sizeBytes, durationMs, fileName, trackIndex }`. No bytes leave device.
- On another device, a book with no local file shows as **"Not on this device"** (grey row, cloud icon). Tapping offers: locate file / re-import / import via Files / AirDrop / USB. When a local file with matching `fileHash` appears, the progress/bookmarks/chapters instantly apply.
- M4b: fingerprint the single file; chapter table (from §3) is synced separately so chapters appear even before file is present.

This keeps sync payloads to **kilobytes** regardless of library size.

---

## 3. Data model

### 3.1 Local tables (Drift) — sync-related additions

Existing tables: `Books`, `Chapters`, `Bookmarks`, `ListeningHistory`.

Proposed sync columns (added per synced table; nullable for pre-sync backward compat):

```dart
// Mix into Books, Bookmarks, ListeningHistory, and optionally Chapters.
// Chapters are derived from file probe; syncing them is optional but useful for
// single-file m4b where chapter parsing is expensive — sync avoids re-parsing.
IntColumn get updatedAtMs => integer().withDefault(const Constant(0))();
TextColumn get updatedByDeviceId => text().withDefault(const Constant(''))();
TextColumn get vectorClockJson => text().withDefault(const Constant('{}'))();
BoolColumn get isDeleted => boolean().withDefault(const Constant(false))(); // tombstone
BoolColumn get isDirty => boolean().withDefault(const Constant(false))();
BoolColumn get isEncrypted => boolean().withDefault(const Constant(false))();
```

New tables:

```dart
class SyncMeta extends Table {
  TextColumn get key => text()(); // singleton row: 'meta'
  TextColumn get userId => text().nullable()();
  TextColumn get deviceId => text()(); // uuid v4, one per install
  IntColumn get lastPulledAtMs => integer().withDefault(const Constant(0))();
  IntColumn get lastPushedAtMs => integer().withDefault(const Constant(0))();
  TextColumn get vectorClockJson => text().withDefault(const Constant('{}'))();
  @override Set<Column> get primaryKey => {key};
}

class LibraryFiles extends Table {
  TextColumn get id => text()(); // uuid
  TextColumn get bookId => text().customConstraint('REFERENCES books(id) ON DELETE CASCADE')();
  TextColumn get fileName => text()();
  TextColumn get fileHash => text()(); // sha256 hex
  IntColumn get sizeBytes => integer()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  IntColumn get trackIndex => integer().withDefault(const Constant(0))();
  @override Set<Column> get primaryKey => {id};
}

class SyncOutbox extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get tableName => text()();
  TextColumn get rowId => text()();
  TextColumn get op => text()(); // 'upsert' | 'delete'
  IntColumn get createdAtMs => integer()();
}
```

`LibraryFiles` is the canonical fingerprint store; `books.filePathsJson` keeps local absolute paths (device-specific, never synced raw).

### 3.2 Remote schema (logical — maps to Supabase table / Firestore collection / REST resource)

Per user (`user_id` is RLS/partition key):

- `remote_books` — one row per book `id`
- `remote_bookmarks` — one row per bookmark `id`
- `remote_history` — one row per history session `id` (append-only; never updated except `endedAtMs/endMs/listenedMs` once)
- `remote_files` — one row per `LibraryFiles.id`
- `remote_devices` — one row per `deviceId` (lastSeenAt, pushToken if notifications)

Each remote row stores:

```
id, user_id, payload_encrypted (text, nullable), payload_plain (jsonb, nullable),
updated_at_ms, updated_by_device_id, vector_clock (jsonb), is_deleted, created_at
```

`payload_encrypted` vs `payload_plain`: encrypted entity types go in the former; non-sensitive (e.g. file fingerprints/durations) may go plain for server-side dedupe/search.

### 3.3 Entity payloads (what is synced)

| Entity | Synced fields | Encrypted? | Notes |
|--------|---------------|------------|-------|
| Book progress | `id, title, author, coverHash?, totalDurationMs, lastPositionFileHash, lastPositionMs, totalProgress, isFinished, fileFingerprints[]` | **Yes** (progress + titles reveal taste) | `lastPositionFilePath` is local-only; sync `lastPositionFileHash + lastPositionMs + bookPositionMs` |
| Chapters | `id, bookId, title, startMs, endMs, trackIndex` | No (or same as book) | Optional; re-derivable |
| Bookmark | `id, bookId, title, note, kind, fileHash, positionMs, bookPositionMs, createdAtMs, chapterIndex` | **Yes** (notes are private) | `filePath` → `fileHash` on wire |
| ListeningHistory | `id, bookId, startedAtMs, endedAtMs, startMs, endMs, listenedMs, speed` | **Yes** | Append-only; large — cap pull window (e.g. last 90 days) + paginate |
| Settings (optional) | `speed, skipSilence, seekStep, autoBookmark, theme` | No | Small; sync if user opts in |

`addedAtMs` and `lastPlayedAtMs` are synced (useful for sorting) but never used for conflict resolution — see §4.

---

## 4. Conflict resolution — last-write-wins + vector clock

### 4.1 Vector clock

Per device, a monotonically increasing counter. Stored as `Map<deviceId, int>` serialized to `vectorClockJson` / `vector_clock`.

On local write:

```dart
clock[deviceId] = (clock[deviceId] ?? 0) + 1;
row.vectorClockJson = jsonEncode(clock);
row.updatedAtMs = nowMs;
row.updatedByDeviceId = deviceId;
row.isDirty = true;
```

### 4.2 Merge rule

For each incoming remote row vs local row with same `id`:

1. If one side has `isDeleted=true`, deletion wins only if its `updatedAtMs` is strictly greater (prevents accidental resurrect). Tombstones GC after 30 days.
2. If vector clocks are **comparable** (one dominates the other: every counter ≤ and at least one <), the dominating side wins.
3. If **concurrent** (neither dominates), apply **last-write-wins (LWW)** by `updatedAtMs` (server `updated_at_ms` is tie-breaker; device clocks are not trusted — server assigns `updated_at_ms` on push).
4. Bookmarks/history: never merge field-by-field; rows are atomic. History rows are append-only, so conflicts are rare (only the closing `endedAtMs` write can race — LWW is fine).
5. Book progress: atomic row LWW. If UX demands, future: merge `max(totalProgress)` — deferred to avoid surprising rewinds.

Result: deterministic, commutative, and safe to retry.

### 4.3 Clock skew

- Clients send `clientUpdatedAtMs` but server overwrites with `serverUpdatedAtMs` as canonical `updated_at_ms`. Clients adopt server time on pull.
- Optional: on sign-in, server returns `serverTimeMs` so client can compute skew offset for local ordering.

---

## 5. Encryption — progress & bookmarks

### 5.1 Threat model

- Transport is always TLS.
- **At-rest on server:** sensitive entities are opaque ciphertext; a DB leak reveals no titles, notes, or listening patterns.
- Server operator (or Supabase/Firebase admin) cannot read user content without the user's key.
- Device storage is not encrypted by sync (Drift file inherits OS file encryption; full at-rest device encryption is a separate concern).

### 5.2 Key management

- Derive a 256-bit sync key from user auth via **HKDF** over a per-user secret:
  - Supabase/Firebase: on first sign-in, generate `syncKey = random(32 bytes)` on device, wrap it with a key derived from `user.id + server pepper` via platform Keychain/Keystore (iOS Keychain / Android EncryptedSharedPreferences), and store wrapped copy server-side as `user_sync_key_wrapped` (so new devices can unwrap after re-auth).
  - Custom REST: similar; or derive from password via Argon2id if password auth is used (not recommended — prefer OAuth/JWT).
- Key rotation: generate new key, re-encrypt all rows on next push with `keyVersion` header; old key kept for decrypt until GC.

### 5.3 Envelope

For each encrypted entity:

```
plaintext JSON → AES-256-GCM(key, nonce=random 12B)
wire = base64(nonce || ciphertext || tag)  with header { keyVersion, alg: "aes-256-gcm" }
```

Implementation: `package:cryptography` or `encrypt` (AES-GCM). Nonce never reused. Payload size overhead ~28 bytes per row.

Library file hashes/durations may stay plaintext (they reveal little and enable server-side matching).

---

## 6. API spec

Base URL: `https://api.crisperplayer.app/v1` (custom REST) or Supabase/Firebase equivalent. All endpoints require `Authorization: Bearer <JWT>`.

### 6.1 Auth

```
POST /auth/magic-link        { email } → { ok }
POST /auth/oauth/:provider   → JWT
POST /auth/refresh           { refreshToken } → { accessToken, refreshToken }
GET  /me                     → { userId, email, serverTimeMs, syncKeyWrapped? }
```

Supabase/Firebase: use their SDK auth; JWT is their access token.

### 6.2 Sync — pull

```
GET /sync/pull?since=<ms>&limit=500&cursor=<opaque>
→ {
    serverTimeMs: 1713400000000,
    hasMore: true,
    cursor: "eyJ...",
    changes: [
      {
        table: "books" | "bookmarks" | "history" | "files" | "chapters",
        id: "uuid",
        isDeleted: false,
        updatedAtMs: 1713400000000,
        updatedByDeviceId: "device-uuid",
        vectorClock: { "deviceA": 5, "deviceB": 2 },
        payload: { ... } | null,          // plaintext entities
        payloadEncrypted: "base64..." | null,
        keyVersion: 1
      }
    ]
  }
```

- `since` is `lastPulledAtMs` (server `updated_at_ms`).
- Pagination via `cursor` (opaque server cursor) + `hasMore`.
- History may be paginated aggressively (e.g. 200 rows/page).
- Pull is **read-only**; no side effects.

Supabase equivalent: `SELECT * FROM remote_* WHERE user_id=:uid AND updated_at_ms > :since ORDER BY updated_at_ms LIMIT 500`.

### 6.3 Sync — push

```
POST /sync/push
Body: {
  deviceId: "uuid",
  deviceTimeMs: 1713400000000,
  changes: [ { table, id, isDeleted, clientUpdatedAtMs, vectorClock, payload?, payloadEncrypted?, keyVersion? } ]
}
→ {
  serverTimeMs: 1713400001000,
  results: [
    { id, table, status: "accepted" | "rejected", serverUpdatedAtMs, vectorClock, conflict?: { winner: "local"|"remote", remoteRow } }
  ]
}
```

- Server assigns `serverUpdatedAtMs` (canonical) and merges vector clock: `serverClock[deviceId] = max(serverClock[deviceId], incomingClock[deviceId])`.
- Conflict (concurrent vector clocks): server applies LWW by `serverUpdatedAtMs` (incoming row's time vs existing row's time) and returns `conflict` so client can surface/apply winner.
- Batch size cap: 100 rows/request. Client splits larger pushes.

### 6.4 Devices

```
GET  /devices              → [{ deviceId, lastSeenAtMs, platform, appVersion }]
DELETE /devices/:deviceId  → { ok }  // revoke device; its future pushes rejected
POST /devices/register     { deviceId, platform, pushToken? } → { ok }
```

### 6.5 File fingerprints (no bytes)

```
GET  /files?bookId=...     → [{ id, bookId, fileName, fileHash, sizeBytes, durationMs, trackIndex }]
POST /files/upsert         { files: [...] }  // same shape; hash-only
```

### 6.6 Errors (common)

| HTTP | Code | Meaning |
|------|------|---------|
| 401 | `unauthorized` | JWT expired/invalid → refresh |
| 409 | `conflict` | Concurrent write — see `conflict` payload; client applies winner |
| 413 | `payload_too_large` | Batch too big → split |
| 422 | `validation_error` | Bad shape → fix client |
| 429 | `rate_limited` | Back off (Retry-After) |
| 5xx | `server_error` | Retry with backoff |

All error bodies: `{ error: { code, message, retryAfterMs? } }`.

### 6.7 Supabase / Firebase mapping

- **Supabase:** Tables `remote_books`, `remote_bookmarks`, `remote_history`, `remote_files`, `remote_devices` with RLS `user_id = auth.uid()`. Sync endpoints become thin PostgREST wrappers or Edge Functions for push/pull batching + encryption passthrough.
- **Firebase:** Collections `users/{uid}/books/{id}` etc. Firestore rules mirror RLS. Prefer calling via Cloud Functions for push/pull to keep vector-clock logic server-side.

---

## 7. Sync flows (sequence)

### 7.1 First sign-in on a new device

1. Sign in → fetch `user_sync_key_wrapped` → unwrap with Keychain-derived KEK → obtain `syncKey`.
2. `GET /sync/pull?since=0` (paginated) → decrypt → `batch` into Drift (all rows `isDirty=false`).
3. Library shows cloud books as "Not on this device" until matching file hash appears.

### 7.2 Normal foreground sync

1. App resumes → if `now - lastPulledAt > 60s`, run `syncCycle()` (pull then push).
2. Progress/bookmark writes mark `isDirty` immediately; debounced push fires within 30 s or on pause.

### 7.3 Offline edits + reconnect

1. Offline: all writes stay local, `isDirty=true`, vector clock advances.
2. On reconnect: pull first (get remote wins), then push dirty. Conflicts resolved per §4.

### 7.4 Delete

1. Local delete → set `isDeleted=true`, `isDirty=true` (tombstone), hide from UI via `WHERE isDeleted=false`.
2. Push tombstone; remote marks `is_deleted=true`.
3. Other devices pull tombstone and hide row.
4. GC tombstones after 30 days (server + clients).

---

## 8. Privacy

- **Data minimization:** audio bytes never leave device. Only hashes, durations, progress, bookmarks, history.
- **Encryption:** Book titles/authors, positions, bookmark notes, history are encrypted client-side before upload (§5). File hashes/durations may remain plaintext for matching.
- **On-device:** Drift DB file inherits OS file protection (`NSFileProtectionComplete` on iOS, scoped storage on Android). No sync key in plaintext prefs.
- **Right to erasure:** `DELETE /me` wipes all remote rows for `user_id` (hard delete). Local data unaffected until user clears app.
- **No analytics on content:** Server logs contain only `user_id`, `deviceId`, row counts, and `updated_at_ms` — never plaintext payload.
- **Opt-in:** Sync is off by default. User explicitly signs in to enable. Sign-out keeps local data, wipes remote device token, and optionally deletes remote data on request.
- **Third-party backends:** If using Supabase/Firebase, their DPA/subprocessors apply. Self-host option exists for users who want no third party.

---

## 9. Offline-first guarantees

- Reads never block on network.
- Writes never fail due to offline — they are local + dirty.
- Sync cycles are idempotent and retryable; duplicate pushes (same `id` + `vectorClock`) are deduplicated server-side.
- App works identically with sync disabled (current behavior) — sync is additive.
- Background fetch (iOS `BGTaskScheduler`, Android `WorkManager`) may run periodic pull/push when OS allows, but is best-effort only.

---

## 10. Testing & rollout

- Unit: vector-clock compare, LWW tie-break, encrypt/decrypt round-trip, hash computation.
- Integration: two in-memory Drift instances + fake remote → concurrent edits → assert merge winner.
- Manual: airplane-mode edits → reconnect → verify no data loss.
- Rollout: behind `settings.enableCloudSync` flag (default off). Ship DB migration first, then sync engine, then UI badge.

---

## 11. Open decisions

- History retention window for pull (90 days default? user-configurable?).
- Whether to sync `coverPath` (local path → not useful) vs `coverHash` + optional small thumbnail upload (e.g. 200×200 JPEG, ~20 KB).
- Push notification to trigger pull on other devices (FCM/APNs) vs polling — v1 can poll on resume; push is optimization.
