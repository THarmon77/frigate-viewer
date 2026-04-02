# MODULE_MAP.md — Per-Module Documentation

> Each module follows the four-field protocol:
> **THE INTENT** / **THE GHOSTS** / **THE DETRIMENT** / **THE TRANSPORTER MAP**

---

## `store/settings.ts`

### THE INTENT
Define the canonical shape of all user-configurable settings as a
TypeScript interface (`ISettings`), provide sensible defaults
(`initialSettings`), and implement a migration pipeline
(`settingsMigrations` + `fillGaps`) that forward-fills missing keys when
the app is updated. Also exports Redux Toolkit slice with reducers for
mutating settings, and selectors for reading individual settings fields.

### THE GHOSTS
- `initialSettings` is a **module-level constant**, not a factory. It is
  evaluated once when the module loads, synchronously, with no error
  boundary. Any side-effect or failure (e.g. `NativeModules` null access)
  crashes the entire module import chain.
- `fillGaps` uses `Object.keys(initial)` to drive the merge. Any new key
  added to `ISettings` that is not also in `initialSettings` will never
  be back-filled for existing users.
- `fillGaps` only goes one level deep for arrays (it checks
  `!Array.isArray`). If a new nested array is added inside an existing
  object key, it will not be merged — the entire parent object from the
  stored state takes precedence.
- The `Region` type is a closed union of specific locale strings. If a
  device returns a locale not in this list (very likely for regional
  variants), the type system is violated at runtime.
- `v1Migrations` handles the `server` → `servers` deprecation correctly,
  but the function is called with the wrong type by `store.ts` (see
  SCARE-2 in `SCARY_SECTIONS.md`).

### THE DETRIMENT
- Startup crash for users on devices where `NativeModules.I18nManager`
  is null (see SCARE-1).
- Users with unsupported locales get an invalid `region` value stored,
  which can cause `react-intl` formatting to silently fall back or error.
- Settings migrations silently fail when called with wrong argument type.

### THE TRANSPORTER MAP
To reconstruct this module from scratch:
1. Define `ISettings` interface with all settings sub-groups.
2. Provide `initialSettings` as a **function** (not a constant) to defer
   evaluation: `export const makeInitialSettings = (): ISettings => ({...})`.
3. Guard native calls: `NativeModules.I18nManager?.localeIdentifier ?? '{{DEFAULT_LOCALE}}'`.
4. Add new locales to the `Region` union by updating the list and verifying
   against the `react-intl` locale data.
5. Test `fillGaps` with partial, empty, and null inputs.

---

## `store/store.ts`

### THE INTENT
Configure the Redux store with two reducers: `settings` (persisted via
`redux-persist` to `AsyncStorage`) and `events` (not persisted, ephemeral).
Apply a custom `createTransform` that runs migration logic on every
rehydration so returning users always have complete settings with all
new defaults applied.

### THE GHOSTS
- The `createTransform` outbound function receives `SettingsState`
  (`{v1: ISettings}`) but passes it directly to `settingsMigrations`
  which expects `ISettings`. This is SCARE-2.
- `persistReducer<SettingsState>` has no `version` or `migrate` config.
  The recommended pattern for versioned migrations is to use
  `redux-persist`'s built-in `migrate` option with version numbers.
  The custom transform approach works but is fragile and non-standard.
- The transform's inbound function is `state => state` (identity), meaning
  state is stored exactly as-is. If state shape changes drastically between
  versions, old stored data may be irrecoverable.
- `persistor` is exported as a side-effect of calling `persistStore(store)`.
  This is evaluated at import time. Any failure in store initialization
  propagates immediately.

### THE DETRIMENT
- Broken migration means new settings keys are never back-filled for
  upgrading users (they always see defaults for new features).
- No version number means there's no way to run destructive migrations
  (e.g., "remove old format X and replace with Y") safely.

### THE TRANSPORTER MAP
To reconstruct with correct pattern:
```typescript
// Correct transform — passes inner ISettings, not wrapper
createTransform(
  (state: SettingsState) => state,
  (state: SettingsState) => ({
    ...state,
    v1: settingsMigrations(state.v1),
  }),
)
```

For future versioned migrations, add `version: 1` and a `migrate`
function to `persistReducer` config.

---

## `helpers/rest.ts`

