# /finalized — The Materialized Reality

This silo represents the **living, patched result** of the fork.

Unlike a traditional `/finalized` that would contain compiled artefacts
or a separate copy of the source, this React Native project's
"materialized reality" IS the source tree at the repository root.
The `/finalized` silo therefore serves as the **index and verification
record** of what the patched state looks like, and what each patched
file's final intent is.

---

## Verification: What "Finalized" Means Here

A file is "finalized" in this context when:
1. All patches from `/patches/README.md` targeting it are **Applied**
2. Its behaviour matches the requirements in the Logic Traceability Matrix
   (see `SOVEREIGN_ARCHIVE.md` Layer 2)
3. It has corresponding documentation in `archaeology/MODULE_MAP.md`

---

## Patched File Manifest

The following files were modified from upstream by this fork.
Each entry shows the final intent of the file and which patch(es) touched it.

| File | Final Intent | Patches | Key Change |
|------|-------------|---------|------------|
| `store/settings.ts` | Define settings shape; safely initialize with device locale | PATCH-01 | `NativeModules.I18nManager?.localeIdentifier ?? 'en_US'` |
| `store/store.ts` | Wire Redux + persistence; run migrations correctly | PATCH-02 | `settingsMigrations(state.v1)` not `state` |
| `helpers/rest.ts` | HTTP to Frigate API with correct error propagation | PATCH-03 | `response.ok` guard before every `.json()` |
| `helpers/rest.messages.ts` | i18n strings for HTTP errors | PATCH-03 | Added `error.httpError` key |
| `views/system/System.tsx` | Stats dashboard with reliable loading state | PATCH-04 | `setLoading(false)` moved to `.finally()` |
| `views/camera-events/CameraEvents.tsx` | Event list with user-visible error feedback | PATCH-05 | Toast on catch; `.catch()` on loadMore |
| `views/camera-events/CameraEvent.tsx` | Event card mutations with failure feedback | PATCH-06 | `.catch()` with toast on delete/retain/unretain |
| `views/camera-events/Share.tsx` | File share with null-safe download result | PATCH-07 | Early return if `download()` → `undefined`; safe error stringify |
| `views/camera-events/messages.ts` | i18n strings for event view errors | PATCH-05,06 | Added `error.loadFailed`, `error.actionFailed` |

---

## Unmodified Files (Unchanged from Upstream)

All files not listed above are byte-for-byte identical to the upstream
fork point at commit `6e4dcf1`. They carry the risks documented in
`archaeology/SCARY_SECTIONS.md` (specifically SCARE-6 and SCARE-7
which were identified but not patched in this fork).

Notable unmodified files and their known residual risks:

| File | Residual Risk |
|------|--------------|
| `helpers/redux.tsx` | PersistGate has no loading prop or error boundary |
| `views/camera-event-clip/CameraEventClip.tsx` | `JSON.stringify(err)` can throw; iOS VLC crash |
| `views/report/Report.tsx` | `JSON.stringify()` has no try-catch |

---

## Build Artefacts

React Native does not produce output files in the source tree.
Build output locations:

| Platform | Command | Output Location |
|----------|---------|-----------------|
| Android debug APK | `npm run android` | `android/app/build/outputs/apk/debug/` |
| Android release APK | `cd android && ./gradlew assembleRelease` | `android/app/build/outputs/apk/release/` |
| Android release AAB | `npm run android:bundle` | `android/app/build/outputs/bundle/release/` |
| iOS (macOS only) | `npm run ios` | Xcode derived data / device |

---

## Integrity Verification

To verify this silo matches the documented patches exactly:

```bash
# Verify PATCH-01 is applied
grep -n "I18nManager?." store/settings.ts
# Expected: line 107: region: NativeModules.I18nManager?.localeIdentifier ?? 'en_US',

# Verify PATCH-02 is applied
grep -n "state\.v1" store/store.ts
# Expected: v1: settingsMigrations(state.v1),

# Verify PATCH-03 is applied
grep -n "response.ok" helpers/rest.ts
# Expected: 2 occurrences (login + query functions)

# Verify PATCH-04 is applied
grep -n "finally" views/system/System.tsx
# Expected: .finally(() => { setLoading(false); })

# Verify PATCH-07 is applied
grep -n "if (!path)" views/camera-events/Share.tsx
# Expected: 2 occurrences (shareSnapshot + shareClip)
```

All checks can be run at once:
```bash
bash rebuild.sh --check-only
```
