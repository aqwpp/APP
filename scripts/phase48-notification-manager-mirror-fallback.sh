#!/usr/bin/env bash
set -euo pipefail
FILE="USBTool/va-lib/src/main/java/com/lody/virtual/client/hook/proxies/notification/NotificationManagerStub.java"
test -s "$FILE"
python3 - <<'PY'
from pathlib import Path
p = Path("USBTool/va-lib/src/main/java/com/lody/virtual/client/hook/proxies/notification/NotificationManagerStub.java")
s = p.read_text()
old = """        NotificationManager.sService.set(getInvocationStub().getProxyInterface());
        Toast.sService.set(getInvocationStub().getProxyInterface());"""
new = """        IInterface proxy = getInvocationStub().getProxyInterface();
        setStaticService(NotificationManager.TYPE, "sService", NotificationManager.sService, proxy);
        setStaticService(Toast.TYPE, "sService", Toast.sService, proxy);"""
if old in s:
    s = s.replace(old, new, 1)
elif "setStaticService(NotificationManager.TYPE" not in s:
    raise SystemExit("Phase 48 NotificationManagerStub.inject anchor missing")
marker = """    @Override
    public boolean isEnvBad() {"""
helper = """    // Some Android 10 vendor framework builds do not populate one or both
    // mirror RefStaticObject wrappers. Fall back to the actual framework field.
    // A missing Toast field must not prevent NotificationManager hook startup.
    private static void setStaticService(Class<?> frameworkClass, String fieldName,
            mirror.RefStaticObject<IInterface> mapped, IInterface service) {
        if (mapped != null) {
            try {
                mapped.set(service);
                return;
            } catch (Throwable ignored) {
                // Try direct framework reflection below.
            }
        }
        if (frameworkClass == null) {
            return;
        }
        try {
            java.lang.reflect.Field field = frameworkClass.getDeclaredField(fieldName);
            field.setAccessible(true);
            field.set(null, service);
        } catch (Throwable ignored) {
            // Vendor framework may have removed/renamed this cache field.
            // Keep VirtualCore alive; other notification entry points remain usable.
        }
    }

"""
if "private static void setStaticService(Class<?> frameworkClass" not in s:
    if marker not in s:
        raise SystemExit("Phase 48 helper insertion anchor missing")
    s = s.replace(marker, helper + marker, 1)
p.write_text(s)
assert "setStaticService(NotificationManager.TYPE" in s
assert "setStaticService(Toast.TYPE" in s
assert "NotificationManager.sService.set(getInvocationStub()" not in s
assert "Toast.sService.set(getInvocationStub()" not in s
print("Phase 48: notification and toast static service mirror fallback applied")
PY
cat > USBTool/BUILD_AUDIT_PHASE48.txt <<'AUDIT'
USBTool Phase 48 - Android 10 vendor NotificationManager mirror fallback
- Device root cause: NotificationManagerStub.inject() dereferenced a null RefStaticObject wrapper while replacing static notification service references.
- Preserve mirror RefStaticObject.set() when the wrapper is available.
- If the mirror wrapper is absent or throws, reflect the actual framework class static sService field.
- Treat a missing/renamed vendor Toast cache field as non-fatal so notification hook setup does not abort all VirtualCore startup.
- This compatibility patch addresses the observed startup crash; guest notification behavior still requires device validation.
AUDIT
