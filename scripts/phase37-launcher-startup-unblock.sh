#!/usr/bin/env bash
set -euo pipefail
TARGET="USBTool/app/src/main/java/com/ssai/usbtool/USBToolApplication.java"
test -s "$TARGET"
cat > "$TARGET" <<'JAVA'
package com.ssai.usbtool;

import android.app.Application;
import android.content.Context;
import android.util.Log;

import com.lody.virtual.client.core.VirtualCore;

/**
 * Do not initialize VirtualApp in the launcher process during Application startup.
 * Its framework-hook startup is synchronous and can stall the Android main thread
 * before the first Activity is drawn. Engine and stub processes still initialize
 * before their ContentProviders, as required by VirtualApp.
 */
public final class USBToolApplication extends Application {
    private static final String TAG = "USBToolApplication";
    private static volatile String startupFailure;

    private static boolean isLauncherProcess(Context context) {
        String processName = Application.getProcessName();
        return context.getPackageName().equals(processName);
    }

    @Override
    protected void attachBaseContext(Context base) {
        super.attachBaseContext(base);
        if (isLauncherProcess(base)) {
            Log.i(TAG, "Skipping synchronous VirtualCore startup in launcher process");
            return;
        }
        try {
            VirtualCore core = VirtualCore.get();
            if (!core.isStartup()) {
                // Engine and VirtualApp stub processes must initialize before providers.
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
        if (isLauncherProcess(this)) return;
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
cat > USBTool/BUILD_AUDIT_PHASE37.txt <<'AUDIT'
USBTool Phase 37 - prevent launcher splash hang
- Root cause candidate confirmed in source: USBToolApplication.attachBaseContext synchronously called VirtualCore.startup() in the launcher process before MainActivity could be drawn.
- Launcher process now skips automatic VirtualCore startup and initialization.
- VirtualApp engine and stub processes continue initializing before their ContentProviders.
- Explicit VirtualCore diagnostics / guest launch path may still initialize the runtime when requested.
- This is a targeted startup responsiveness fix; physical-device success still requires testing.
AUDIT
grep -q 'Skipping synchronous VirtualCore startup in launcher process' "$TARGET"
grep -q 'Engine and VirtualApp stub processes must initialize before providers' "$TARGET"
grep -q 'isLauncherProcess(this)' "$TARGET"
echo "Phase 37 launcher startup responsiveness audit passed."