### THE INTENT
Provide a React hook (`useRest`) that exposes three functions — `get`,
`post`, `del` — for making authenticated HTTP requests to the Frigate
API. Handle authentication automatically: for `frigate` auth, call the
`/api/login` endpoint on 401 and retry the original request. For `basic`
auth, inject the `Authorization` header. Show toast notifications on
errors. Log all requests and errors to Firebase Crashlytics.

### THE GHOSTS
- `response.json()` is called without first checking `response.ok`. Any
  non-JSON HTTP response (HTML error pages, empty bodies) produces a
  `SyntaxError` that surfaces to the user as a confusing "JSON error"
  (SCARE-3).
- The `catch` block calls `ToastAndroid.show(e.message, ...)`. If the
  error is a `SyntaxError` with a long message, the toast may be clipped.
  More importantly, this is Android-only. On iOS, this silently does
  nothing.
- `buildServerUrl` returns `undefined` if `protocol` or `host` are
  empty. The callers (`buildServerApiUrl`, then `query`) will construct
  URLs like `undefined/api/events` which will throw a network error
  rather than a clear "server not configured" error.
- The `login` function shares the same `response.json()` issue and
  additionally only checks for status 400 explicitly — a 500 from the
  login endpoint falls through to `.json()` parsing.
- `useRest` is a hook (uses `useIntl`), so it cannot be called outside
  of React components. This tightly couples all HTTP logic to the React
  tree.

### THE DETRIMENT
- All server errors appear as JSON parse errors to users.
- Unconfigured server shows network errors instead of onboarding prompts.
- iOS users get no error feedback at all (ToastAndroid is Android-only).

### THE TRANSPORTER MAP
Core URL construction logic:
```
Protocol + "://" + Host + (":" + Port if present) + "/" + (Path if present) + "api/" + endpoint
```
Auth strategies:
- `none`: no Authorization header
- `basic`: `Authorization: Basic base64(username:password)`
- `frigate`: POST to `/api/login`, then retry with session cookie

---

## `helpers/redux.tsx`

### THE INTENT
Provide a Higher-Order Component `withRedux` that wraps any
`react-native-navigation` screen component with the Redux `Provider`
and redux-persist's `PersistGate`. This ensures every screen has access
to the store and waits for persisted state to load before rendering.

### THE GHOSTS
- `PersistGate` has no `loading` prop specified. When null, it renders
  nothing while rehydrating — blank white screen for the user.
- No `onBeforeLift` callback to validate rehydrated state shape.
- No React Error Boundary. A crash in any wrapped component during
  hydration is uncaught.
- `persistor` and `store` are imported as module-level singletons.
  Multiple screens wrapped with `withRedux` share the same store
  instance — this is correct behavior but means any store corruption
  affects all screens simultaneously.

### THE DETRIMENT
- Blank screen on slow storage or storage errors.
- Any crash during rehydration kills the entire navigation stack.

### THE TRANSPORTER MAP
Minimal reconstruction:
```tsx
<Provider store={store}>
  <PersistGate loading={<LoadingScreen />} persistor={persistor}>
    <Component {...props} />
  </PersistGate>
</Provider>
```
Add an `ErrorBoundary` wrapper outside `Provider` for full resilience.

---

## `views/camera-events/CameraEvents.tsx`

### THE INTENT
Display a paginated, filterable list of camera events from the Frigate
API. Support pull-to-refresh, infinite scroll (load more on end-reached),
multi-column layout, filter by camera/label/zone/retained status, and
initiate sharing or clip viewing for individual events.

### THE GHOSTS
- `eventsQueryParams` memo depends on `events` state AND `refreshing`.
  The `before` cursor key (`events[events.length-1].start_time`) is
  included in the memo but the memo is recomputed every time `events`
  changes, which happens during loadMore. This can cause `loadMore` to
  fetch overlapping pages.
- Silent `.catch(() => {})` means users see empty lists on any error.
- `loadMore` has no catch handler and no guard against concurrent calls.
  If the user scrolls fast, multiple concurrent `loadMore` requests can
  race and produce duplicate events in the list.
- `listRef.current?.scrollToIndex({index: 0})` can throw on Android if
  the list hasn't rendered yet. The optional chain prevents a crash but
  silently fails to scroll.
- The `eslint-disable-next-line react-hooks/exhaustive-deps` comment at
  line 190 suppresses a legitimate deps warning. `eventsQueryParams` is
  intentionally excluded to avoid re-fetching on every keystroke in
  filters, but this means filter changes do not immediately trigger a
  refresh through the `useEffect` — they rely on a separate `useEffect`
  at line 204-207 which calls `refresh()`.

