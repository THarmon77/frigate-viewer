# MASTER_LOG.md — The Story of This Fork

> This document narrates the history and intent of this fork.
> It is not a changelog. It explains the *why* behind every decision,
> the trade-offs accepted, and the risks carried forward.

---

## Chapter 0 — Why Fork?

Frigate Viewer is a well-intentioned, functional React Native app that
wraps the Frigate NVR API in a mobile UI. The upstream maintainers
(`sp-engineering`) built something genuinely useful. However, the codebase
carries several compounding bugs that cause a well-documented, widely
reported startup crash — most visibly manifesting as a cryptic
**"JSON Parse error"** that users see on first launch or after clearing
app data.

The upstream repository shows no active resolution of these issues.
This fork exists to:

1. Fix the startup JSON error and its root causes
2. Document the inherited codebase thoroughly enough that future
   maintainers understand the original design intent and the hazards
3. Maintain alignment with upstream as closely as possible to minimize
   divergence

This is not a rewrite. It is a targeted surgical intervention on a
codebase that works 90% of the time but fails catastrophically in
predictable, fixable ways.

---

## Chapter 1 — Inheriting the Dig Site

**Fork point:** commit `6e4dcf1` on `tharmon77/frigate-viewer`
**App version at fork:** `14.3.0`

The codebase at fork time is a React Native 0.73.9 app with:
- Redux Toolkit + redux-persist for state management
- Wix React Native Navigation (not React Navigation)
- Firebase Crashlytics for error reporting
- rn-fetch-blob for file downloads
- VLC player for RTSP streams (Android only)
- react-intl for i18n

The navigation architecture (Wix RNN) is notable because it is more
complex than the commonly-used React Navigation library. Every screen
is registered as a native component and rendered independently, which
is why `helpers/redux.tsx` wraps each screen individually with the
Redux Provider + PersistGate rather than wrapping the app root once.

The state persistence architecture uses redux-persist's `AsyncStorage`
adapter, with a custom `createTransform` for running migrations. The
settings slice wraps `ISettings` in a `{v1: ISettings}` envelope
to support versioned migrations — a pattern that suggests the original
authors anticipated future breaking changes to the settings schema.

---

## Chapter 2 — Diagnosing the "JSON Error"

### What users reported
Multiple users reported seeing a JSON parse error immediately on app
startup. The exact message varies by device but typically resembles:
> `SyntaxError: JSON Parse error: Unexpected token '<'`
or
> `TypeError: null is not an object (evaluating 'NativeModules.I18nManager.localeIdentifier')`

### The actual chain of causation

The two issues are **linked in a cascade**:

**Step 1 — Root cause:** `store/settings.ts:107` accesses
`NativeModules.I18nManager.localeIdentifier` at module load time with
no null guard. On affected devices (certain Android ROMs, emulators),
`NativeModules.I18nManager` is `null`.

**Step 2 — Propagation:** When `settings.ts` fails to evaluate, the
`store/store.ts` module (which imports `initialSettings` and
`settingsMigrations` from it) also fails. `persistStore(store)` cannot
run. The `persistor` singleton is never properly initialized.

**Step 3 — Misleading error:** redux-persist attempts to rehydrate
state from `AsyncStorage`. With a broken persistor, it either reads
corrupted/partial JSON or encounters an internal error during the
transform phase. The error that bubbles up is a JSON-flavored error
because redux-persist uses `JSON.parse` internally — not because
there's actually a JSON problem.

**Step 4 — Compounding factor:** Even on devices where Step 1 doesn't
crash (the `NativeModules` call succeeds), the `createTransform` in
`store/store.ts` is misconfigured (SCARE-2). It passes the full
`SettingsState` wrapper to `settingsMigrations` instead of the inner
`ISettings`. This means the migration runs on `{v1: {...}}` instead of
`{servers: [...], locale: {...}, ...}`, finds none of the expected keys,
and returns all defaults. The effect: settings reset to defaults on
every cold start, and `locale.region` re-evaluates `NativeModules.I18nManager`
on every launch, repeatedly triggering the SCARE-1 crash on affected
devices.

### Why it wasn't caught
1. The crash only affects devices where `NativeModules.I18nManager === null`.
   Developer machines typically use standard emulators where it works.
2. The "JSON error" message obscures the real `TypeError` at the source.
3. The migration bug (SCARE-2) is a TypeScript type mismatch that
   TypeScript doesn't catch (the types overlap structurally enough).
