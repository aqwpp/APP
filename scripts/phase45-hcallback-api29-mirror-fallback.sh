#!/usr/bin/env bash
set -euo pipefail
FILE="USBTool/va-lib/src/main/java/com/lody/virtual/client/hook/proxies/am/HCallbackStub.java"
test -s "$FILE"
python3 - <<'PY'
from pathlib import Path
p = Path("USBTool/va-lib/src/main/java/com/lody/virtual/client/hook/proxies/am/HCallbackStub.java")
s = p.read_text()
old = """        private static final int LAUNCH_ACTIVITY = ActivityThread.H.LAUNCH_ACTIVITY.get();
        private static final int CREATE_SERVICE = ActivityThread.H.CREATE_SERVICE.get();
        private static final int SCHEDULE_CRASH =
                ActivityThread.H.SCHEDULE_CRASH != null ? ActivityThread.H.SCHEDULE_CRASH.get() : -1;
"""
new = """        // Android 10 compatibility: some mirror builds fail to populate RefStaticInt
        // for ActivityThread.H fields. Resolve the real framework field directly first,
        // then use the documented API-29 message constants as a narrowly scoped fallback.
        private static int resolveMessageCode(mirror.RefStaticInt mapped, String name, int api29Fallback) {
            if (mapped != null) {
                return mapped.get();
            }
            try {
                Class<?> type = ActivityThread.H.TYPE;
                if (type != null) {
                    java.lang.reflect.Field field = type.getDeclaredField(name);
                    field.setAccessible(true);
                    return field.getInt(null);
                }
            } catch (Throwable ignored) {
                // Fall through to the Android 10 constants below.
            }
            if (android.os.Build.VERSION.SDK_INT == 29) {
                return api29Fallback;
            }
            throw new IllegalStateException("Unable to resolve ActivityThread.H." + name
                    + " on Android API " + android.os.Build.VERSION.SDK_INT);
        }

        private static final int LAUNCH_ACTIVITY =
                resolveMessageCode(ActivityThread.H.LAUNCH_ACTIVITY, "LAUNCH_ACTIVITY", 100);
        private static final int CREATE_SERVICE =
                resolveMessageCode(ActivityThread.H.CREATE_SERVICE, "CREATE_SERVICE", 114);
        private static final int SCHEDULE_CRASH =
                resolveMessageCode(ActivityThread.H.SCHEDULE_CRASH, "SCHEDULE_CRASH", 134);
"""
if "private static int resolveMessageCode(mirror.RefStaticInt mapped" not in s:
    if old not in s:
        raise SystemExit("Phase 45 HCallbackStub static field anchor not found")
    s = s.replace(old, new, 1)
p.write_text(s)
assert "resolveMessageCode(ActivityThread.H.LAUNCH_ACTIVITY" in s
assert "resolveMessageCode(ActivityThread.H.CREATE_SERVICE" in s
assert "resolveMessageCode(ActivityThread.H.SCHEDULE_CRASH" in s
print("Phase 45 HCallbackStub Android 10 message-code fallback applied")
PY
cat > USBTool/BUILD_AUDIT_PHASE45.txt <<'AUDIT'
USBTool Phase 45 - Android 10 ActivityThread.H message-code mirror fallback
- Root cause observed on device: HCallbackStub static initializer dereferenced null ActivityThread.H.LAUNCH_ACTIVITY RefStaticInt.
- Resolve each message code from the mapped RefStaticInt when available.
- If the mirror wrapper is null, reflect the corresponding field from ActivityThread.H.TYPE.
- On API 29 only, use AOSP ActivityThread.H message constants as a last-resort fallback: LAUNCH_ACTIVITY=100, CREATE_SERVICE=114, SCHEDULE_CRASH=134.
- Other Android API levels fail with a descriptive exception rather than silently using API-29 constants.
AUDIT
