# /patches — Modification Log

This directory documents every change made to the inherited upstream
codebase. Each patch entry describes the **why**, the **what**, and
the **risk** of the change.

Patches are applied directly to the source files at the repo root.
This directory does not contain `.patch` files — it contains the
**rationale record** so the intent behind every change survives.

---

## Patch Index

| ID       | File                     | Type      | Status      | Risk   |
|----------|--------------------------|-----------|-------------|--------|
| PATCH-01 | `store/settings.ts:107`  | Bug fix   | **Applied** | Low    |
| PATCH-02 | `store/store.ts:27-30`   | Bug fix   | **Applied** | Medium |
| PATCH-03 | `helpers/rest.ts:59,109` + `rest.messages.ts` | Bug fix | **Applied** | Low |
| PATCH-04 | `views/system/System.tsx:88-94` | Bug fix | **Applied** | Low  |
| PATCH-05 | `views/camera-events/CameraEvents.tsx:184,193` + `messages.ts` | Bug fix | **Applied** | Low |
| PATCH-06 | `views/camera-events/CameraEvent.tsx:105,121,131` + `messages.ts` | Bug fix | **Applied** | Low |
| PATCH-07 | `views/camera-events/Share.tsx:65-119` | Bug fix | **Applied** | Medium |

---

## PATCH-01 — Guard NativeModules.I18nManager

**Addresses:** SCARE-1 in `archaeology/SCARY_SECTIONS.md`
**File:** `store/settings.ts:107`

### Why
`NativeModules.I18nManager` is null on some Android devices at module
load time, crashing the entire store initialization chain and producing
a misleading "JSON error" on startup. This was the #1 user-reported issue.

### What Changes
```diff
- region: NativeModules.I18nManager.localeIdentifier,
+ region: NativeModules.I18nManager?.localeIdentifier ?? 'en_US',
```

### Trade-offs
- **Accepting:** Users on devices where the I18n bridge returns null
  will get `en_US` formatting as a default, which may not match their
  device language. This is a minor UX trade-off.
- **Alternative considered:** Making `initialSettings` a factory function
  to defer evaluation. Rejected because it would require changes in
  more files (every consumer of `initialSettings`).
- **Risk of `'en_US'` default:** Low. The user can always change their
  locale in settings. Crashing is strictly worse than a wrong default.

---

## PATCH-02 — Fix settingsMigrations Transform Type

**Addresses:** SCARE-2 in `archaeology/SCARY_SECTIONS.md`
**File:** `store/store.ts:27-30`

### Why
The `createTransform` outbound function passes `SettingsState`
(`{v1: ISettings}`) to `settingsMigrations` which expects `ISettings`.
This causes the migration to run on the wrong object, silently failing
to back-fill any new default settings for upgrading users.

### What Changes
```diff
  createTransform(
    state => state,
-   state => ({...state, ...settingsMigrations(state)}),
+   (state: SettingsState) => ({
+     ...state,
+     v1: settingsMigrations(state.v1),
+   }),
  ),
```

### Trade-offs
- **Risk:** This change makes the migration actually run correctly for
  the first time. Users who have accumulated settings under the broken
  migration will have any missing new-version defaults properly populated
  on the next launch. Existing settings are preserved.
- **What could go wrong:** If `state.v1` is somehow undefined in stored
  state (corrupted storage), `settingsMigrations(undefined)` would be
  called. `v1Migrations` handles undefined gracefully (returns undefined),
  and `fillGaps` with undefined uses all defaults — so this is safe.

---

## PATCH-03 — Check response.ok Before Parsing JSON

**Addresses:** SCARE-3 in `archaeology/SCARY_SECTIONS.md`
**File:** `helpers/rest.ts:59,94-109`

### Why
Non-JSON HTTP responses (HTML error pages from 4xx/5xx responses or
reverse proxies) cause `response.json()` to throw a `SyntaxError` that
surfaces to users as "JSON Parse error: Unexpected token '<'". This is
the exact error message widely reported in user bug reports.

