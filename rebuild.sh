#!/usr/bin/env bash
# =============================================================================
# rebuild.sh — Frigate Viewer Hermetic Bootstrap
# Sovereign Archive Protocol | PATCH eecf115
#
# PURPOSE:
#   Verify the host environment, install all JS dependencies, link native
#   assets, and print a precise "what to do next" summary. Designed to
#   run on a blank machine and produce a working dev environment in one step.
#
# USAGE:
#   bash rebuild.sh              — full environment check + install
#   bash rebuild.sh --check-only — verify environment, do not install
#   bash rebuild.sh --android    — also attempt to start the Android build
#
# REQUIREMENTS:
#   - Node.js 18+
#   - Java 17 (JDK)
#   - Android SDK (ANDROID_HOME set)
#   - npm 9+
# =============================================================================

set -euo pipefail

# ─── Colours ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
YEL='\033[1;33m'
GRN='\033[0;32m'
BLU='\033[0;34m'
CYN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── State ───────────────────────────────────────────────────────────────────
ERRORS=0
WARNINGS=0
CHECK_ONLY=false
RUN_ANDROID=false

for arg in "$@"; do
  case $arg in
    --check-only) CHECK_ONLY=true ;;
    --android)    RUN_ANDROID=true ;;
  esac
done

# ─── Helpers ─────────────────────────────────────────────────────────────────
ok()   { echo -e "  ${GRN}✓${NC}  $1"; }
warn() { echo -e "  ${YEL}⚠${NC}  $1"; ((WARNINGS++)); }
fail() { echo -e "  ${RED}✗${NC}  $1"; ((ERRORS++)); }
info() { echo -e "  ${BLU}→${NC}  $1"; }
head() { echo -e "\n${BOLD}${CYN}$1${NC}"; }

require_cmd() {
  local cmd="$1"
  local label="${2:-$cmd}"
  if ! command -v "$cmd" &>/dev/null; then
    fail "$label not found in PATH"
    return 1
  fi
  return 0
}

version_gte() {
  # version_gte "18.2.0" "18" → true if first arg >= second
  local actual="$1"
  local required="$2"
  printf '%s\n%s\n' "$required" "$actual" | sort -V -C
}

# ─── Banner ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║     FRIGATE VIEWER — SOVEREIGN ARCHIVE REBUILD       ║${NC}"
echo -e "${BOLD}║     Integrity Hash: eecf115                          ║${NC}"
echo -e "${BOLD}║     Branch: claude/fix-startup-json-error-Vusi9      ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# ─── SECTION 1: Node.js ──────────────────────────────────────────────────────
head "[ 1/6 ] Node.js"
if require_cmd node "Node.js"; then
  NODE_VER=$(node --version | sed 's/v//')
  if version_gte "$NODE_VER" "18"; then
    ok "Node.js $NODE_VER (>=18 required)"
  else
    fail "Node.js $NODE_VER is too old. Install v18+ from https://nodejs.org"
  fi
else
  info "Install Node.js 18 LTS: https://nodejs.org/en/download"
fi

# ─── SECTION 2: npm ──────────────────────────────────────────────────────────
head "[ 2/6 ] npm"
if require_cmd npm; then
  NPM_VER=$(npm --version)
  if version_gte "$NPM_VER" "9"; then
    ok "npm $NPM_VER (>=9 required)"
  else
    warn "npm $NPM_VER is older than recommended (9+). Run: npm install -g npm"
  fi
fi

# ─── SECTION 3: Java ─────────────────────────────────────────────────────────
head "[ 3/6 ] Java (JDK)"
if require_cmd java "Java"; then
  # java -version writes to stderr
  JAVA_VER=$(java -version 2>&1 | head -1 | sed 's/.*version "\([0-9]*\).*/\1/')
  if [ "$JAVA_VER" = "17" ]; then
    ok "Java $JAVA_VER (17 required)"
  elif [ "$JAVA_VER" -gt "17" ] 2>/dev/null; then
    warn "Java $JAVA_VER detected. Java 17 is recommended for React Native 0.73.x"
    info "Switch with: sudo update-alternatives --config java"
  else
    fail "Java $JAVA_VER too old. Install JDK 17:"
    info "  Ubuntu: sudo apt install openjdk-17-jdk"
    info "  macOS:  brew install openjdk@17"
  fi
else
  info "Install JDK 17:"
  info "  Ubuntu: sudo apt install openjdk-17-jdk"
  info "  macOS:  brew install openjdk@17"
fi

# ─── SECTION 4: Android SDK ──────────────────────────────────────────────────
head "[ 4/6 ] Android SDK"
if [ -z "${ANDROID_HOME:-}" ]; then
  fail "ANDROID_HOME is not set"
  info "Add to your shell profile (~/.bashrc or ~/.zshrc):"
  info "  export ANDROID_HOME=\$HOME/Android/Sdk"
  info "  export PATH=\$PATH:\$ANDROID_HOME/platform-tools"
