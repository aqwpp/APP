#!/usr/bin/env bash
set -euo pipefail
RUNNER="USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java"
test -s "$RUNNER"
python3 - <<'PY'
from pathlib import Path
p = Path("USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java")
s = p.read_text()
old = '''                Intent launch = core.getLaunchIntent(pkg, 0);
                if (launch == null) {
                    result = "虚拟安装成功（" + pkg + "），但没有可解析的桌面启动 Activity";
                } else {
                    int status = VActivityManager.get().startActivity(launch, 0);
                    result = "虚拟安装成功：" + pkg + "\\n启动请求返回码：" + status
                            + "\\n返回码不等于 guest 已成功显示；请观察应用是否实际启动。";
                }'''
new = '''                boolean installed = core.isAppInstalled(pkg);
                boolean launchable = core.isPackageLaunchable(pkg);
                boolean engineRunning = core.isEngineLaunched();
                if (!installed) {
                    throw new IllegalStateException("安装结果返回成功，但引擎查询不到已安装包：" + pkg);
                }
                Intent launch = core.getLaunchIntent(pkg, 0);
                if (!launchable || launch == null) {
                    result = "虚拟安装成功：" + pkg
                            + "\\n引擎进程运行：" + engineRunning
                            + "\\n包已安装：" + installed
                            + "\\n可启动 Activity：" + launchable
                            + "\\n未找到可启动的桌面 Activity。";
                } else {
                    int status = VActivityManager.get().startActivity(launch, 0);
                    result = "虚拟安装成功：" + pkg
                            + "\\n引擎进程运行：" + engineRunning
                            + "\\n包已安装：" + installed
                            + "\\n可启动 Activity：" + launchable
                            + "\\n启动请求返回码：" + status
                            + "\\n注意：请求已提交不代表 guest 界面已成功显示。";
                }'''
if old not in s:
    raise SystemExit("Phase 26 patch anchor not found; refusing unsafe edit")
p.write_text(s.replace(old, new, 1))
PY
grep -q 'core.isAppInstalled(pkg)' "$RUNNER"
grep -q 'core.isPackageLaunchable(pkg)' "$RUNNER"
grep -q 'core.isEngineLaunched()' "$RUNNER"
cat > USBTool/BUILD_AUDIT_PHASE26.txt <<'AUDIT'
USBTool Phase 26 - guest install and launch diagnostics
Package: com.ssai.usbtool
Target: Android 10 / API 29; ARM64 native runtime

Added runtime checks after VirtualApp install:
- Query whether VirtualApp reports the guest package installed.
- Query whether the package has a launchable Activity.
- Query whether the VirtualApp engine process is running.
- Include these states with the launch request result.
- Treat a contradictory install-success / package-not-installed result as an error.

Not verified:
- Actual guest Activity display on a physical Android 10 ARM64 device.
- Framework hook stability, guest process lifecycle, or arbitrary APK compatibility.
- Separate guest UID, permission isolation, or a security sandbox.
AUDIT
echo "Phase 26 guest install/launch diagnostic source audit passed."
