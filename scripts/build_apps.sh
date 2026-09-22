#!/usr/bin/env bash
# Build all WebView affiliate APKs with per-logo splash colors.
set -euo pipefail
setopt NULL_GLOB 2>/dev/null || true

PROJECT="/Users/aristotlebuenaventura/Documents/GitHub/WebIntoApp"
LOGOS="/Users/aristotlebuenaventura/Downloads/BDT_LOGOS"
DIST="$PROJECT/dist"
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export JAVA_HOME ANDROID_HOME
export PATH="$JAVA_HOME/bin:$PATH"

cd "$PROJECT"
mkdir -p "$DIST"

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9'
}

apk_name() {
  echo "$1" | tr ' ' '_' | tr -cd 'A-Za-z0-9_-'
}

# Args: hex (RRGGBB or #RRGGBB) -> prints soft, base, deep hex without #
derive_splash_colors() {
  python3 - "$1" <<'PY'
import sys
h = sys.argv[1].lstrip('#').upper()
r,g,b = int(h[0:2],16), int(h[2:4],16), int(h[4:6],16)

def clamp(x): return max(0, min(255, int(round(x))))

def mix(c, target, t):
    return clamp(c + (target - c) * t)

# Soft: lift toward white a bit (or toward mid-gray if already near white)
# Deep: pull toward black
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

# name|url|icon
APPS=(
  "MCW Affiliates|https://facai777.net/page/affiliate/login.jsp|M1.png"
  "Mega Cricket World Affiliates|https://cricbd88.club/page/affiliate/login.jsp|M2.png"
  "Banglabet Affiliates|https://bbtlink.co/affsignup|B1.png"
  "Bengalbet Affiliates|https://bgb88.club/page/affiliate/login.jsp|B2.png"
  "Deshislots Affiliates|https://deshislots88.net/page/affiliate/login.jsp|DESHISLOTS.png"
  "Banglawin Affiliates|https://banglawin88.net/page/affiliate/login.jsp|B4.png"
  "Banglaplus88 Affiliates|https://banglaplus88.net/page/affiliate/login.jsp|B3.png"
  "Khelaghor Affiliates|https://khelabd88.com/page/affiliate/login.jsp|K1.png"
  "TKBaazi Affiliates|https://tkbaazi.net/page/affiliate/login.jsp|TKBAAZI.png"
  "Joywin88 Affiliates|https://joywin88aff.com/|JOYWIN.png"
  "Ga888 Affiliates|https://ga888cam.com/page/affiliate/login.jsp|G1.png"
  "CF789 Affiliates|https://cf789-vn.top/page/affiliate/login.jsp|C1.png"
  "VND789 Affiliates|https://vnd789.vip/page/affiliate/login.jsp|VN9.png"
  "88Daga Affiliates|https://88daga.me/page/affiliate/login.jsp|D88.png"
)

# Ensure Java package is stable
if [ ! -f "$PROJECT/app/src/main/java/com/webviewshell/app/MainActivity.java" ]; then
  echo "ERROR: MainActivity missing" >&2
  exit 1
fi
perl -i -pe 's/namespace = ".*"/namespace = "com.webviewshell.app"/' "$PROJECT/app/build.gradle.kts"

total=${#APPS[@]}
i=0
for entry in "${APPS[@]}"; do
  i=$((i + 1))
  IFS='|' read -r NAME URL ICON <<< "$entry"
  SLUG=$(slugify "$NAME")
  # Package segments cannot start with a digit (e.g. 88daga...)
  if [[ "$SLUG" =~ ^[0-9] ]]; then
    SLUG="app${SLUG}"
  fi
  APP_ID="com.${SLUG}.app"
  OUT_APK="$DIST/$(apk_name "$NAME").apk"
  ICON_PATH="$LOGOS/$ICON"

  echo ""
  echo "========== [$i/$total] $NAME =========="
  echo "package: $APP_ID"
  echo "url:     $URL"
  echo "icon:    $ICON"

  if [ ! -f "$ICON_PATH" ]; then
    echo "ERROR: missing icon $ICON_PATH" >&2
    exit 1
  fi

  BG=$(detect_logo_bg "$ICON_PATH")
  read -r SOFT BASE DEEP <<< "$(derive_splash_colors "$BG")"
  echo "splash:  #$BASE (soft=#$SOFT deep=#$DEEP)"

  write_strings "$NAME" "$URL"
  write_colors "$SOFT" "$BASE" "$DEEP"
  set_icons "$ICON_PATH"
  perl -i -pe "s/applicationId = \".*\"/applicationId = \"$APP_ID\"/" "$PROJECT/app/build.gradle.kts"

  ./gradlew assembleDebug --no-daemon -q
  cp "$PROJECT/app/build/outputs/apk/debug/app-debug.apk" "$OUT_APK"
  echo "OK -> $OUT_APK ($(du -h "$OUT_APK" | awk '{print $1}'))"
done

echo ""
echo "========== ALL DONE ($total apps) =========="
ls -lh "$DIST"/*.apk
