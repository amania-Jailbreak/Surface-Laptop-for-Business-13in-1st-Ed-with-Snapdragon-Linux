#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
OUTPUT=${1:-}
[[ -n "$OUTPUT" ]] || { printf 'usage: %s OUTPUT.apk\n' "$0" >&2; exit 2; }

need() {
	command -v "$1" >/dev/null 2>&1 || {
		printf 'ERROR: command not found: %s\n' "$1" >&2
		exit 1
	}
}

AAPT2=${AAPT2:-aapt2}
D8=${D8:-}
DX=${DX:-/usr/lib/android-sdk/build-tools/debian/dx}
APKSIGNER=${APKSIGNER:-apksigner}
ZIPALIGN=${ZIPALIGN:-zipalign}
ANDROID_JAR=${ANDROID_JAR:-}
ANDROID_FRAMEWORK_RES_APK=${ANDROID_FRAMEWORK_RES_APK:-}

need javac
need jar
need keytool
need zip
need "$AAPT2"
need "$APKSIGNER"
need "$ZIPALIGN"
if [[ -n "$D8" ]]; then
	need "$D8"
elif command -v d8 >/dev/null 2>&1; then
	D8=d8
elif [[ ! -x "$DX" ]]; then
	printf 'ERROR: neither d8 nor dx was found\n' >&2
	exit 1
fi
[[ -f "$ANDROID_JAR" ]] || {
	printf 'ERROR: set ANDROID_JAR to an Android platform android.jar\n' >&2
	exit 1
}
[[ -f "$ANDROID_FRAMEWORK_RES_APK" ]] || {
	printf 'ERROR: set ANDROID_FRAMEWORK_RES_APK to platform framework-res.apk\n' >&2
	exit 1
}

BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT
mkdir -p "$BUILD_DIR/classes" "$BUILD_DIR/dex" "$(dirname "$OUTPUT")"

"$AAPT2" compile --dir "$APP_DIR/res" -o "$BUILD_DIR/resources.zip"
"$AAPT2" link \
	-I "$ANDROID_FRAMEWORK_RES_APK" \
	--manifest "$APP_DIR/AndroidManifest.xml" \
	-R "$BUILD_DIR/resources.zip" \
	--min-sdk-version 29 \
	--target-sdk-version 35 \
	--auto-add-overlay \
	-o "$BUILD_DIR/base.apk"

mapfile -t JAVA_SOURCES < <(find "$APP_DIR/src" -type f -name '*.java' -print | sort)
[[ ${#JAVA_SOURCES[@]} -gt 0 ]] || { printf 'ERROR: no Java sources found\n' >&2; exit 1; }
# Keep the APK compatible with the platform runtime used by Waydroid.  The
# Debian dx fallback does not desugar Java 8 lambdas/invoke-custom reliably.
STUB_JAR="$BUILD_DIR/platform-stubs.jar"
mapfile -t STUB_SOURCES < <(find "$APP_DIR/stubs" -type f -name '*.java' -print 2>/dev/null | sort)
if [[ ${#STUB_SOURCES[@]} -gt 0 ]]; then
	mkdir -p "$BUILD_DIR/stubs"
	javac -source 7 -target 7 -classpath "$ANDROID_JAR" -d "$BUILD_DIR/stubs" "${STUB_SOURCES[@]}"
	(cd "$BUILD_DIR/stubs" && jar cf "$STUB_JAR" .)
	JAVAC_CLASSPATH="$ANDROID_JAR:$STUB_JAR"
else
	JAVAC_CLASSPATH="$ANDROID_JAR"
fi
javac -source 7 -target 7 -classpath "$JAVAC_CLASSPATH" -d "$BUILD_DIR/classes" "${JAVA_SOURCES[@]}"
if [[ -n "$D8" ]]; then
	mapfile -t CLASS_FILES < <(find "$BUILD_DIR/classes" -type f -name '*.class' -print | sort)
	if [[ -f "$STUB_JAR" ]]; then
		"$D8" --lib "$ANDROID_JAR" --lib "$STUB_JAR" --output "$BUILD_DIR/dex" "${CLASS_FILES[@]}"
	else
		"$D8" --lib "$ANDROID_JAR" --output "$BUILD_DIR/dex" "${CLASS_FILES[@]}"
	fi
else
	"$DX" --dex --min-sdk-version=29 --output="$BUILD_DIR/dex/classes.dex" "$BUILD_DIR/classes"
fi

cp "$BUILD_DIR/base.apk" "$BUILD_DIR/unsigned.apk"
(cd "$BUILD_DIR/dex" && zip -q "$BUILD_DIR/unsigned.apk" classes.dex)

keytool -genkeypair -v \
	-keystore "$BUILD_DIR/debug.keystore" \
	-storepass android -keypass android \
	-alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
	-dname 'CN=Android Debug,O=Android,C=US' >/dev/null 2>&1
"$ZIPALIGN" -f 4 "$BUILD_DIR/unsigned.apk" "$BUILD_DIR/aligned.apk"
"$APKSIGNER" sign \
	--ks "$BUILD_DIR/debug.keystore" --ks-pass pass:android \
	--key-pass pass:android --out "$OUTPUT" "$BUILD_DIR/aligned.apk"
"$APKSIGNER" verify "$OUTPUT"
test -s "$OUTPUT"
printf 'Built %s\n' "$OUTPUT"
