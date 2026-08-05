#!/usr/bin/env bash
# Build WebView APKs from a list of apps (name, url, icon).
set -euo pipefail

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
  # lowercase, keep alnum only
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9'
}

apk_name() {
  echo "$1" | tr ' ' '_' | tr -cd 'A-Za-z0-9_-'
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
  # Escape XML special chars
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

set_application_id() {
  local app_id="$1"
  # Update both namespace and applicationId so each app is unique
  perl -i -pe "s/namespace = \".*\"/namespace = \"$app_id\"/" "$PROJECT/app/build.gradle.kts"
  perl -i -pe "s/applicationId = \".*\"/applicationId = \"$app_id\"/" "$PROJECT/app/build.gradle.kts"
}

# Keep Java source package fixed; applicationId can differ from folder path.
# Android Gradle Plugin requires namespace to match R package generation path OR we keep namespace
# matching the Java package folder. Safer: keep namespace as com.webviewshell.app always,
# only change applicationId.
ensure_stable_namespace() {
  # Move/create Java sources under com.webviewshell.app once
  local src_old="$PROJECT/app/src/main/java/com/testingaris/app"
  local src_new="$PROJECT/app/src/main/java/com/webviewshell/app"
  if [ -d "$src_old" ] && [ ! -d "$src_new" ]; then
    mkdir -p "$src_new"
    if [ -f "$src_old/MainActivity.java" ]; then
      sed 's/package com\.testingaris\.app;/package com.webviewshell.app;/' \
        "$src_old/MainActivity.java" > "$src_new/MainActivity.java"
      rm -rf "$PROJECT/app/src/main/java/com/testingaris"
    fi
  fi
  if [ ! -f "$src_new/MainActivity.java" ]; then
    echo "ERROR: MainActivity missing at $src_new" >&2
    exit 1
  fi
  perl -i -pe 's/namespace = ".*"/namespace = "com.webviewshell.app"/' "$PROJECT/app/build.gradle.kts"
}

# Format: name|url|icon
APPS=(
  "MCW Affiliates|https://facai777.net/page/affiliate/login.jsp|M1.png"
  "Mega Cricket World Affiliates|https://cricbd88.club/page/affiliate/login.jsp|M2.png"
  "Banglabet Affiliates|https://bbetbd88.com/page/affiliate/login.jsp|B1.png"
  "Bengalbet Affiliates|https://bgb88.club/page/affiliate/login.jsp|B2.png"
  "Deshislots Affiliates|https://deshislots88.net/page/affiliate/login.jsp|DESHISLOTS.png"
  "Banglawin Affiliates|https://banglawin88.net/page/affiliate/login.jsp|B4.png"
  "Banglaplus88 Affiliates|https://banglaplus88.net/page/affiliate/login.jsp|B3.png"
  "Khelaghor Affiliates|https://khelabd88.com/page/affiliate/login.jsp|K1.png"
  "TKBaazi Affiliates|https://tkbaazi.net/page/affiliate/login.jsp|TKBAAZI.png"
  "Joywin88 Affiliates|https://joywin88aff.com/|JOYWIN.png"
)

ensure_stable_namespace

total=${#APPS[@]}
i=0
for entry in "${APPS[@]}"; do
  i=$((i + 1))
  IFS='|' read -r NAME URL ICON <<< "$entry"
  SLUG=$(slugify "$NAME")
  APP_ID="com.${SLUG}.app"
  OUT_APK="$DIST/$(apk_name "$NAME").apk"
  ICON_PATH="$LOGOS/$ICON"

  echo ""
  echo "========== [$i/$total] $NAME =========="
  echo "package: $APP_ID"
  echo "url:     $URL"
  echo "icon:    $ICON"
  echo "out:     $OUT_APK"

  if [ ! -f "$ICON_PATH" ]; then
    echo "ERROR: missing icon $ICON_PATH" >&2
    exit 1
  fi

  write_strings "$NAME" "$URL"
  set_icons "$ICON_PATH"
  # Only applicationId changes per app; namespace stays com.webviewshell.app
  perl -i -pe "s/applicationId = \".*\"/applicationId = \"$APP_ID\"/" "$PROJECT/app/build.gradle.kts"

  ./gradlew assembleDebug --no-daemon -q
  cp "$PROJECT/app/build/outputs/apk/debug/app-debug.apk" "$OUT_APK"
  echo "OK -> $OUT_APK ($(du -h "$OUT_APK" | awk '{print $1}'))"
done

echo ""
echo "========== ALL DONE =========="
ls -lh "$DIST"/*.apk
