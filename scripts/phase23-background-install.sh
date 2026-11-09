#!/usr/bin/env bash
set -euo pipefail
ROOT="USBTool/app/src/main/java/com/ssai/usbtool"
python3 - <<'PY'
from pathlib import Path
p=Path("USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java")
s=p.read_text()
s=s.replace('import android.content.Intent;','import android.content.Intent;\nimport android.os.Handler;\nimport android.os.Looper;\nimport java.io.File;\nimport java.util.concurrent.ExecutorService;\nimport java.util.concurrent.Executors;')
start=s.index('    public static String installAndLaunch(')
end=s.rindex('}')
body='''    public interface Callback { void onComplete(String result); }
    private static final ExecutorService EXECUTOR = Executors.newSingleThreadExecutor();
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    /** Must be called from the host main thread: VirtualCore startup installs framework hooks. */
    public static void prepareOnMain(Context context) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            throw new IllegalStateException("VirtualCore 初始化必须在主线程执行");
        }
        VirtualCore core = VirtualCore.get();
        if (!core.isStartup()) core.startup(context.getApplicationContext());
        core.initialize(new VirtualCore.VirtualInitializer() {});
        core.waitForEngine();
    }

    /** Package parsing/install and launch request are performed off the UI thread. */
    public static void installAndLaunchAsync(String apkPath, String expectedPackage,
                                             Callback callback) {
        EXECUTOR.execute(() -> {
            String result;
            try {
                File apk = new File(apkPath);
                if (!apk.isFile() || !apk.canRead()) {
                    throw new IllegalArgumentException("APK 文件不存在或不可读取：" + apkPath);
                }
                VirtualCore core = VirtualCore.get();
                if (!core.isStartup()) {
                    throw new IllegalStateException("VirtualCore 尚未初始化；请先在主线程初始化引擎");
                }
                InstallResult install = core.installPackage(
                        apk.getAbsolutePath(), InstallStrategy.UPDATE_IF_EXIST);
                if (install == null) throw new IllegalStateException("引擎未返回安装结果");
                if (!install.isSuccess) throw new IllegalStateException(
                        "虚拟安装失败：" + String.valueOf(install.error));
                String pkg = install.packageName == null ? expectedPackage : install.packageName;
                if (!expectedPackage.equals(pkg)) throw new IllegalStateException(
                        "包名不匹配：预期 " + expectedPackage + "，实际 " + pkg);
                Intent launch = core.getLaunchIntent(pkg, 0);
                if (launch == null) {
                    result = "虚拟安装成功（" + pkg + "），但没有可解析的桌面启动 Activity";
                } else {
                    int status = VActivityManager.get().startActivity(launch, 0);
                    result = "虚拟安装成功：" + pkg + "\\n启动请求返回码：" + status
                            + "\\n返回码不等于 guest 已成功显示；请观察应用是否实际启动。";
                }
            } catch (Throwable error) {
                result = "VirtualApp 安装/启动异常：" + error.getClass().getName()
                        + "\\n" + String.valueOf(error.getMessage());
            }
            final String message = result;
            MAIN.post(() -> callback.onComplete(message));
        });
    }
'''
p.write_text(s[:start]+body+'}\n')
p=Path("USBTool/app/src/main/java/com/ssai/usbtool/MainActivity.java")
s=p.read_text()
old='''                        String result = VirtualAppPackageRunner.installAndLaunch(
                                this, app.apkPath, app.packageName);
                        new AlertDialog.Builder(this)
                                .setTitle("虚拟 APK 启动结果")
                                .setMessage(result)
                                .setPositiveButton("关闭", null)
                                .show();'''
new='''                        try {
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
                        progress.show();
                        VirtualAppPackageRunner.installAndLaunchAsync(
                                app.apkPath, app.packageName, result -> {
                                    if (isFinishing() || isDestroyed()) return;
                                    progress.dismiss();
                                    new AlertDialog.Builder(this)
                                            .setTitle("虚拟 APK 启动结果")
                                            .setMessage(result)
                                            .setPositiveButton("关闭", null).show();
                                });'''
if old not in s: raise SystemExit("Phase22 UI block not found; refusing unsafe patch")
s=s.replace(old,new)
p.write_text(s)
PY
echo "Phase 23: moves package install and launch work to a single background executor; VirtualCore startup remains on main thread."
