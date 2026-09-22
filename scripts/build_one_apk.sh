#!/usr/bin/env bash
# Build a single WebView affiliate APK.
# Usage: build_one_apk.sh "<App Name>" "<https://url>" "<icon.png|/absolute/path/to/icon.png>"
set -euo pipefail
setopt NULL_GLOB 2>/dev/null || true

NAME="${1:?App name required}"
URL="${2:?URL required}"
ICON_ARG="${3:?Icon file or path required}"

PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
LOGOS="${WEBINTOAPP_LOGOS:-$HOME/Downloads/BDT_LOGOS}"
DIST="$PROJECT/dist"
JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export JAVA_HOME ANDROID_HOME
export PATH="$JAVA_HOME/bin:$PATH"

cd "$PROJECT"
mkdir -p "$DIST"

if [[ "$ICON_ARG" = /* ]]; then
  ICON_PATH="$ICON_ARG"
else
  ICON_PATH="$LOGOS/$ICON_ARG"
fi

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9'
}

apk_name() {
  echo "$1" | tr ' ' '_' | tr -cd 'A-Za-z0-9_-'
}

derive_splash_colors() {
  python3 - "$1" <<'PY'
import sys
h = sys.argv[1].lstrip('#').upper()
r,g,b = int(h[0:2],16), int(h[2:4],16), int(h[4:6],16)

def clamp(x): return max(0, min(255, int(round(x))))

def mix(c, target, t):
    return clamp(c + (target - c) * t)

lum = (0.299*r + 0.587*g + 0.114*b)/255.0
if lum > 0.85:
    soft = (mix(r,255,0.08), mix(g,255,0.08), mix(b,255,0.08))
    deep = (mix(r,0,0.12), mix(g,0,0.12), mix(b,0,0.12))
elif lum < 0.08:
    soft = (mix(r,255,0.14), mix(g,255,0.14), mix(b,255,0.14))
    deep = (0,0,0)
else:
    soft = (mix(r,255,0.18), mix(g,255,0.18), mix(b,255,0.18))
    deep = (mix(r,0,0.22), mix(g,0,0.22), mix(b,0,0.22))

print(f"{soft[0]:02X}{soft[1]:02X}{soft[2]:02X} {h} {deep[0]:02X}{deep[1]:02X}{deep[2]:02X}")
PY
}

detect_logo_bg() {
  python3 - "$1" <<'PY'
from PIL import Image
import collections, sys
img = Image.open(sys.argv[1]).convert("RGBA")
w,h = img.size
opaque = []
for x in range(0, w, 2):
    for y in [0,1,2,h-1,h-2,h-3]:
        p = img.getpixel((x,y))
        if p[3] > 200:
            opaque.append(p[:3])
for y in range(0, h, 2):
    for x in [0,1,2,w-1,w-2,w-3]:
        p = img.getpixel((x,y))
        if p[3] > 200:
            opaque.append(p[:3])
top = collections.Counter(opaque).most_common(1)[0][0]
print(f"{top[0]:02X}{top[1]:02X}{top[2]:02X}")
PY
}

set_icons() {
  local src="$1"
  sips -z 48 48 "$src" --out "$PROJECT/app/src/main/res/mipmap-mdpi/ic_launcher.png" >/dev/null
  sips -z 72 72 "$src" --out "$PROJECT/app/src/main/res/mipmap-hdpi/ic_launcher.png" >/dev/null
  sips -z 96 96 "$src" --out "$PROJECT/app/src/main/res/mipmap-xhdpi/ic_launcher.png" >/dev/null
  sips -z 144 144 "$src" --out "$PROJECT/app/src/main/res/mipmap-xxhdpi/ic_launcher.png" >/dev/null
  sips -z 192 192 "$src" --out "$PROJECT/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" >/dev/null
}

write_strings() {
  local name="$1"
  local url="$2"
  local esc_name esc_url
  esc_name=$(printf '%s' "$name" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
  esc_url=$(printf '%s' "$url" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
  cat > "$PROJECT/app/src/main/res/values/strings.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">${esc_name}</string>
    <string name="app_url">${esc_url}</string>
</resources>
EOF
}

write_colors() {
  local soft="$1" base="$2" deep="$3"
  cat > "$PROJECT/app/src/main/res/values/colors.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="splash_background">#${base}</color>
    <color name="splash_background_deep">#${deep}</color>
    <color name="splash_background_soft">#${soft}</color>
    <color name="progress_accent">#FFFFFF</color>
</resources>
EOF
}

if [ ! -f "$PROJECT/app/src/main/java/com/webviewshell/app/MainActivity.java" ]; then
  echo "ERROR: MainActivity missing" >&2
  exit 1
fi

if [ ! -f "$ICON_PATH" ]; then
  echo "ERROR: missing icon $ICON_PATH" >&2
  exit 1
fi

SLUG=$(slugify "$NAME")
if [[ "$SLUG" =~ ^[0-9] ]]; then
  SLUG="app${SLUG}"
fi
APP_ID="com.${SLUG}.app"
OUT_APK="$DIST/$(apk_name "$NAME").apk"

echo "========== $NAME =========="
echo "package: $APP_ID"
echo "url:     $URL"
echo "icon:    $ICON_PATH"

BG=$(detect_logo_bg "$ICON_PATH")
read -r SOFT BASE DEEP <<< "$(derive_splash_colors "$BG")"
echo "splash:  #$BASE (soft=#$SOFT deep=#$DEEP)"

perl -i -pe 's/namespace = ".*"/namespace = "com.webviewshell.app"/' "$PROJECT/app/build.gradle.kts"
write_strings "$NAME" "$URL"
write_colors "$SOFT" "$BASE" "$DEEP"
set_icons "$ICON_PATH"
perl -i -pe "s/applicationId = \".*\"/applicationId = \"$APP_ID\"/" "$PROJECT/app/build.gradle.kts"

./gradlew assembleDebug --no-daemon -q
cp "$PROJECT/app/build/outputs/apk/debug/app-debug.apk" "$OUT_APK"
echo "OK -> $OUT_APK ($(du -h "$OUT_APK" | awk '{print $1}'))"
echo "APK_PATH=$OUT_APK"
