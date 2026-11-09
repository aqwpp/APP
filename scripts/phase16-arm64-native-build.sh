#!/usr/bin/env bash
set -euo pipefail
ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
MOD="$ROOT/USBTool/va-lib"
GRADLE="$MOD/build.gradle"
APP_MK="$MOD/src/main/jni/Application.mk"
TMP="$ROOT/.virtualapp-arm64-source"

test -f "$GRADLE"
test -f "$MOD/src/main/jni/Android.mk"
test -f "$APP_MK"

# Replace the legacy 32-bit-only native layer with an Apache-2.0 VirtualApp
# revision that contains ARM64 inline hooks and 64-bit syscall handling.
rm -rf "$TMP"
git clone --quiet https://github.com/ISEKHON/VirtualApp.git "$TMP"
git -C "$TMP" checkout --quiet b3c634ad7941765df3da84a207aca94b7861afae
test -f "$TMP/lib/src/main/jni/A64Inlinehook/And64InlineHook.cpp"
test -f "$TMP/lib/src/main/jni/Foundation/IOUniformer.cpp"
grep -q '__NR_newfstatat' "$TMP/lib/src/main/jni/Foundation/IOUniformer.cpp"
rm -rf "$MOD/src/main/jni"
mkdir -p "$MOD/src/main"
cp -a "$TMP/lib/src/main/jni" "$MOD/src/main/jni"
cp "$TMP/LICENSE" "$MOD/UPSTREAM_VIRTUALAPP_LICENSE_APACHE_2.0.txt"

# Keep the target constrained to the user's Android 10 ARM64 device.
cat > "$APP_MK" <<'EOF'
APP_ABI := arm64-v8a
APP_PLATFORM := android-29
APP_STL := c++_static
APP_OPTIM := release
VA_ROOT := $(call my-dir)
NDK_MODULE_PATH := $(NDK_MODULE_PATH):$(VA_ROOT)
EOF

python3 - "$GRADLE" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
if 'externalNativeBuild {' not in s:
    s = s.replace('''    defaultConfig {
        minSdk 29
        targetSdk 29
    }
''', '''    defaultConfig {
        minSdk 29
        targetSdk 29
        ndk {
            abiFilters 'arm64-v8a'
        }
        externalNativeBuild {
            ndkBuild {
                arguments 'NDK_APPLICATION_MK:=src/main/jni/Application.mk'
            }
        }
    }

    ndkVersion '27.2.12479018'

    externalNativeBuild {
        ndkBuild {
            path file('src/main/jni/Android.mk')
        }
    }
''')
p.write_text(s)
required = ["abiFilters 'arm64-v8a'", "ndkVersion '27.2.12479018'", "path file('src/main/jni/Android.mk')"]
for item in required:
    if item not in s:
        raise SystemExit("Native build config missing: " + item)
PY

cat > "$MOD/NATIVE_ARM64_PHASE16.txt" <<'EOF'
Phase 16: use a pinned Apache-2.0 VirtualApp native revision with ARM64 inline hooks
and 64-bit syscall handling. Target: arm64-v8a, Android API 29, NDK 27.2.12479018.
This phase compiles and packages the native layer; it does not prove framework hooks,
guest Activity/Service/Provider launch, data isolation, or full Android 10 compatibility.
Those remain separate runtime and physical-device acceptance gates.
EOF
echo "Phase 16: pinned ARM64-capable VirtualApp native sources installed."
