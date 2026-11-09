#!/usr/bin/env bash
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
USBTOOL="$ROOT/USBTool"
VA_DIR="$ROOT/.virtualapp-src"
VA_COMMIT="0535cbef5601726d2840aec97f286204cd6d1151"

test -f "$USBTOOL/settings.gradle"
test -f "$USBTOOL/app/build.gradle"

if [ ! -d "$VA_DIR/.git" ]; then
  git clone --filter=blob:none --no-checkout https://github.com/asLody/VirtualApp.git "$VA_DIR"
fi
git -C "$VA_DIR" fetch --depth 1 origin "$VA_COMMIT"
git -C "$VA_DIR" checkout --detach "$VA_COMMIT"
test -d "$VA_DIR/VirtualApp/lib/src/main/java/com/lody/virtual"

rm -rf "$USBTOOL/va-lib"
mkdir -p "$USBTOOL/va-lib"
cp -a "$VA_DIR/VirtualApp/lib/src/main/." "$USBTOOL/va-lib/src-main/"
mkdir -p "$USBTOOL/va-lib/src/main"
# Keep the upstream source tree intact; Gradle consumes its normal src/main layout.
rm -rf "$USBTOOL/va-lib/src-main"
cp -a "$VA_DIR/VirtualApp/lib/src/main" "$USBTOOL/va-lib/src"
cp "$VA_DIR/VirtualApp/lib/proguard-rules.pro" "$USBTOOL/va-lib/" 2>/dev/null || true

cat > "$USBTOOL/va-lib/build.gradle" <<'GRADLE'
plugins {
    id 'com.android.library'
}

android {
    namespace 'com.lody.virtual'
    compileSdk 35

    defaultConfig {
        minSdk 29
        targetSdk 29
    }

    // Phase 14 imports and compiles the Java/AIDL engine layer only.
    // The upstream native target uses obsolete gnustl_static and excludes arm64-v8a.
    // Native hooking and IO redirection are deliberately not advertised as active yet.
    sourceSets {
        main {
            java.srcDirs = ['src/main/java']
            aidl.srcDirs = ['src/main/aidl']
            res.srcDirs = ['src/main/res']
            manifest.srcFile 'src/main/AndroidManifest.xml'
        }
    }

    buildFeatures {
        aidl true
        buildConfig true
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}

dependencies {
    implementation fileTree(dir: 'libs', include: ['*.jar'])
}
GRADLE

python3 - "$USBTOOL/settings.gradle" "$USBTOOL/app/build.gradle" <<'PY'
import pathlib, sys
settings = pathlib.Path(sys.argv[1])
app = pathlib.Path(sys.argv[2])
s = settings.read_text()
if "include ':va-lib'" not in s and 'include(":va-lib")' not in s:
    s += "\ninclude ':va-lib'\nproject(':va-lib').projectDir = file('va-lib')\n"
settings.write_text(s)
a = app.read_text()
if "project(':va-lib')" not in a and 'project(":va-lib")' not in a:
    a += "\n\ndependencies {\n    implementation project(':va-lib')\n}\n"
app.write_text(a)
PY

# Java 17's stricter generic inference exposes raw List<?> return types in this
# legacy helper. Keep the runtime behavior unchanged and make the ResolveInfo cast explicit.
python3 - "$USBTOOL/va-lib/src/main/java/com/lody/virtual/client/hook/proxies/pm/MethodProxies.java" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
needle = "ParceledListSlice.getList.call(_hostResult)"
fixed = "(List<ResolveInfo>) (List<?>) ParceledListSlice.getList.call(_hostResult)"
if needle in s:
    s = s.replace(needle, fixed)
p.write_text(s)
if fixed not in s:
    raise SystemExit("Phase 14 generic compatibility patch did not apply")
print("Patched legacy ParceledListSlice generic casts:", s.count(fixed))
PY

# Keep a machine-readable provenance and capability boundary in the build output.
cat > "$USBTOOL/VA_INTEGRATION_PHASE14.txt" <<EOF
VirtualApp Java/AIDL source imported from asLody/VirtualApp
Pinned commit: $VA_COMMIT
Module: va-lib
Target: Android API 29+, compile SDK 35
Included: upstream Java, AIDL, resources, manifest
Not yet included: native libva++.so; no ARM64 native runtime is claimed.
Not yet validated: startup hooks, package installation, Activity/Service/Provider launch.
EOF

echo "VirtualApp Java/AIDL module staged at USBTool/va-lib"
