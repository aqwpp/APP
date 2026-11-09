#!/usr/bin/env bash
set -euo pipefail
RUNNER="USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java"
ACTIVITY="USBTool/app/src/main/java/com/ssai/usbtool/MainActivity.java"
test -s "$RUNNER"; test -s "$ACTIVITY"
python3 - <<'PY'
from pathlib import Path
p=Path("USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java")
s=p.read_text()
if "import java.util.concurrent.Callable;" not in s:
    s=s.replace("import java.util.concurrent.ExecutorService;", "import java.util.concurrent.Callable;\nimport java.util.concurrent.ExecutorService;")
start=s.index("    private static void awaitEngineOffMain(VirtualCore core)")
end=s.index("    /** Package parsing/install and launch request are performed off the UI thread. */", start)
helper="""    private static <T> T callBounded(String stage, Callable<T> action, long timeoutSeconds) throws Exception {
        FutureTask<T> task = new FutureTask<>(action);
        Thread worker = new Thread(task, "USBTool-RPC-" + stage.replace(' ', '-'));
        worker.setDaemon(true);
        worker.start();
        try {
            return task.get(timeoutSeconds, TimeUnit.SECONDS);
        } catch (TimeoutException timeout) {
            task.cancel(true);
            throw new IllegalStateException("阶段超时：" + stage + "，超过 " + timeoutSeconds
                    + " 秒；Binder/VirtualApp 服务可能无响应。", timeout);
        }
    }

    private static void awaitEngineOffMain(VirtualCore core) throws Exception {
        callBounded("等待引擎", () -> { core.waitForEngine(); return null; }, 25);
    }

"""
s=s[:start]+helper+s[end:]
s=s.replace("""                InstallResult install = core.installPackage(
                        apk.getAbsolutePath(), InstallStrategy.UPDATE_IF_EXIST);""","""                InstallResult install = callBounded("虚拟安装 APK", () -> core.installPackage(
                        apk.getAbsolutePath(), InstallStrategy.UPDATE_IF_EXIST), 60);""")
s=s.replace("""                boolean installed = core.isAppInstalled(pkg);
                boolean launchable = core.isPackageLaunchable(pkg);
                boolean engineRunning = core.isEngineLaunched();""","""                boolean installed = callBounded("检查安装状态", () -> core.isAppInstalled(pkg), 20);
                boolean launchable = callBounded("检查启动入口", () -> core.isPackageLaunchable(pkg), 20);
                boolean engineRunning = callBounded("检查引擎进程", core::isEngineLaunched, 15);""")
s=s.replace("""                Intent launch = core.getLaunchIntent(pkg, 0);""","""                Intent launch = callBounded("获取启动 Intent", () -> core.getLaunchIntent(pkg, 0), 20);""")
s=s.replace("""                    int status = VActivityManager.get().startActivity(launch, 0);""","""                    int status = callBounded("启动虚拟 Activity",
                            () -> VActivityManager.get().startActivity(launch, 0), 30);""")
s=s.replace("""                        + "\\nEngine launched: " + core.isEngineLaunched()""","""                        + "\\nEngine launched: " + safeEngineState(core)""")
insert="""    private static String safeEngineState(VirtualCore core) {
        try {
            return callBounded("读取引擎状态", core::isEngineLaunched, 3).toString();
        } catch (Throwable ignored) {
            return "unknown (query timed out or failed)";
        }
    }

"""
idx=s.index("    private static String readServerBootMarker(Context context)")
s=s[:idx]+insert+s[idx:]
p.write_text(s)

p=Path("USBTool/app/src/main/java/com/ssai/usbtool/MainActivity.java")
s=p.read_text()
old="""                        try {
                            VirtualAppPackageRunner.prepareOnMain(this);
                        } catch (Throwable error) {
                            new AlertDialog.Builder(this).setTitle("VirtualCore 初始化失败")
                                    .setMessage(error.getClass().getName() + "\\n" + String.valueOf(error.getMessage()))
                                    .setPositiveButton("关闭", null).show();
                            return;
                        }
                        android.app.ProgressDialog progress = new android.app.ProgressDialog(this);
                        progress.setMessage("正在虚拟安装并启动 APK…");
                        progress.setCancelable(false);
                        progress.show();"""
new="""                        android.app.ProgressDialog progress = new android.app.ProgressDialog(this);
                        progress.setMessage("正在初始化 VirtualCore…");
                        progress.setCancelable(false);
                        progress.show();
                        try {
                            // Display progress before synchronous framework-hook initialization.
                            VirtualAppPackageRunner.prepareOnMain(this);
                        } catch (Throwable error) {
                            progress.dismiss();
                            new AlertDialog.Builder(this).setTitle("VirtualCore 初始化失败")
                                    .setMessage(error.getClass().getName() + "\\n" + String.valueOf(error.getMessage()))
                                    .setPositiveButton("关闭", null).show();
                            return;
                        }
                        progress.setMessage("正在虚拟安装并启动 APK…");"""
if old not in s: raise SystemExit("MainActivity progress/prepare anchor missing")
s=s.replace(old,new,1)
p.write_text(s)
PY
grep -q '阶段超时：' "$RUNNER"
grep -q 'callBounded("虚拟安装 APK"' "$RUNNER"
grep -q 'Display progress before synchronous framework-hook initialization' "$ACTIVITY"
cat > USBTool/BUILD_AUDIT_PHASE39.txt <<'AUDIT'
USBTool Phase 39 - bounded VirtualApp Binder operations and visible startup progress
- Phase 38 bounded only waitForEngine; installPackage and subsequent IPC calls could still block forever.
- Added daemon-thread bounded calls for engine readiness (25s), package install (60s), package state and launch-intent queries (15-20s), and Activity launch (30s).
- Timeout errors identify the exact stage and explain that Binder/VirtualApp may be unresponsive.
- Error reporting bounds the engine-state probe so a failed Binder call cannot hang the error dialog construction.
- MainActivity now displays progress before synchronous VirtualCore framework-hook startup and dismisses it on initialization exceptions.
- Build/source audit only. This does not claim the underlying Binder server crash or Android 10 framework-hook compatibility is fixed; physical-device validation remains required.
AUDIT
echo "Phase 39 bounded IPC source audit passed."