4. The transform runs correctly enough that settings *mostly* work —
   the `v1` key is preserved in the spread — so the bug wasn't
   obvious in casual testing.

---

## Chapter 3 — The Fixes

### Decision: Minimal Targeted Fixes, Not Refactoring

We chose the smallest possible changes to fix the reported bugs.
We explicitly did NOT:
- Refactor the settings module to use factory functions (though this
  would be architecturally cleaner)
- Replace the custom transform with redux-persist's native `migrate`
  system (though that would be more standard)
- Change the navigation architecture
- Refactor error handling to be a cross-cutting concern

**Why:** Smaller diffs are easier to review, easier to port if upstream
resumes activity, and less likely to introduce new bugs. The existing
architecture, while imperfect, is coherent. We are patching holes, not
rebuilding the ship.

### Fix 1 — Optional chaining on NativeModules (PATCH-01)
`NativeModules.I18nManager?.localeIdentifier ?? 'en_US'`

We chose X (`?.` with `'en_US'` fallback) over Y (factory function)
because of Z (minimal change surface), accepting the risk of [users
on null-I18n devices defaulting to `en_US` instead of their device
locale]. The user can override this in Settings.

### Fix 2 — Correct transform argument (PATCH-02)
Pass `state.v1` to `settingsMigrations` instead of `state`.

We chose X (fix the call site in `store.ts`) over Y (make
`settingsMigrations` accept both types) because of Z (the function
signature is semantically correct — it should receive `ISettings`;
fixing the caller is cleaner), accepting the risk of [correctly running
migrations may surface previously-hidden gaps in users' stored settings,
which will be filled with defaults on next launch — this is the intended
behavior].

### Fix 3 — response.ok guard before JSON parsing (PATCH-03)
Check `!response.ok` and throw a descriptive error before calling
`.json()`.

We chose X (throw on non-ok before parsing) over Y (wrapping `.json()`
in its own try-catch with custom error) because of Z (fail-fast is
clearer and the HTTP status is the real error that should be communicated),
accepting the risk of [changing the user-visible error message from
"JSON Parse error" to "HTTP 502: ...". This is strictly an improvement
but changes observable behavior].

### Fix 4-7 — Missing error handlers
Adding `.finally()`, `.catch()`, and null-guards throughout the view
layer. Each of these is strictly additive with no behavioral downside.

---

## Chapter 4 — What We Carried Forward (Known Risks)

The following issues were identified but NOT fixed in this fork,
deliberately left for future work:

| Issue | Why Left | Risk Carried |
|-------|----------|-------------|
| iOS crash in CameraEventClip (VLC null) | Platform-specific, unclear iOS roadmap | iOS users can't watch clips |
| Cache file accumulation in Share.tsx | Requires cache eviction strategy | Storage growth over time |
| `refreshFrequency` hardcoded in System.tsx | Minor UX, not a crash | Users always get 30s refresh |
| Filter state not persisted | Unclear if intentional | Users re-apply filters each session |
| PersistGate no loading/error UI | Requires design decision | Blank screen on slow storage |
| ToastAndroid-only errors (no iOS) | Requires platform abstraction | iOS users get no error feedback |

---

## Chapter 5 — File Map of This Fork

```
frigate-viewer/
├── upstream/
│   └── README.md              ← Frozen source manifest (where we came from)
├── archaeology/
│   ├── SCARY_SECTIONS.md      ← Deep-dive on dangerous inherited code
│   └── MODULE_MAP.md          ← Per-module INTENT/GHOSTS/DETRIMENT/TRANSPORTER
├── patches/
│   └── README.md              ← Rationale record for every change made
├── meta/
│   └── MANIFEST.md            ← Hermetic dependency + setup guide
└── MASTER_LOG.md              ← This file — the narrative of the fork
```

All actual code changes are made in-place in the source tree (not as
`.patch` files) to keep the working tree coherent.

---

## Appendix — Quick Reference: The Three Bugs That Cause The JSON Error

For anyone landing here from a crash report:

1. **`store/settings.ts:107`** — `NativeModules.I18nManager` is null on
   some devices. Fix: add `?.` and `?? 'en_US'`.

2. **`store/store.ts:29`** — `settingsMigrations(state)` should be
   `settingsMigrations(state.v1)`.

3. **`helpers/rest.ts:59,109`** — `response.json()` is called without
   checking `response.ok`. Any non-JSON HTTP response becomes a JSON error.

Issues 1 and 3 are what users see. Issue 2 causes Issue 1 to fire on
every launch rather than only the first.
