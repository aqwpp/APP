#!/usr/bin/env bash
set -euo pipefail
ROOT="USBTool/app/src/main/java/com/ssai/usbtool"
mkdir -p "$ROOT/runtime/virtualapp"
cat > "$ROOT/runtime/virtualapp/VirtualCoreStartupProbe.java" <<'JAVA'
package com.ssai.usbtool.runtime.virtualapp;

import android.content.Context;
import com.lody.virtual.client.core.VirtualCore;

/**
 * Explicit, opt-in VirtualCore startup probe. Startup mutates framework hooks;
 * it is deliberately not run automatically during USBTool launch.
 */
public final class VirtualCoreStartupProbe {
    private VirtualCoreStartupProbe() {}

    public static String run(Context context) {
        StringBuilder report = new StringBuilder();
        VirtualCore core = VirtualCore.get();
        try {
            if (!core.isStartup()) {
                core.startup(context.getApplicationContext());
            }
            core.initialize(new VirtualCore.VirtualInitializer() {});
            core.waitForEngine();
            report.append("VirtualCore startup：")
                    .append(core.isStartup() ? "已完成" : "未完成");
            report.append("\n进程类型：")
                    .append(core.isMainProcess() ? "Main" :
                            core.isServerProcess() ? "Server" :
                            core.isVAppProcess() ? "Virtual client" : "Child");
            report.append("\nEngine server：")
                    .append(core.isEngineLaunched() ? "运行中" : "尚未检测到");
            report.append("\n\n注意：这只验证引擎初始化探测，不代表第三方 APK 已成功安装或启动。");
        } catch (Throwable error) {
            report.append("VirtualCore 初始化失败：")
                    .append(error.getClass().getName())
                    .append("\n")
                    .append(String.valueOf(error.getMessage()));
            report.append("\n\n未启动 guest APK；请保留此错误用于修复。");
        }
        return report.toString();
    }
}
JAVA
python3 - <<'PY'
from pathlib import Path
p=Path("USBTool/app/src/main/java/com/ssai/usbtool/MainActivity.java")
s=p.read_text()
imp="import com.ssai.usbtool.runtime.diagnostics.VirtualAppReadinessReport;\n"
if "VirtualCoreStartupProbe" not in s:
    s=s.replace(imp, imp+"import com.ssai.usbtool.runtime.virtualapp.VirtualCoreStartupProbe;\n")
marker='        Button readiness = new Button(this);\n'
if "启动 VirtualApp 引擎（实验）" not in s:
    button='''        Button startEngine = new Button(this);
        startEngine.setText("启动 VirtualApp 引擎（实验）");
        startEngine.setOnClickListener(v -> new AlertDialog.Builder(this)
                .setTitle("启动 VirtualApp 引擎")
                .setMessage("此操作会在 USBTool 主进程注入系统服务 Hook，并尝试启动 VirtualApp 服务进程。旧版 Hook 可能与部分 Android 10 ROM 不兼容；如果失败，请记录错误。当前不会自动启动任何导入 APK。")
                .setNegativeButton("取消", null)
                .setPositiveButton("启动", (dialog, which) -> {
                    String result = VirtualCoreStartupProbe.run(this);
                    new AlertDialog.Builder(this)
                            .setTitle("VirtualApp 初始化结果")
                            .setMessage(result)
                            .setPositiveButton("关闭", null)
                            .show();
                }).show());
        page.addView(startEngine);

'''
    if marker not in s: raise SystemExit("MainActivity insertion marker missing")
    s=s.replace(marker,button+marker)
p.write_text(s)
PY
echo "Phase 21: added explicit opt-in VirtualCore startup probe; no guest APK launch claim."
