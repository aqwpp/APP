#!/usr/bin/env bash
set -euo pipefail
ROOT="USBTool/app/src/main/java/com/ssai/usbtool"
APP_MANIFEST="USBTool/app/src/main/AndroidManifest.xml"
mkdir -p "$ROOT"
cat > "$ROOT/USBToolApplication.java" <<'JAVA'
package com.ssai.usbtool;

import android.app.Application;
import android.content.Context;
import android.util.Log;

import com.lody.virtual.client.core.VirtualCore;

/**
 * VirtualApp requires startup in every host-package process before ContentProviders
 * are created. BinderProvider lives in the engine process, so starting only from
 * MainActivity is too late and leaves the server Binder registry empty.
 */
public final class USBToolApplication extends Application {
    private static final String TAG = "USBToolApplication";
    private static volatile String startupFailure;

    @Override
    protected void attachBaseContext(Context base) {
        super.attachBaseContext(base);
        try {
            VirtualCore core = VirtualCore.get();
            if (!core.isStartup()) {
                // attachBaseContext runs on the process main thread and before providers.
                core.startup(base);
            }
        } catch (Throwable error) {
            startupFailure = error.getClass().getName() + ": " + String.valueOf(error.getMessage());
            Log.e(TAG, "VirtualCore startup failed before provider initialization", error);
        }
    }

    @Override
    public void onCreate() {
        super.onCreate();
        if (VirtualCore.get().isStartup()) {
            try {
                VirtualCore.get().initialize(new VirtualCore.VirtualInitializer() {});
            } catch (Throwable error) {
                startupFailure = error.getClass().getName() + ": " + String.valueOf(error.getMessage());
                Log.e(TAG, "VirtualCore process initialization failed", error);
            }
        }
    }

    public static String getStartupFailure() {
        return startupFailure;
    }
}
JAVA

python3 - <<'PY'
from pathlib import Path
import xml.etree.ElementTree as ET
p=Path("USBTool/app/src/main/AndroidManifest.xml")
s=p.read_text()
if 'android:name=".USBToolApplication"' not in s:
    marker='<application'
    if marker not in s: raise SystemExit("application manifest element missing")
    s=s.replace(marker, marker+'\n        android:name=".USBToolApplication"', 1)
p.write_text(s)
root=ET.parse(p).getroot()
app=root.find('application')
name=app.get('{http://schemas.android.com/apk/res/android}name')
if name != '.USBToolApplication':
    raise SystemExit("Application class was not registered in host manifest")
PY

RUNNER="USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java"
grep -q 'core.startup(base)' "$ROOT/USBToolApplication.java"
grep -q 'protected void attachBaseContext(Context base)' "$ROOT/USBToolApplication.java"
grep -q 'com.lody.virtual.server.BinderProvider' "USBTool/va-lib/src/main/AndroidManifest.xml"
grep -q 'android:process="@string/engine_process_name"' "USBTool/va-lib/src/main/AndroidManifest.xml"
grep -q 'android:name=".USBToolApplication"' "$APP_MANIFEST"
grep -q 'prepareOnMain(this)' "USBTool/app/src/main/java/com/ssai/usbtool/MainActivity.java"

cat > USBTool/BUILD_AUDIT_PHASE27.txt <<'AUDIT'
USBTool Phase 27 - per-process VirtualCore startup ordering source audit
Package: com.ssai.usbtool
Target: Android 10 / API 29; arm64-v8a; no root

Changes:
- Added USBToolApplication and registered it in the host manifest.
- Calls VirtualCore.startup(base) from attachBaseContext in each host-package process.
- This occurs before ContentProvider creation, including BinderProvider in the engine process.
- Calls VirtualCore.initialize() from Application.onCreate after providers have been created.
- Captures startup failures in logcat and exposes a getter for diagnostics.

Reason:
- Starting VirtualCore only from MainActivity initializes only the UI process.
- BinderProvider runs in a separate engine process and checks VirtualCore.isStartup().
- Without per-process startup before provider creation, BinderProvider can return without
  registering the VirtualApp server Binder services.

Not verified:
- Physical-device startup success, Android framework hook compatibility, Binder service readiness.
- Actual guest Activity/Service/Receiver/Provider execution or arbitrary APK compatibility.
- Separate Android UID, permission isolation, or a security sandbox.
AUDIT
echo "Phase 27 per-process VirtualCore startup ordering source audit passed."
