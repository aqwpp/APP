#!/usr/bin/env bash
set -euo pipefail
ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
APP="$ROOT/USBTool/app/src/main/java/com/ssai/usbtool"
mkdir -p "$APP/runtime/diagnostics"
cat > "$APP/runtime/diagnostics/VirtualAppReadinessReport.java" <<'JAVA'
package com.ssai.usbtool.runtime.diagnostics;

import android.content.Context;
import android.os.Build;
import java.io.File;

public final class VirtualAppReadinessReport {
    private VirtualAppReadinessReport() {}

    public static String create(Context context) {
        StringBuilder out = new StringBuilder();
        out.append("USBTool / VirtualApp 依赖诊断\n\n");
        out.append("Android API：").append(Build.VERSION.SDK_INT).append("\n");
        out.append("设备 ABI：");
        for (String abi : Build.SUPPORTED_ABIS) out.append(abi).append(" ");
        out.append("\n");

        boolean corePresent = classExists("com.lody.virtual.client.core.VirtualCore");
        boolean clientPresent = classExists("com.lody.virtual.client.VClientImpl");
        out.append("VirtualCore Java 类：").append(corePresent ? "已包含" : "缺失").append("\n");
        out.append("VClientImpl Java 类：").append(clientPresent ? "已包含" : "缺失").append("\n");

        String nativeDir = context.getApplicationInfo().nativeLibraryDir;
        File nativeLib = new File(nativeDir, "libva++.so");
        out.append("Native 库目录：").append(nativeDir).append("\n");
        out.append("libva++.so：").append(nativeLib.isFile() ? "已找到" : "未包含").append("\n\n");

        boolean ready = corePresent && clientPresent && nativeLib.isFile()
                && Build.VERSION.SDK_INT >= 29;
        out.append("引擎状态：").append(ready ? "依赖初步齐备，仍需设备 Hook 验证" : "尚未具备安全启动条件");
        if (!nativeLib.isFile()) {
            out.append("\n\n阻断项：缺少 ARM64 原生 Hook / IO 重定向库 libva++.so。");
        }
        out.append("\n\n安全说明：此诊断不会调用 VirtualCore.startup()，不会注入系统服务，也不会执行第三方 APK。");
        out.append("\nJava/AIDL 编译成功不等于 Activity、Service、Provider 已可虚拟启动。");
        return out.toString();
    }

    private static boolean classExists(String name) {
        try {
            Class.forName(name, false, VirtualAppReadinessReport.class.getClassLoader());
            return true;
        } catch (Throwable ignored) {
            return false;
        }
    }
}
JAVA

python3 - "$APP/MainActivity.java" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
imp = "import com.ssai.usbtool.runtime.diagnostics.VirtualAppReadinessReport;\n"
if imp not in s:
    anchor = "import com.ssai.usbtool.runtime.bootstrap.ApplicationBootstrapPlanner;\n"
    if anchor not in s:
        raise SystemExit("MainActivity import anchor missing")
    s = s.replace(anchor, anchor + imp)
button = '''        Button readiness = new Button(this);
        readiness.setText("检查 VirtualApp 引擎依赖");
        readiness.setOnClickListener(v -> new AlertDialog.Builder(this)
                .setTitle("VirtualApp 运行依赖诊断")
                .setMessage(VirtualAppReadinessReport.create(this))
                .setPositiveButton("关闭", null).show());
        page.addView(readiness);

'''
anchor = '        TextView note = new TextView(this);\n'
if '检查 VirtualApp 引擎依赖' not in s:
    if anchor not in s:
        raise SystemExit("MainActivity UI anchor missing")
    s = s.replace(anchor, button + anchor)
p.write_text(s)
PY

cat > "$ROOT/USBTool/VA_INTEGRATION_PHASE15.txt" <<'EOF'
Phase 15: safe VirtualApp dependency diagnostics.
Adds an in-app diagnostic for Java core classes, supported ABI, Android API level,
and libva++.so presence. Does not call VirtualCore.startup() or install hooks.
Native ARM64 build, device-level framework hooks, and guest component launch remain
unimplemented and unverified.
EOF
echo "Phase 15 safe VirtualApp readiness diagnostics staged."
