# SCARY_SECTIONS.md — Dangerous Code Deep-Dive

> These are the sections of the inherited codebase most likely to
> cause production failures. Ordered by severity. Each entry follows
> the four-field protocol: INTENT / GHOSTS / DETRIMENT / TRANSPORTER MAP.

---

## SCARE-1 (CRITICAL) — Unsafe NativeModules Access at Module Load Time

**File:** `store/settings.ts:107`

```typescript
// As inherited — DANGEROUS
export const initialSettings: ISettings = {
  ...
  locale: {
    region: NativeModules.I18nManager.localeIdentifier,  // ← THE PROBLEM
    datesDisplay: 'descriptive',
  },
  ...
};
```

### THE INTENT
The original author wanted to auto-detect the user's device locale at
first launch and pre-populate the `locale.region` setting so dates and
numbers appear in the correct regional format without requiring the user
to configure it manually.

### THE GHOSTS
1. **`initialSettings` is evaluated synchronously at module load time.**
   This is a top-level constant, not a factory function. It runs the
   moment `settings.ts` is `import`-ed — before any React lifecycle,
   before any null-checks, before the app is fully initialized.

2. **`NativeModules.I18nManager` can be `null` on some Android devices.**
   Specifically: custom ROMs, some emulators, and devices where the
   I18n bridge hasn't finished binding when the JS module first loads.
   On these devices, `NativeModules.I18nManager.localeIdentifier` throws:
   `TypeError: null is not an object (evaluating 'NativeModules.I18nManager.localeIdentifier')`

3. **`localeIdentifier` format varies by platform and ROM.**
   It may return `en_US`, `en-US`, `en`, or even `en_US_#Latn`.
   The `Region` type only accepts a fixed whitelist (e.g. `'en_US'`).
   Non-matching values are silently stored as invalid types.

4. **The crash propagates to redux-persist and surfaces as a "JSON error."**
   When `settings.ts` fails to evaluate, `store.ts` (which imports it)
   also fails. `redux-persist` then tries to rehydrate against a broken
   store reference, and the error often surfaces downstream as a
   `SyntaxError: JSON Parse error` — misleading users and bug reporters.

### THE DETRIMENT
- **App crashes on startup** for all users on affected devices.
- The crash is non-recoverable without clearing app data (or reinstalling).
- Because the error manifests as a JSON parse error rather than the real
  TypeError, the root cause is hard to diagnose from crash logs.
- Every redux-persist rehydration on subsequent launches also fails,
  meaning the user's settings are permanently unreadable.

### TRANSPORTER MAP (Reconstruction Guide)
To reproduce safely:
1. Use an Android emulator with API 30 or lower.
2. Clear app data: `adb shell pm clear com.{{APP_PACKAGE}}`.
3. Launch the app with the Metro bundler attached.
4. Observe the crash in LogCat: search for `I18nManager`.

**The Fix (see `/patches/`):**
```typescript
// Safe version
region: NativeModules.I18nManager?.localeIdentifier ?? 'en_US',
```
Use optional chaining (`?.`) to handle null `I18nManager`, and provide
`'en_US'` as a safe default fallback.

---

## SCARE-2 (CRITICAL) — `settingsMigrations` Transform Type Mismatch

**File:** `store/store.ts:27-30`

```typescript
// As inherited — DANGEROUS
const settingsReducer = persistReducer<SettingsState>(
  {
    key: 'settings',
    storage: AsyncStorage,
    transforms: [
      createTransform(
        state => state,
        state => ({...state, ...settingsMigrations(state)}),  // ← THE PROBLEM
      ),
    ],
  },
  settingsStore.reducer,
);
```

### THE INTENT
The author wanted to run migration logic on stored settings every time
the app loads from disk. `settingsMigrations` fills in any missing
settings keys that were added in newer versions of the app — so
upgrading users get sensible defaults for new features without losing
existing config.

### THE GHOSTS
1. **`state` in the `createTransform` outbound function is `SettingsState`,
   not `ISettings`.**
   `SettingsState = { v1: ISettings }`. The reducer wraps settings in a
   `v1` key. But `settingsMigrations` is typed to receive `ISettings`
   (the inner object), not the wrapper. TypeScript does not catch this
   because the types are structurally compatible enough to not error.

2. **At runtime, `v1Migrations` receives `{ v1: ISettings }` and
   destructures `{ server, servers, ...rest }` from it.**
   Neither `server` nor `servers` exist at this level. It returns
   `{ v1: ISettings, servers: undefined }`.

3. **`fillGaps(initialSettings, { v1: ISettings, servers: undefined })`
   then runs over `Object.keys(initialSettings)` which does not include
   `v1`.**
   Result: ALL top-level settings (`servers`, `locale`, `app`, `cameras`,
   `events`) are reset to `initialSettings` defaults on every cold start,
   because the current persisted values are nested under `.v1` and never
   found by the merge.

