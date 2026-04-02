# MANIFEST.md — Hermetic Dependency Reference

> Goal: a developer on a blank machine should be able to read this
> document and reach a running dev build without using Google once.

---

## 1. Host Machine Requirements

| Requirement      | Minimum Version | Notes                                        |
|------------------|-----------------|----------------------------------------------|
| OS               | Ubuntu 22.04 / macOS 13+ | Windows via WSL2 for Android only  |
| Node.js          | 18.x            | Enforced by `engines.node` in package.json   |
| npm              | 9.x             | Comes with Node 18                           |
| Java (JDK)       | 17              | Required by Gradle for Android builds        |
| Android SDK      | API 33          | Install via Android Studio SDK Manager       |
| Android NDK      | r25c            | Set `ANDROID_NDK_HOME` env var               |
| Xcode            | 15+             | iOS only; macOS required                     |
| CocoaPods        | 1.14+           | iOS only: `sudo gem install cocoapods`       |
| Ruby             | 3.x             | CocoaPods dependency on macOS                |

---

## 2. Environment Variables

```bash
# Required for Android builds
export ANDROID_HOME=$HOME/Android/Sdk
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/25.2.9519653
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/tools
export PATH=$PATH:$ANDROID_HOME/tools/bin
export PATH=$PATH:$ANDROID_HOME/platform-tools

# Required for Firebase (Crashlytics)
# Place google-services.json at: android/app/google-services.json
# Place GoogleService-Info.plist at: ios/GoogleService-Info.plist
```

---

## 3. Runtime Dependencies (from `package.json`)

### Production

| Package                                    | Version    | Purpose                                           |
|--------------------------------------------|------------|---------------------------------------------------|
| `react`                                    | 18.2.0     | UI framework                                      |
| `react-native`                             | 0.73.9     | Mobile runtime                                    |
| `@reduxjs/toolkit`                         | ^1.9.5     | State management                                  |
| `redux`                                    | ^4.2.1     | Redux core                                        |
| `redux-persist`                            | ^6.0.0     | Async state persistence to AsyncStorage           |
| `react-redux`                              | ^8.1.2     | React bindings for Redux                          |
| `@react-native-async-storage/async-storage`| 2.0.0      | On-device key-value storage (used by redux-persist)|
| `react-native-navigation`                  | ^7.40.1    | Native navigation (Wix RNN, not React Navigation) |
| `@react-native-firebase/app`               | ^21.0.0    | Firebase core                                     |
| `@react-native-firebase/crashlytics`       | ^21.0.0    | Crash reporting                                   |
| `react-intl`                               | ^6.4.7     | i18n / locale formatting                          |
| `formik`                                   | ^2.4.5     | Form state management                             |
| `yup`                                      | ^1.4.0     | Form validation schemas                           |
| `date-fns`                                 | ^2.30.0    | Date formatting utilities                         |
| `buffer`                                   | ^6.0.3     | Node Buffer polyfill (used for Basic Auth base64) |
| `rn-fetch-blob`                            | ^0.12.0    | File downloads to device cache                    |
| `react-native-share`                       | ^11.0.3    | Native share sheet                                |
| `react-native-gesture-handler`             | ^2.13.1    | Gesture system (required by reanimated)           |
| `react-native-reanimated`                  | ^3.15.2    | Animated transitions                              |
| `react-native-ui-lib`                      | ^7.9.1     | UI component library (Wix)                        |
| `react-native-svg-charts`                  | github fork| Charts for system stats (forked from piwko28)     |
| `react-native-reanimated-table`            | ^0.0.2     | Table component                                   |
| `@ant-design/icons-react-native`           | ^2.3.2     | Icon set                                          |
| `@lunarr/vlc-player`                       | ^1.0.5     | VLC-based video player for RTSP streams           |

### Development

| Package                          | Version  | Purpose                      |
|----------------------------------|----------|------------------------------|
| `typescript`                     | 5.0.4    | Static typing                |
| `eslint`                         | ^8.19.0  | Linting                      |
| `prettier`                       | ^2.8.8   | Code formatting              |
| `jest`                           | ^29.6.3  | Unit testing                 |
| `babel-jest`                     | ^29.6.3  | Babel transform for tests    |
| `react-native-asset`             | ^2.1.1   | Font/asset linking           |

---

## 4. Android-Specific Requirements

```
android/app/google-services.json   ← Firebase config (NOT committed; obtain from Firebase Console)
android/local.properties           ← Must contain: sdk.dir=/path/to/Android/Sdk
```

### Gradle versions (android/gradle/wrapper/gradle-wrapper.properties)
Check the file for exact versions. Typical for RN 0.73.x:
- Gradle: 8.x
- Android Gradle Plugin: 8.x

### Build Variants
- `debug` — connects to Metro bundler
- `release` — signed AAB/APK; requires keystore

### Signing (release builds)
Create `android/keystore.properties`:
```
storeFile={{PATH_TO_KEYSTORE}}
storePassword={{KEYSTORE_PASSWORD}}
keyAlias={{KEY_ALIAS}}
keyPassword={{KEY_PASSWORD}}
```

---

## 5. iOS-Specific Requirements

```bash
cd ios && pod install
```

```
ios/GoogleService-Info.plist   ← Firebase config (NOT committed; obtain from Firebase Console)
```

> RTSP (VLC player) does not work on iOS. The `@lunarr/vlc-player`
> package is Android-only in this project.

---

## 6. First-Time Setup (Step by Step)

```bash
# 1. Clone the repo
git clone {{REPO_URL}}
cd frigate-viewer

# 2. Install JS dependencies
npm install

# 3a. Android — link assets
npx react-native-asset

# 3b. iOS — install pods
cd ios && pod install && cd ..

# 4. Place Firebase config files (see Section 4/5 above)

# 5. Start Metro bundler
npm start

# 6a. Run on Android device/emulator
npm run android

# 6b. Run on iOS simulator (macOS only)
npm run ios
```

---

## 7. Runtime Configuration (User-Facing)

The app requires a running **Frigate NVR** instance accessible on the
local network. Required configuration entered in-app:

| Setting    | Description                                            |
|------------|--------------------------------------------------------|
| Protocol   | `http` or `https`                                      |
| Host       | IP address or hostname of the Frigate server           |
| Port       | Default `5000` for Frigate                             |
| Path       | Optional sub-path if behind a reverse proxy            |
| Auth       | `none`, `basic` (username/password), or `frigate`      |

The Frigate API base URL is constructed as:
`{{PROTOCOL}}://{{HOST}}:{{PORT}}/{{PATH}}/api`

---

## 8. External Services

| Service      | Required? | Notes                                                  |
|--------------|-----------|--------------------------------------------------------|
| Firebase     | Yes       | Crashlytics for error reporting. Disable via settings. |
| Frigate NVR  | Yes       | The actual backend — self-hosted, user-provided        |

---

## 9. Known Platform Constraints

- **Android**: Full feature support
- **iOS**: No RTSP live view (VLC player unsupported)
- **Locale**: `NativeModules.I18nManager.localeIdentifier` can return
  `null` on some Android devices/ROMs — see `/archaeology/SCARY_SECTIONS.md#scare-1`
