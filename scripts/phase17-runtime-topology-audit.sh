#!/usr/bin/env bash
set -euo pipefail
ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
JAVA="$ROOT/USBTool/app/src/main/java/com/ssai/usbtool/runtime/diagnostics/VirtualAppReadinessReport.java"
test -f "$JAVA"

cat > "$JAVA" <<'JAVA'
package com.ssai.usbtool.runtime.diagnostics;

import android.content.Context;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.os.Build;
import java.io.File;
import java.lang.reflect.Method;

/**
 * Static readiness audit only. This class intentionally never calls VirtualCore.startup()
 * because the imported legacy engine requires its complete stub component/process topology.
 */
public final class VirtualAppReadinessReport {
    private VirtualAppReadinessReport() {}

    public static String create(Context context) {
        StringBuilder out = new StringBuilder();
        out.append("USBTool / VirtualApp 运行前检查\n\n");
        out.append("Android API：").append(Build.VERSION.SDK_INT).append("\n");
        out.append("设备 ABI：");
        boolean arm64 = false;
        for (String abi : Build.SUPPORTED_ABIS) {
            out.append(abi).append(" ");
            if ("arm64-v8a".equals(abi)) arm64 = true;
        }
        out.append("\nARM64 设备：").append(arm64 ? "是" : "否").append("\n");

        boolean corePresent = classExists("com.lody.virtual.client.core.VirtualCore");
        boolean clientPresent = classExists("com.lody.virtual.client.VClientImpl");
        boolean startupPresent = hasStartupMethod();
        out.append("VirtualCore：").append(corePresent ? "已包含" : "缺失").append("\n");
        out.append("VClientImpl：").append(clientPresent ? "已包含" : "缺失").append("\n");
        out.append("VirtualCore.startup(Context)：")
                .append(startupPresent ? "方法存在（未执行）" : "方法缺失").append("\n");

        File nativeLib = new File(context.getApplicationInfo().nativeLibraryDir, "libva++.so");
        out.append("libva++.so：").append(nativeLib.isFile() ? "已打包" : "缺失");
        if (nativeLib.isFile()) out.append("（").append(nativeLib.length()).append(" bytes）");
        out.append("\n");

        try {
            PackageManager pm = context.getPackageManager();
            PackageInfo info = pm.getPackageInfo(context.getPackageName(),
                    PackageManager.GET_ACTIVITIES | PackageManager.GET_SERVICES
                    | PackageManager.GET_RECEIVERS | PackageManager.GET_PROVIDERS);
            int activities = info.activities == null ? 0 : info.activities.length;
            int services = info.services == null ? 0 : info.services.length;
            int receivers = info.receivers == null ? 0 : info.receivers.length;
            int providers = info.providers == null ? 0 : info.providers.length;
            out.append("合并 Manifest 组件：Activity ").append(activities)
                    .append(" / Service ").append(services)
                    .append(" / Receiver ").append(receivers)
                    .append(" / Provider ").append(providers).append("\n");
            out.append("组件清单：").append(componentNames(info)).append("\n");
        } catch (Throwable e) {
            out.append("Manifest 组件读取失败：").append(e.getClass().getSimpleName()).append("\n");
        }

        boolean depsPresent = Build.VERSION.SDK_INT >= 29 && arm64 && corePresent
                && clientPresent && startupPresent && nativeLib.isFile();
        out.append("\n静态依赖检查：")
                .append(depsPresent ? "通过" : "未通过").append("\n");
        out.append("运行状态：未验证 / 未启动\n\n");
        out.append("重要：此页面不会调用 VirtualCore.startup()，不会注入系统服务，也不会启动导入 APK。");
        out.append(" 仅有 Java 类和 libva++.so 不足以证明虚拟化可用。还必须验证 Stub Activity/Service/Provider、");
        out.append("服务进程、Provider 初始化顺序、系统 Hook、APK 安装和真实组件启动。");
        out.append(" 当前也不提供独立 Android UID 或安全沙箱。");
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

    private static boolean hasStartupMethod() {
        try {
            Class<?> core = Class.forName("com.lody.virtual.client.core.VirtualCore", false,
                    VirtualAppReadinessReport.class.getClassLoader());
            Method method = core.getMethod("startup", Context.class);
            return method != null;
        } catch (Throwable ignored) {
            return false;
        }
    }

    private static String componentNames(PackageInfo info) {
        StringBuilder names = new StringBuilder();
        append(names, info.activities);
        append(names, info.services);
        append(names, info.receivers);
        append(names, info.providers);
        if (names.length() == 0) return "未声明组件";
        if (names.length() > 700) return names.substring(0, 700) + "…";
        return names.toString();
    }

    private static void append(StringBuilder out, android.content.pm.ComponentInfo[] items) {
        if (items == null) return;
        for (android.content.pm.ComponentInfo item : items) {
            if (out.length() > 0) out.append(", ");
            out.append(item.name);
        }
    }
}
JAVA

echo "Phase 17: add a non-invasive runtime topology audit; VirtualCore startup remains disabled."