### THE DETRIMENT
- Potential duplicate events on fast scrolling.
- Users can't distinguish "no events" from "failed to load events".
- Filter changes may not reliably refresh if both useEffects fire close
  together.

### THE TRANSPORTER MAP
Data flow:
1. Component mounts → `useEffect([refreshing])` fires → if `refreshing===true`, fetch events
2. Pull-to-refresh → `refresh()` → `setRefreshing(true)` → triggers step 1
3. Scroll to end → `loadMore()` → fetch with `before` cursor → append to events
4. Filter change → `useEffect([filters])` → `refresh()` → triggers step 1

---

## `views/system/System.tsx`

### THE INTENT
Display a live system statistics dashboard for the Frigate server:
detector performance, GPU utilization, per-camera CPU/FPS metrics.
Polls the `/api/stats` endpoint every 30 seconds. Shows charts when
CPU data is available, tables otherwise.

### THE GHOSTS
- `refresh()` has no `.catch()` — spinner hangs forever on error (SCARE-4).
- `setInterval` unhandled rejection on every poll cycle during outages.
- The `refreshButton(refresh)` call at line 69 passes `refresh` as a
  navigation button callback. If the navigation library calls this
  asynchronously after the component unmounts, `setLoading` / `setStats`
  are called on an unmounted component.
- `stats.cpu_usages` is optionally chained in some places but not others.
  `stats.gpu_usages` is checked with `stats && stats.gpu_usages` but
  then accessed with `stats.gpu_usages!` (non-null assertion) in the memo.
  If `gpu_usages` becomes null between the check and the access (impossible
  in practice but TypeScript allows it), a runtime error occurs.
- `refreshFrequency` is hardcoded to `30` at the top of the file (line 30)
  rather than reading from user settings. There is a `selectCamerasRefreshFrequency`
  selector in the store but it's not used here.

### THE DETRIMENT
- Infinite spinner on network error.
- Stale stats if the user's preferred refresh frequency differs from 30s.

---

## `views/camera-events/Share.tsx`

### THE INTENT
Provide an `ActionSheet` allowing users to share a camera event's
snapshot or clip to other apps via the native share sheet. Downloads
the file to the device cache using `rn-fetch-blob`, shows a progress
indicator, then invokes `react-native-share`.

### THE GHOSTS
- `download()` returns `undefined` on error; callers don't check (SCARE-6).
- `JSON.stringify(err)` in the catch block can throw on native errors.
- `RNShare.open()` has no `.catch()` — if the user dismisses the share
  sheet, some implementations throw a "user cancelled" error that goes
  unhandled.
- `RNFetchBlob.session('share').dispose()` only runs if `RNShare.open`
  resolves successfully. If sharing fails or is cancelled, cached files
  accumulate in `dirs.CacheDir` indefinitely.
- `stall(200)` is a 200ms arbitrary delay between download completion
  and share sheet opening. This suggests a race condition was observed
  during development but not properly fixed.

### THE DETRIMENT
- Cache files may grow unboundedly over time if shares are cancelled.
- Failed downloads silently attempt to share `file://undefined`.

---

## `views/camera-event-clip/CameraEventClip.tsx`

### THE INTENT
Display a full-screen video player for a Frigate event clip using the
`@lunarr/vlc-player` package. Supports both HTTP stream URLs and local
file playback. Handles landscape orientation locking.

### THE GHOSTS
- `setError(JSON.stringify(err))` at line 149 can throw on certain native
  errors from the VLC player (circular reference in error object).
- The VLC player is Android-only. On iOS this screen likely crashes on
  mount when the native module is null.
- No timeout on video loading — if the stream never responds, the loading
  state persists indefinitely.

### THE DETRIMENT
- iOS users attempting to view clips crash the app.
- Long or unresponsive streams show a permanent loading indicator.

---

## `store/events.ts`

### THE INTENT
Store ephemeral UI state for event filters: which cameras, labels,
zones are selected, and whether to show only retained events.
Not persisted — resets on app restart.

### THE GHOSTS
- Filter state is not persisted, so users must re-apply filters every
  session. No obvious reason for this decision — it may be intentional
  (transient UI state) or an oversight.
- `selectAvailableCameras` depends on filter state being populated
  correctly. If the Frigate API returns new cameras, the available list
  won't update until the user navigates to the filter screen.

### THE DETRIMENT
- Low-severity UX issue: filters reset on every app restart.
