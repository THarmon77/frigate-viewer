# /upstream — Frozen Source Reference

This directory marks the **conceptual origin point** of the fork.
It does not duplicate source files (they exist in the repo root).
Instead, it serves as a frozen manifest: a record of exactly what
was inherited and from where.

## Origin Repository

| Field        | Value                                                          |
|--------------|----------------------------------------------------------------|
| Source       | `https://github.com/sp-engineering/frigate-viewer`             |
| Forked From  | `tharmon77/frigate-viewer`                                     |
| Fork Point   | commit `6e4dcf1` — "Revise README to update project description" |
| App Version  | `14.3.0` (package.json)                                        |
| RN Version   | `0.73.9`                                                       |
| Fork Date    | 2026-04-01                                                     |

## What Was Inherited (As-Is)

Every file at the repo root at fork time is upstream. The fork
introduced **no functional changes** at the moment of forking.

The following modules are the most architecturally significant
inherited pieces (see `/archaeology/MODULE_MAP.md` for deep docs):

| Module                          | Role                                        |
|---------------------------------|---------------------------------------------|
| `store/settings.ts`             | Redux state shape + migrations              |
| `store/store.ts`                | redux-persist configuration                 |
| `helpers/rest.ts`               | All HTTP communication with Frigate API     |
| `helpers/redux.tsx`             | PersistGate + Provider HOC                  |
| `views/camera-events/`          | Event list, event card, share, clip viewer  |
| `views/system/System.tsx`       | System stats polling dashboard              |

## Known Defects Inherited at Fork Point

See `/archaeology/SCARY_SECTIONS.md` for full details.
Summary of critical bugs brought in from upstream:

1. **Startup crash** — `NativeModules.I18nManager` accessed without null-guard at module load time (`store/settings.ts:107`)
2. **Transform type mismatch** — `settingsMigrations` receives `SettingsState` instead of `ISettings`, corrupting migration logic (`store/store.ts:27-30`)
3. **Unguarded `response.json()`** — no `response.ok` check before JSON parsing (`helpers/rest.ts:59,109`)
4. **Numerous missing `.catch()` handlers** — silent failures across views

All patches for the above live in `/patches/`.