4. **`locale.region` in `initialSettings` re-invokes SCARE-1.**
   Every restart, the migration resets `locale.region` to
   `NativeModules.I18nManager.localeIdentifier`, compounding the risk
   even on devices where the first launch didn't crash.

5. **User-saved settings appear to vanish after every cold start.**
   The `v1` key is spread back in via `{...state, ...result}`, so the
   data isn't lost from storage, but the migration logic never applies
   correctly, meaning new-version defaults are never back-filled properly.

### THE DETRIMENT
- Settings migrations silently fail to run. New fields added in future
  versions will always be undefined for returning users.
- Perceived data loss: user configures the app, force-kills it, reopens
  it, and their settings appear reverted (because defaults were re-applied
  over the `v1` sub-object path).
- Combined with SCARE-1: the reset on every launch means SCARE-1 fires
  on every startup, not just the first.

### TRANSPORTER MAP
To reproduce:
1. Fresh install; configure a server and non-default settings.
2. Force-stop the app.
3. Re-open; observe settings back to defaults.

**The Fix (see `/patches/`):**
```typescript
createTransform(
  state => state,
  (state: SettingsState) => ({
    ...state,
    v1: settingsMigrations(state.v1),  // pass only the inner ISettings
  }),
)
```

---

## SCARE-3 (HIGH) — Unguarded `response.json()` in HTTP Helper

**File:** `helpers/rest.ts:59, helpers/rest.ts:109`

```typescript
// login function — line 59
return response.json();  // ← no response.ok check

// query function — line 109
return response[json === false ? 'text' : 'json']();  // ← no response.ok check
```

### THE INTENT
After a successful HTTP call, parse the response body as JSON (or text
for certain binary-adjacent endpoints) and return it to the caller.

### THE GHOSTS
1. **`response.ok` is not checked before calling `.json()`.**
   When Frigate returns a non-200 status (e.g. 502 Bad Gateway from a
   reverse proxy, 503 during startup, 404 for a missing endpoint), the
   response body is typically an HTML error page, not JSON.
   Calling `.json()` on HTML throws:
   `SyntaxError: JSON Parse error: Unexpected token '<'`

2. **The thrown `SyntaxError` is caught by the outer `try/catch`.**
   The catch block logs to Crashlytics and calls:
   `ToastAndroid.show(e.message, ToastAndroid.LONG)`
   The user sees: *"JSON Parse error: Unexpected token '<'"* —
   which is the "JSON error on start" reported by many users.
   They have no idea what actually went wrong (server unreachable,
   auth failure, reverse proxy error, etc.).

3. **`response.ok` IS already logged** at line 94-96 (`!response.ok`
   logs to crashlytics), but the code does NOT throw or return early.
   The check is cosmetic only.

4. **The login retry path (lines 98-101) has the same issue.**
   After auto-login, `retriedResponse.json()` is called with the same
   lack of status validation.

### THE DETRIMENT
- Every non-JSON server response manifests to the user as a cryptic
  "JSON error", making diagnosis nearly impossible.
- Error details (actual HTTP status, actual server message) are lost.
- If Frigate is behind a reverse proxy that returns 401/403 HTML, the
  app appears "broken" when it's actually an auth config problem.

### TRANSPORTER MAP
To reproduce:
1. Configure the app with a valid host but add a reverse proxy that
   returns a 503 HTML page during startup.
2. Open the app and navigate to any data view.
3. Observe the toast: "JSON Parse error: Unexpected token '<'".

**The Fix (see `/patches/`):**
```typescript
// After fetching, before parsing:
if (!response.ok) {
  throw new Error(
    intl.formatMessage(messages['error.httpError'], {
      status: response.status,
      url,
    })
  );
}
return response[json === false ? 'text' : 'json']();
```

---

## SCARE-4 (HIGH) — Infinite Loading Spinner in System.tsx

**File:** `views/system/System.tsx:88-94`

```typescript
const refresh = () => {
  setLoading(true);
  return get<Stats>(server, `stats`).then(stats => {
    setStats(stats);
    setLoading(false);         // ← only runs on success
  });
  // ← NO .catch() or .finally()
};

// Called in a setInterval every 30s — line 82-84
interval.current = setInterval(async () => {
  await refresh();             // ← unhandled rejection
}, refreshFrequency * 1000);
```

### THE INTENT
Poll the Frigate `/api/stats` endpoint every 30 seconds and update the
system stats display. A loading indicator is shown while fetching.

### THE GHOSTS
1. If `get<Stats>` rejects (network error, server down, non-JSON
   response via SCARE-3), `.then()` never runs, so `setLoading(false)`
   never executes.
2. The loading spinner remains on screen permanently until the user
   navigates away and back.
3. The `setInterval` continues firing every 30 seconds, each time
   calling `setLoading(true)` on an already-loading component, but
   never resolving it.
4. The unhandled promise rejection in `setInterval` is silently swallowed.

### THE DETRIMENT
- Users on flaky networks see a perpetual spinner on the System tab.
- The only recovery is navigating away and back, which is not obvious.
- On every polling cycle that fails, the component tries to set state
  potentially after unmount (if the user navigated away), which can
  trigger a React "Can't perform a state update on an unmounted component"
  warning in development.

