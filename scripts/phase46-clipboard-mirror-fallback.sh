#!/usr/bin/env bash
set -euo pipefail
FILE="USBTool/va-lib/src/main/java/com/lody/virtual/client/hook/proxies/clipboard/ClipBoardStub.java"
test -s "$FILE"
python3 - <<'PY'
from pathlib import Path
p = Path("USBTool/va-lib/src/main/java/com/lody/virtual/client/hook/proxies/clipboard/ClipBoardStub.java")
s = p.read_text()
old = """            return ClipboardManagerOreo.mService.get(cm);
"""
new = """            return getOreoClipboardService(cm);
"""
if old in s:
    s = s.replace(old, new, 1)
elif "return getOreoClipboardService(cm);" not in s:
    raise SystemExit("Phase 46 clipboard get anchor not found")
old_set = """            ClipboardManagerOreo.mService.set(cm, getInvocationStub().getProxyInterface());
"""
new_set = """            setOreoClipboardService(cm, getInvocationStub().getProxyInterface());
"""
if old_set in s:
    s = s.replace(old_set, new_set, 1)
elif "setOreoClipboardService(cm, getInvocationStub().getProxyInterface());" not in s:
    raise SystemExit("Phase 46 clipboard set anchor not found")
marker = """    @Override
    protected void onBindMethods() {
"""
helpers = """    // API 26+ stores IClipboard in ClipboardManager.mService. Some mirror
    // initializers leave ClipboardManagerOreo.mService unset on vendor ROMs.
    // Keep the mirror path when available, then resolve the exact API field directly.
    private static IInterface getOreoClipboardService(android.content.ClipboardManager cm) {
        if (ClipboardManagerOreo.mService != null) {
            IInterface service = ClipboardManagerOreo.mService.get(cm);
            if (service != null) {
                return service;
            }
        }
        try {
            java.lang.reflect.Field field =
                    android.content.ClipboardManager.class.getDeclaredField("mService");
            field.setAccessible(true);
            return (IInterface) field.get(cm);
        } catch (Throwable error) {
            throw new IllegalStateException(
                    "Unable to read ClipboardManager.mService on API "
                            + Build.VERSION.SDK_INT, error);
        }
    }

    private static void setOreoClipboardService(
            android.content.ClipboardManager cm, IInterface service) {
        if (ClipboardManagerOreo.mService != null) {
            try {
                ClipboardManagerOreo.mService.set(cm, service);
                return;
            } catch (Throwable ignored) {
                // Try the direct framework field below.
            }
        }
        try {
            java.lang.reflect.Field field =
                    android.content.ClipboardManager.class.getDeclaredField("mService");
            field.setAccessible(true);
            field.set(cm, service);
        } catch (Throwable error) {
            throw new IllegalStateException(
                    "Unable to replace ClipboardManager.mService on API "
                            + Build.VERSION.SDK_INT, error);
        }
    }

"""
if "private static IInterface getOreoClipboardService(" not in s:
    if marker not in s:
        raise SystemExit("Phase 46 clipboard helper insertion anchor not found")
    s = s.replace(marker, helpers + marker, 1)
p.write_text(s)
assert "return getOreoClipboardService(cm);" in s
assert "setOreoClipboardService(cm, getInvocationStub().getProxyInterface());" in s
assert 'getDeclaredField("mService")' in s
print("Phase 46 Android 10 ClipboardManager.mService reflection fallback applied")
PY
cat > USBTool/BUILD_AUDIT_PHASE46.txt <<'AUDIT'
USBTool Phase 46 - Android 10 ClipboardManager mirror fallback
- Device root cause: ClipBoardStub dereferenced a null ClipboardManagerOreo.mService RefObject during VirtualCore hook injection.
- Retain the mapped RefObject path when populated.
- If the mirror wrapper is absent or returns null, read ClipboardManager.mService directly via reflection.
- Use the same guarded fallback for proxy injection, so startup and service replacement use the same field resolution.
- Fail with an explicit API-level diagnostic if the framework field cannot be accessed; do not silently skip clipboard hook initialization.
- AOSP Android 10 source confirms ClipboardManager contains private final IClipboard mService.
AUDIT
