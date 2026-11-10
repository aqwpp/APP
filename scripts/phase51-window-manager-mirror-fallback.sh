#!/usr/bin/env bash
set -euo pipefail
FILE="USBTool/va-lib/src/main/java/com/lody/virtual/client/hook/proxies/window/WindowManagerStub.java"
test -s "$FILE"
python3 - <<'PY'
from pathlib import Path
p = Path("USBTool/va-lib/src/main/java/com/lody/virtual/client/hook/proxies/window/WindowManagerStub.java")
s = p.read_text()
old = '''        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
            if (WindowManagerGlobal.sWindowManagerService != null) {
                WindowManagerGlobal.sWindowManagerService.set(getInvocationStub().getProxyInterface());
            }
        } else {
            if (Display.sWindowManager != null) {
                Display.sWindowManager.set(getInvocationStub().getProxyInterface());
            }
        }
        if (PhoneWindow.TYPE != null) {
            PhoneWindow.sWindowManager.set(getInvocationStub().getProxyInterface());
        }'''
new = '''        android.os.IInterface proxy = getInvocationStub().getProxyInterface();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
            setStaticService(WindowManagerGlobal.TYPE, "sWindowManagerService",
                    WindowManagerGlobal.sWindowManagerService, proxy);
        } else {
            setStaticService(Display.TYPE, "sWindowManager", Display.sWindowManager, proxy);
        }
        if (PhoneWindow.TYPE != null) {
            setStaticService(PhoneWindow.TYPE, "sWindowManager", PhoneWindow.sWindowManager, proxy);
        }'''
if old in s:
    s = s.replace(old, new, 1)
elif "setStaticService(WindowManagerGlobal.TYPE" not in s:
    raise SystemExit("Phase 51 WindowManagerStub.inject anchor missing")
marker = '''    @Override
    protected void onBindMethods() {'''
helper = '''    // Android 10 vendor frameworks can omit mirror mappings even when the
    // underlying framework static cache field exists. Never dereference a null
    // RefStaticObject; try the mapped field first, then reflect the real field.
    private static void setStaticService(Class<?> frameworkClass, String fieldName,
            mirror.RefStaticObject<android.os.IInterface> mapped,
            android.os.IInterface service) {
        if (mapped != null) {
            try {
                mapped.set(service);
                return;
            } catch (Throwable ignored) {
                // Fall through to framework reflection.
            }
        }
        if (frameworkClass == null) return;
        try {
            java.lang.reflect.Field field = frameworkClass.getDeclaredField(fieldName);
            field.setAccessible(true);
            field.set(null, service);
        } catch (Throwable ignored) {
            // A missing vendor cache field must not abort VirtualCore startup.
        }
    }

'''
if "private static void setStaticService(Class<?> frameworkClass" not in s:
    if marker not in s:
        raise SystemExit("Phase 51 helper insertion anchor missing")
    s = s.replace(marker, helper + marker, 1)
p.write_text(s)
assert "setStaticService(WindowManagerGlobal.TYPE" in s
assert "WindowManagerGlobal.sWindowManagerService.set(" not in s
assert "PhoneWindow.sWindowManager.set(" not in s
print("Phase 51: WindowManager static service mirror fallback applied")
PY
cat > USBTool/BUILD_AUDIT_PHASE51.txt <<'AUDIT'
USBTool Phase 51 - Android 10 vendor WindowManager mirror fallback
- Device log identified a null mirror.RefStaticObject in WindowManagerStub.inject() during InvocationStubManager.injectAll().
- Preserve mirror-based static service injection when the mapping exists.
- Fall back to reflection on WindowManagerGlobal.sWindowManagerService, legacy Display.sWindowManager, and PhoneWindow.sWindowManager.
- A missing or inaccessible vendor cache field is non-fatal and must not abort VirtualCore startup.
- This patch addresses the observed startup exception only; successful WindowManager interception and guest APK launch require on-device validation.
AUDIT
grep -q 'setStaticService(WindowManagerGlobal.TYPE' "$FILE"
echo 'Phase 51 patch applied.'
