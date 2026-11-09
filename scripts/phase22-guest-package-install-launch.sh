#!/usr/bin/env bash
set -euo pipefail
ROOT="USBTool/app/src/main/java/com/ssai/usbtool"
mkdir -p "$ROOT/runtime/virtualapp"
cat > "$ROOT/runtime/virtualapp/VirtualAppPackageRunner.java" <<'JAVA'
package com.ssai.usbtool.runtime.virtualapp;

import android.content.Context;
import android.content.Intent;

import com.lody.virtual.client.core.InstallStrategy;
import com.lody.virtual.client.core.VirtualCore;
import com.lody.virtual.client.ipc.VActivityManager;
import com.lody.virtual.remote.InstallResult;

/**
 * Experimental end-to-end package path through VirtualApp. Requires a
 * successful VirtualCore startup and correctly merged stub components.
 */
public final class VirtualAppPackageRunner {
    private VirtualAppPackageRunner() {}

    public static String installAndLaunch(Context context, String apkPath,
                                          String expectedPackage) {
        try {
            VirtualCore core = VirtualCore.get();
            if (!core.isStartup()) {
                core.startup(context.getApplicationContext());
            }
            core.initialize(new VirtualCore.VirtualInitializer() {});
            core.waitForEngine();

            InstallResult result = core.installPackage(
                    apkPath, InstallStrategy.UPDATE_IF_EXIST);
            if (result == null) return "虚拟安装失败：引擎未返回安装结果";
            if (!result.isSuccess) {
                return "虚拟安装失败：" + String.valueOf(result.error);
            }
            String pkg = result.packageName == null
                    ? expectedPackage : result.packageName;
            if (!expectedPackage.equals(pkg)) {
                return "包名不匹配：预期 " + expectedPackage + "，实际 " + pkg;
            }
            Intent launch = core.getLaunchIntent(pkg, 0);
            if (launch == null) {
                return "虚拟安装成功（" + pkg + "），但没有可解析的桌面启动 Activity";
            }
            int status = VActivityManager.get().startActivity(launch, 0);
            return "虚拟安装成功：" + pkg + "\n启动请求返回码：" + status
                    + "\n请观察 guest APK 是否实际显示并正常交互；返回码不等于真机启动验证。";
        } catch (Throwable error) {
            return "VirtualApp 安装/启动异常："
                    + error.getClass().getName() + "\n"
                    + String.valueOf(error.getMessage());
        }
    }
}
JAVA
python3 - <<'PY'
from pathlib import Path
p=Path("USBTool/app/src/main/java/com/ssai/usbtool/MainActivity.java")
s=p.read_text()
imp="import com.ssai.usbtool.runtime.virtualapp.VirtualCoreStartupProbe;\n"
if "VirtualAppPackageRunner" not in s:
    s=s.replace(imp, imp+"import com.ssai.usbtool.runtime.virtualapp.VirtualAppPackageRunner;\n")
marker='            Button loadDex = new Button(this);\n'
if "实验：安装并启动虚拟 APK" not in s:
    button='''            Button virtualRun = new Button(this);
            virtualRun.setText("实验：安装并启动虚拟 APK");
            virtualRun.setOnClickListener(v -> new AlertDialog.Builder(this)
                    .setTitle("虚拟安装并启动")
                    .setMessage("将尝试通过 VirtualApp 安装该 APK，并启动其主 Activity。此实验可能因 ROM Hook、Stub 组件或进程配置不完整而失败。")
                    .setNegativeButton("取消", null)
                    .setPositiveButton("继续", (dialog, which) -> {
                        String result = VirtualAppPackageRunner.installAndLaunch(
                                this, app.apkPath, app.packageName);
                        new AlertDialog.Builder(this)
                                .setTitle("虚拟 APK 启动结果")
                                .setMessage(result)
                                .setPositiveButton("关闭", null)
                                .show();
                    }).show());
            card.addView(virtualRun);

'''
    if marker not in s: raise SystemExit("MainActivity insertion marker missing")
    s=s.replace(marker,button+marker)
p.write_text(s)
PY
echo "Phase 22: adds explicit VirtualApp package install/launch experiment; device validation still required."
