#!/usr/bin/env bash
set -euo pipefail
ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
MOD="$ROOT/USBTool/va-lib"
GRADLE="$MOD/build.gradle"
APP_MK="$MOD/src/main/jni/Application.mk"
IO_CPP="$MOD/src/main/jni/Foundation/IOUniformer.cpp"

test -f "$GRADLE"
test -f "$MOD/src/main/jni/Android.mk"
test -f "$APP_MK"
test -f "$IO_CPP"

# The legacy source uses syscall numbers but omitted the NDK syscall header.
python3 - "$IO_CPP" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
inc = '#include <sys/syscall.h>'
if inc not in s:
    p.write_text(inc + '\n' + s)
PY

# Re-enable the upstream NDK build for a modern ARM64 toolchain.
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
Phase 16: enable compilation of the pinned VirtualApp native source for arm64-v8a.
Toolchain: Android NDK 27.2.12479018, Android API 29, libc++_static.
The legacy IOUniformer source is explicitly given the NDK syscall declarations header.
This phase only attempts to compile and package the upstream native library.
A successful .so build is not proof that VirtualCore hooks or guest components work.
Runtime initialization and Android 10 device tests remain separate acceptance gates.
EOF
echo "Phase 16: ARM64 NDK build enabled; syscall header compatibility patch applied."