### TRANSPORTER MAP
To reproduce:
1. Open the System tab with a valid connection.
2. Shut down (or network-isolate) the Frigate server.
3. Wait 30 seconds.
4. Observe the spinner appearing and never disappearing.

**The Fix:**
```typescript
const refresh = () => {
  setLoading(true);
  return get<Stats>(server, `stats`)
    .then(stats => {
      setStats(stats);
    })
    .catch(() => {
      // optionally: setError(true) to show an error state
    })
    .finally(() => {
      setLoading(false);
    });
};
```

---

## SCARE-5 (HIGH) — Silent Error Swallowing in CameraEvents

**File:** `views/camera-events/CameraEvents.tsx:184`

```typescript
get<ICameraEvent[]>(server, `events`, {queryParams: eventsQueryParams})
  .then(data => { ... })
  .catch(() => {})   // ← explicitly discards all errors
  .finally(() => { setRefreshing(false); });
```

And `loadMore` at line 193-202:
```typescript
const loadMore = () => {
  if (!endReached) {
    get<ICameraEvent[]>(server, `events`, {...}).then(data => {
      watchEndReached(data);
      setEvents([...events, ...data]);
    });
    // ← NO .catch() at all
  }
};
```

### THE INTENT
Fetch the list of camera events on mount and on pull-to-refresh.
`loadMore` appends the next page when the list is scrolled to the bottom.

### THE GHOSTS
1. The `.catch(() => {})` in the main fetch was presumably added to
   prevent unhandled rejection warnings. But it discards all error
   information — users see an empty list with no indication of why.
2. `loadMore` has no catch at all. If it fails mid-scroll, the FlatList
   stops paginating silently. The user scrolls to the bottom repeatedly
   and nothing happens.
3. The `eventsQueryParams` memo depends on `events` state but also
   triggers `refreshing`. This creates a subtle dependency loop risk:
   changing events triggers a re-memo which can trigger refresh again.
   (See line 144: `before: events[events.length-1].start_time`)

### THE DETRIMENT
- Blank screen on network failure with no user feedback.
- Broken pagination that appears as "no more events" when it's actually
  a network error.

---

## SCARE-6 (MEDIUM) — `download()` Returns `undefined` on Error

**File:** `views/camera-events/Share.tsx:65-103`

```typescript
const download = async (filename: string, url: string) => {
  try {
    // ... download logic ...
    return filePath;
  } catch (err) {
    setLoading(false);
    ToastAndroid.show(JSON.stringify(err), ToastAndroid.LONG);
    // ← implicit return undefined
  }
};

// Caller:
const path = await download(filename, url);  // path is string | undefined
await stall(200);
RNShare.open({
  url: `file://${path}`,  // ← 'file://undefined' if download failed
}).then(() => { ... });
```

### THE INTENT
Download a snapshot or clip to the device cache, then open the system
share sheet so the user can share it to other apps.

### THE GHOSTS
1. `download()` has a `try/catch` that catches errors and shows a toast.
   But it returns `undefined` implicitly on error rather than rethrowing.
2. The caller doesn't check the return value before proceeding.
3. `RNShare.open({ url: 'file://undefined' })` is called with a literal
   invalid path. This may silently fail or show a confusing system error.
4. `JSON.stringify(err)` at line 87 can itself throw if `err` contains
   circular references (e.g., certain native error objects from
   `rn-fetch-blob`). This would be an error inside an error handler.

### THE DETRIMENT
- A failed download shows a toast, then immediately attempts to share
  a file that doesn't exist.
- The `RNShare.open` call has no `.catch()`, so any subsequent error is
  fully silent.
- In the worst case, `JSON.stringify(err)` throws inside the catch,
  crashing the error handler and leaving `loading` stuck at `false`
  while the dialog remains open.

---

## SCARE-7 (MEDIUM) — No Error Boundary on PersistGate

**File:** `helpers/redux.tsx:17`

```typescript
<PersistGate persistor={persistor}>
  <Component {...props} />
</PersistGate>
```

### THE INTENT
Wrap every screen with the Redux store Provider and delay rendering
until redux-persist has finished rehydrating state from AsyncStorage.

### THE GHOSTS
1. `PersistGate` with no `loading` prop renders nothing (null) while
   rehydrating — the user sees a blank screen.
2. There is no `onBeforeLift` callback to validate the rehydrated state.
3. If `AsyncStorage` is unavailable (corrupted, out of space, storage
   permission revoked on Android 13+), `PersistGate` hangs indefinitely.
4. No React Error Boundary wraps the component tree, so a JS error in
   any child during rehydration propagates as an uncaught error.

### THE DETRIMENT
- App hangs on a blank screen if storage is unavailable.
- No fallback UI or retry mechanism.
- Compounded by SCARE-1 and SCARE-2: if the store fails to initialize,
  the PersistGate will never resolve.
