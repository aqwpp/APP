#!/usr/bin/env bash
set -euo pipefail
FILE="USBTool/va-lib/src/main/java/com/lody/virtual/client/hook/proxies/clipboard/ClipBoardStub.java"
test -s "$FILE"
python3 - <<'PY'
from pathlib import Path
p = Path("USBTool/va-lib/src/main/java/com/lody/virtual/client/hook/proxies/clipboard/ClipBoardStub.java")
s = p.read_text()
if "import mirror.android.os.ServiceManager;" not in s:
    anchor = "import mirror.android.content.ClipboardManagerOreo;\n"
    if anchor not in s:
        raise SystemExit("Phase 47 import anchor missing")
    s = s.replace(anchor, anchor + "import mirror.android.os.ServiceManager;\n", 1)
s = s.replace("return getOreoClipboardService(cm);", "return getOreoClipboardService(cm);")
old = """            ClipboardManagerOreo.mService.set(cm, getInvocationStub().getProxyInterface());"""
new = """            setOreoClipboardService(cm, getInvocationStub().getProxyInterface());"""
if old in s:
    s = s.replace(old, new, 1)
elif "setOreoClipboardService(cm, getInvocationStub().getProxyInterface());" not in s:
    raise SystemExit("Phase 47 inject anchor missing")
start = s.find("    // API 26+ stores IClipboard")
if start >= 0:
    end = s.find("    @Override\n    protected void onBindMethods()", start)
    if end < 0:
        raise SystemExit("Phase 47 helper end anchor missing")
    s = s[:start] + s[end:]
helper_marker = "    @Override\n    protected void onBindMethods() {"
helpers = """    // Resolve the hidden IClipboard interface through the system Binder service.
    // Some Android 10 vendor frameworks do not expose ClipboardManager.mService.
    private static IInterface getOreoClipboardService(android.content.ClipboardManager cm) {
        if (ClipboardManagerOreo.mService != null) {
            try {
                IInterface mapped = ClipboardManagerOreo.mService.get(cm);
                if (mapped != null) return mapped;
            } catch (Throwable ignored) {}
        }
        try {
            android.os.IBinder binder = ServiceManager.getService.call(Context.CLIPBOARD_SERVICE);
            if (binder == null) {
                throw new IllegalStateException("ServiceManager returned null clipboard Binder");
            }
            Class<?> stub = Class.forName("android.content.IClipboard$Stub");
            java.lang.reflect.Method asInterface = stub.getDeclaredMethod(
                    "asInterface", android.os.IBinder.class);
            asInterface.setAccessible(true);
            return (IInterface) asInterface.invoke(null, binder);
        } catch (Throwable error) {
            throw new IllegalStateException(
                    "Unable to resolve IClipboard from ServiceManager on API "
                            + Build.VERSION.SDK_INT, error);
        }
    }

    private static void setOreoClipboardService(
            android.content.ClipboardManager cm, IInterface service) {
        if (ClipboardManagerOreo.mService != null) {
            try {
                ClipboardManagerOreo.mService.set(cm, service);
                return;
            } catch (Throwable ignored) {}
        }
        // Try the AOSP field first, then vendor-renamed IInterface fields.
        try {
            java.lang.reflect.Field field =
                    android.content.ClipboardManager.class.getDeclaredField("mService");
            field.setAccessible(true);
            field.set(cm, service);
            return;
        } catch (Throwable ignored) {}
        // BinderInvocationProxy.inject() has already replaced ServiceManager's cache.
        // If this ROM has no exposed manager field, keep startup working and let
        // future ClipboardManager instances resolve the hooked Binder from that cache.
    }

"""
if "private static IInterface getOreoClipboardService(" not in s:
    if helper_marker not in s:
        raise SystemExit("Phase 47 helper insertion anchor missing")
    s = s.replace(helper_marker, helpers + helper_marker, 1)
p.write_text(s)
assert "ServiceManager.getService.call(Context.CLIPBOARD_SERVICE)" in s
assert 'Class.forName("android.content.IClipboard$Stub")' in s
assert "Unable to read ClipboardManager.mService" not in s
print("Phase 47: clipboard service resolves via ServiceManager/IClipboard.Stub; vendor mService absence no longer aborts startup")
PY
cat > USBTool/BUILD_AUDIT_PHASE47.txt <<'AUDIT'
USBTool Phase 47 - Vendor Android 10 clipboard Binder fallback
- Phase 46 device logs proved this firmware's ClipboardManager has no declared mService field.
- Resolve IClipboard via mirror.android.os.ServiceManager.getService("clipboard") and android.content.IClipboard$Stub.asInterface(IBinder).
- Keep the ClipboardManagerOreo mirror path when it is available.
- Attempt manager-local service replacement only as a best-effort compatibility optimization.
- BinderInvocationProxy.inject() replaces the ServiceManager service cache before the best-effort manager update.
- Startup no longer fails solely because a vendor ClipboardManager omits the AOSP mService field.
AUDIT