### What Changes
In the `query` function, after fetching and after the 401 retry path,
add a `response.ok` guard before calling `.json()`:

```diff
+ if (!response.ok) {
+   throw new Error(`HTTP ${response.status}: ${method} ${url}`);
+ }
  return response[json === false ? 'text' : 'json']();
```

Apply the same to the retried response in the 401 block.

In the `login` function, add similar guard after the 400 check:
```diff
  if (response.status === 400) {
    throw new Error(intl.formatMessage(messages['frigateAuth.wrongCredentials']));
  }
+ if (!response.ok) {
+   throw new Error(`HTTP ${response.status}`);
+ }
  return response.json();
```

### Trade-offs
- **Added error message key:** A new i18n message key should be added
  for `error.httpError` to produce a localized error string. Using a
  raw string here is acceptable as an interim fix.
- **Behavior change:** HTTP errors that previously silently caused a
  JSON parse error toast will now show a more descriptive error toast.
  This is strictly an improvement.

---

## PATCH-04 — Add .finally() to System.tsx refresh()

**Addresses:** SCARE-4 in `archaeology/SCARY_SECTIONS.md`
**File:** `views/system/System.tsx:88-94`

### Why
If the stats API call fails, `setLoading(false)` never runs, leaving
the spinner on screen permanently.

### What Changes
```diff
  const refresh = () => {
    setLoading(true);
-   return get<Stats>(server, `stats`).then(stats => {
-     setStats(stats);
-     setLoading(false);
-   });
+   return get<Stats>(server, `stats`)
+     .then(stats => {
+       setStats(stats);
+     })
+     .finally(() => {
+       setLoading(false);
+     });
  };
```

### Trade-offs
- None. Moving `setLoading(false)` to `.finally()` is strictly correct.

---

## PATCH-05 — Add Error Handling to CameraEvents Fetch

**Addresses:** SCARE-5 in `archaeology/SCARY_SECTIONS.md`
**File:** `views/camera-events/CameraEvents.tsx:184,193-202`

### Why
The main events fetch swallows all errors silently. `loadMore` has no
error handling at all. Both leave users with no feedback on failure.

### What Changes
Replace `.catch(() => {})` with meaningful error handling, and add
`.catch()` to `loadMore`.

### Trade-offs
- Requires a user-visible error state (or toast) — needs a UX decision
  on how to communicate the error. At minimum, `ToastAndroid.show`
  matches the existing error pattern in the codebase.

---

## PATCH-06 — Add .catch() to CameraEvent Mutation Calls

**File:** `views/camera-events/CameraEvent.tsx:105,121,131`

### Why
Delete, retain, and unretain API calls have no error handling. If they
fail, the UI updates as if the operation succeeded (state inconsistency).

### What Changes
Add `.catch()` to each call that reverts the optimistic UI update or
shows a toast on failure.

### Trade-offs
- The current code does not do optimistic updates — it calls the API
  and then updates state in `.then()`. So the main risk is just that
  the user doesn't know if the call failed. Adding a toast in `.catch()`
  is the minimal correct fix.

---

## PATCH-07 — Guard download() Return Value in Share.tsx

**Addresses:** SCARE-6 in `archaeology/SCARY_SECTIONS.md`
**File:** `views/camera-events/Share.tsx:91-103`

### Why
`download()` returns `undefined` on error. The callers proceed to call
`RNShare.open({ url: 'file://undefined' })` without checking.

### What Changes
Add early return guard in `shareSnapshot` and `shareClip`:

```diff
  const path = await download(filename, url);
+ if (!path) {
+   return;  // download() already showed an error toast
+ }
  await stall(200);
  RNShare.open({ url: `file://${path}` })...
```

Also fix `JSON.stringify(err)` in the catch block:
```diff
- ToastAndroid.show(JSON.stringify(err), ToastAndroid.LONG);
+ ToastAndroid.show(String((err as Error)?.message ?? err), ToastAndroid.LONG);
```

### Trade-offs
- None. This is a straightforward null-safety fix.
