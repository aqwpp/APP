#!/usr/bin/env bash
set -euo pipefail

TARGET="USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualCoreStartupProbe.java"
test -f "$TARGET"

cat > "$TARGET" <<'JAVA'
package com.ssai.usbtool.runtime.virtualapp;

import android.content.Context;
import android.os.Build;

import com.lody.virtual.client.core.VirtualCore;
import com.ssai.usbtool.USBToolApplication;

import java.io.File;

/**
 * On-device diagnostics for the experimental VirtualApp runtime.
 * A green startup result is not proof that arbitrary guest APKs can run.
 */
public final class VirtualCoreStartupProbe {
    private VirtualCoreStartupProbe() {}

    public static String run(Context context) {
        StringBuilder report = new StringBuilder();
        VirtualCore core = VirtualCore.get();
        report.append("USBTool VirtualApp 运行时诊断");
        report.append("\nAndroid API：").append(Build.VERSION.SDK_INT);
        report.append("\n设备 ABI：");
        if (Build.SUPPORTED_ABIS != null) {
            for (int i = 0; i < Build.SUPPORTED_ABIS.length; i++) {
                if (i > 0) report.append(", ");
                report.append(Build.SUPPORTED_ABIS[i]);
            }
        }
        File nativeLibrary = new File(context.getApplicationInfo().nativeLibraryDir, "libva++.so");
        report.append("\nNative 库文件：").append(nativeLibrary.exists() ? "存在" : "缺失");
        report.append("\nNative 路径：").append(nativeLibrary.getAbsolutePath());

        String applicationFailure = USBToolApplication.getStartupFailure();
        report.append("\nApplication 早期启动错误：")
                .append(applicationFailure == null ? "无记录" : applicationFailure);

        try {
            if (!core.isStartup()) {
                core.startup(context.getApplicationContext());
            }
            core.initialize(new VirtualCore.VirtualInitializer() {});
            core.waitForEngine();

            report.append("\nVirtualCore startup：")
                    .append(core.isStartup() ? "已完成" : "未完成");
            report.append("\n进程类型：")
                    .append(core.isMainProcess() ? "Main" :
                            core.isServerProcess() ? "Server" :
                            core.isVAppProcess() ? "Virtual client" : "Child");
            report.append("\nEngine 进程名：").append(core.getEngineProcessName());
            report.append("\nEngine server：")
                    .append(core.isEngineLaunched() ? "运行中" : "尚未检测到");
            report.append("\n虚拟安装包数量：")
                    .append(core.getInstalledApps(0).size());
            report.append("\n\n诊断结论：以上只检查初始化和引擎可见性；不代表 guest Activity 已显示。");
        } catch (Throwable error) {
            report.append("\nVirtualCore 初始化/服务检查失败：")
                    .append(error.getClass().getName())
                    .append("\n")
                    .append(String.valueOf(error.getMessage()));
            report.append("\n\n未确认 guest APK 可运行。请保存完整错误信息用于兼容性修复。");
        }
        return report.toString();
    }
}
JAVA

AUDIT="USBTool/BUILD_AUDIT_PHASE28.txt"
cat > "$AUDIT" <<'AUDIT'
USBTool Phase 28 - on-device runtime diagnostics
Package: com.ssai.usbtool
Target: Android 10 / API 29; arm64-v8a; no root

Added diagnostic output for:
- Device API level and supported ABIs.
- Packaged native library presence and resolved nativeLibraryDir path.
- USBToolApplication early startup failure.
- VirtualCore process type and startup state.
- VirtualApp engine process name and running-process visibility.
- Number of packages reported by VirtualCore.

Limitations:
- This is diagnostic instrumentation, not a successful device test.
- Engine process visibility does not prove Binder services are all healthy.
- Package count does not prove guest Activity execution.
- No separate Android UID, permission isolation, or security sandbox is claimed.
AUDIT

grep -q 'USBToolApplication.getStartupFailure' "$TARGET"
grep -q 'nativeLibraryDir' "$TARGET"
grep -q 'getInstalledApps(0)' "$TARGET"
grep -q 'BUILD_AUDIT_PHASE28' scripts/phase28-runtime-diagnostics.sh
echo "Phase 28 on-device runtime diagnostics source audit passed."
