#!/usr/bin/env bash
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
APP_APK="$ROOT/USBTool/app/build/outputs/apk/debug/app-debug.apk"
FIXTURE_APK="$ROOT/USBTool/fixture/build/outputs/apk/debug/fixture-debug.apk"
AAPT="$ANDROID_HOME/build-tools/35.0.0/aapt"
REPORT="$ROOT/USBTool/BUILD_AUDIT_PHASE19.txt"
TREE="$ROOT/USBTool/build-manifest-phase19.xmltree.txt"

test -s "$APP_APK"
test -s "$FIXTURE_APK"
test -x "$AAPT"
command -v readelf >/dev/null

"$AAPT" dump badging "$APP_APK" > "$ROOT/USBTool/app-badging-phase19.txt"
"$AAPT" dump badging "$FIXTURE_APK" > "$ROOT/USBTool/fixture-badging-phase19.txt"
"$AAPT" dump xmltree "$APP_APK" AndroidManifest.xml > "$TREE"

python3 - "$APP_APK" "$FIXTURE_APK" "$ROOT/USBTool/app-badging-phase19.txt" "$ROOT/USBTool/fixture-badging-phase19.txt" "$TREE" "$REPORT" <<'PY'
import hashlib
import pathlib
import re
import subprocess
import sys
import zipfile

app, fixture, app_badging, fixture_badging, tree, report = map(pathlib.Path, sys.argv[1:])
app_bad = app_badging.read_text(errors="replace")
fixture_bad = fixture_badging.read_text(errors="replace")
manifest_tree = tree.read_text(errors="replace")

def require(condition, message):
    if not condition:
        raise SystemExit("PHASE19 AUDIT FAILED: " + message)

require("package: name='com.ssai.usbtool'" in app_bad, "app applicationId is not com.ssai.usbtool")
require("sdkVersion:'29'" in app_bad, "app minSdk is not Android 10 / API 29")
require("targetSdkVersion:'29'" in app_bad, "app targetSdk is not API 29")
require("package: name='com.ssai.usbtool.fixture'" in fixture_bad, "fixture package ID mismatch")

activity_slots = set(re.findall(r"com\\.lody\\.virtual\\.client\\.stub\\.StubActivity\\$C(\\d+)", manifest_tree))
provider_slots = set(re.findall(r"com\\.lody\\.virtual\\.client\\.stub\\.StubContentProvider\\$C(\\d+)", manifest_tree))
missing_activities = sorted(set(str(i) for i in range(50)) - activity_slots, key=int)
missing_providers = sorted(set(str(i) for i in range(50)) - provider_slots, key=int)
require(not missing_activities, "merged APK manifest is missing StubActivity slots: " + ",".join(missing_activities))
require(not missing_providers, "merged APK manifest is missing StubContentProvider slots: " + ",".join(missing_providers))
require("com.lody.virtual.server.BinderProvider" in manifest_tree, "BinderProvider missing from merged manifest")
for name in (
    "com.lody.virtual.client.stub.DaemonService",
    "com.lody.virtual.client.stub.StubPendingService",
    "com.lody.virtual.client.stub.StubJob",
    "com.lody.virtual.client.stub.StubPendingReceiver",
):
    require(name in manifest_tree, "required VirtualApp component missing: " + name)

authorities = []
for line in manifest_tree.splitlines():
    if "android:authorities" in line:
        match = re.search(r'="([^"]+)"', line)
        if match:
            authorities.extend(x.strip() for x in match.group(1).split(";") if x.strip())
duplicates = sorted({x for x in authorities if authorities.count(x) > 1})
require(not duplicates, "duplicate ContentProvider authorities: " + ", ".join(duplicates))

with zipfile.ZipFile(app) as z:
    names = z.namelist()
    native_libs = sorted(n for n in names if n.startswith("lib/") and n.endswith(".so"))
    dex_files = sorted(n for n in names if re.fullmatch(r"classes(?:[0-9]+)?\\.dex", pathlib.PurePosixPath(n).name))
    require(native_libs == ["lib/arm64-v8a/libva++.so"], "unexpected native ABI/library set: " + repr(native_libs))
    require(len(dex_files) >= 1, "no DEX bytecode found")
    so_bytes = z.read("lib/arm64-v8a/libva++.so")
    so_tmp = pathlib.Path("/tmp/usbtool-phase19-libva++.so")
    so_tmp.write_bytes(so_bytes)
    elf = subprocess.check_output(["readelf", "-h", str(so_tmp)], text=True)
    require("Class:                             ELF64" in elf, "libva++.so is not ELF64")
    require("Machine:                           AArch64" in elf, "libva++.so is not AArch64")
    app_sha = hashlib.sha256(app.read_bytes()).hexdigest()
    so_sha = hashlib.sha256(so_bytes).hexdigest()

with zipfile.ZipFile(fixture) as z:
    fixture_dex = [n for n in z.namelist() if n.endswith(".dex")]
    require(bool(fixture_dex), "fixture APK contains no DEX")

lines = [
    "USBTool Phase 19 - built APK / merged manifest audit",
    "Static build-artifact audit only; no device runtime or guest APK launch is claimed.",
    "",
    "Package: com.ssai.usbtool",
    "minSdk: 29 (Android 10)",
    "targetSdk: 29",
    "Fixture package: com.ssai.usbtool.fixture",
    f"VirtualApp StubActivity slots: {len(activity_slots)}/50",
    f"VirtualApp StubContentProvider slots: {len(provider_slots)}/50",
    "BinderProvider: present",
    "DaemonService / StubPendingService / StubJob: present",
    "StubPendingReceiver: present",
    f"Provider authorities: {len(authorities)} unique (no duplicates)",
    f"Native library: lib/arm64-v8a/libva++.so ({len(so_bytes)} bytes; ELF64 AArch64)",
    f"DEX files in host APK: {len(dex_files)}",
    f"App APK SHA-256: {app_sha}",
    f"libva++.so SHA-256: {so_sha}",
    "",
    "NOT VERIFIED by this audit:",
    "- VirtualCore.startup() or Android framework/system-service hooks",
    "- Actual Activity/Service/Receiver/Provider execution for an imported APK",
    "- Separate Android UID, permission isolation, or security sandbox",
    "- Android 10 physical-device lifecycle, linker namespace, and multi-process behavior",
]
report.write_text("\\n".join(lines) + "\\n")
print("\\n".join(lines))
PY