else
  ok "ANDROID_HOME=$ANDROID_HOME"
  if [ -d "$ANDROID_HOME/platform-tools" ]; then
    ok "platform-tools found"
  else
    warn "platform-tools not found in ANDROID_HOME"
    info "Install via Android Studio: SDK Manager → SDK Tools → Android SDK Platform-Tools"
  fi
  if [ -d "$ANDROID_HOME/build-tools" ]; then
    ok "build-tools found"
  else
    warn "build-tools not found"
    info "Install via Android Studio: SDK Manager → SDK Platforms → Android API 33"
  fi
fi

# Check for connected device / emulator
head "[ 5/6 ] Android Device / Emulator"
if command -v adb &>/dev/null; then
  DEVICES=$(adb devices 2>/dev/null | grep -v "List of devices" | grep "device$" | wc -l | tr -d ' ')
  if [ "$DEVICES" -gt "0" ]; then
    ok "$DEVICES device(s) / emulator(s) connected"
    adb devices | grep "device$" | while read -r line; do
      info "  $line"
    done
  else
    warn "No Android device or emulator connected"
    info "Start an emulator in Android Studio, or connect a device with USB debugging enabled"
  fi
else
  warn "adb not in PATH — cannot check for devices"
  info "Add \$ANDROID_HOME/platform-tools to your PATH"
fi

# ─── SECTION 5: Firebase config ──────────────────────────────────────────────
head "[ 6/6 ] Firebase Configuration"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/android/app/google-services.json" ]; then
  ok "android/app/google-services.json present"
else
  fail "android/app/google-services.json MISSING"
  info "Download from: Firebase Console → Project Settings → Your Android App"
  info "Place at: android/app/google-services.json"
fi

if [ -f "$SCRIPT_DIR/ios/GoogleService-Info.plist" ]; then
  ok "ios/GoogleService-Info.plist present"
else
  warn "ios/GoogleService-Info.plist missing (only required for iOS builds)"
  info "Download from: Firebase Console → Project Settings → Your iOS App"
fi

# ─── INSTALL ─────────────────────────────────────────────────────────────────
if $CHECK_ONLY; then
  echo ""
  info "Check-only mode: skipping install."
else
  head "Installing JS dependencies"
  if [ "$ERRORS" -gt "0" ]; then
    echo ""
    echo -e "${RED}${BOLD}Cannot install: $ERRORS error(s) must be resolved first.${NC}"
    echo -e "Fix the issues above and re-run: ${CYN}bash rebuild.sh${NC}"
    exit 1
  fi

  cd "$SCRIPT_DIR"
  echo -e "  Running ${CYN}npm install${NC}..."
  npm install --silent
  ok "npm install complete"

  echo -e "  Running ${CYN}npx react-native-asset${NC}..."
  npx react-native-asset 2>/dev/null || warn "react-native-asset had warnings (may be safe to ignore)"
  ok "Asset linking complete"
fi

# ─── ANDROID BUILD ───────────────────────────────────────────────────────────
if $RUN_ANDROID && ! $CHECK_ONLY; then
  if [ "$ERRORS" -eq "0" ]; then
    head "Starting Android build"
    echo -e "  Running ${CYN}npm run android${NC}..."
    echo -e "  ${YEL}Note: Metro bundler will start in this terminal.${NC}"
    npm run android
  else
    warn "Skipping Android build due to errors above"
  fi
fi

# ─── SUMMARY ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}════════════════════════════════════════${NC}"
if [ "$ERRORS" -gt "0" ]; then
  echo -e "${RED}${BOLD}  RESULT: $ERRORS error(s), $WARNINGS warning(s)${NC}"
  echo -e "  Resolve errors above before building."
elif [ "$WARNINGS" -gt "0" ]; then
  echo -e "${YEL}${BOLD}  RESULT: Ready with $WARNINGS warning(s)${NC}"
else
  echo -e "${GRN}${BOLD}  RESULT: Environment fully verified${NC}"
fi
echo -e "${BOLD}════════════════════════════════════════${NC}"
echo ""

if [ "$ERRORS" -eq "0" ] && ! $CHECK_ONLY; then
  echo -e "${BOLD}Next steps:${NC}"
  echo -e "  1. ${CYN}npm start${NC}                  — start Metro bundler"
  echo -e "  2. ${CYN}npm run android${NC}             — build and deploy to device"
  echo -e "  3. Open the app and configure your Frigate server in Settings"
  echo ""
  echo -e "  For release build:"
  echo -e "  ${CYN}cd android && ./gradlew bundleRelease${NC}"
  echo ""
fi

exit $ERRORS
