#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
import re
root = Path("USBTool/app/src/main/java/com/ssai/usbtool")
runtime = root / "runtime"
runtime.mkdir(parents=True, exist_ok=True)

registry = runtime / "ImportedApkRuntimeRegistry.java"
registry.write_text("""package com.ssai.usbtool.runtime;

import java.util.HashMap;
import java.util.Map;

/** Keeps plugin class loaders and resource tables alive for the host process lifetime. */
public final class ImportedApkRuntimeRegistry {
    private static final Map<String, ImportedApkLoader.Session> SESSIONS = new HashMap<>();
    private ImportedApkRuntimeRegistry() {}

    public static synchronized void retain(String key, ImportedApkLoader.Session session) {
        if (key == null || key.trim().isEmpty() || session == null) {
            throw new IllegalArgumentException("运行时会话标识或内容为空");
        }
        SESSIONS.put(key, session);
    }

    public static synchronized ImportedApkLoader.Session get(String key) {
        return SESSIONS.get(key);
    }

    public static synchronized int size() { return SESSIONS.size(); }
}
""")

main = root / "MainActivity.java"
s = main.read_text()
for imp in [
    "import com.ssai.usbtool.runtime.ImportedApkLoader;\n",
    "import com.ssai.usbtool.runtime.ImportedApkRuntimeRegistry;\n",
]:
    if imp not in s:
        anchor = "import com.ssai.usbtool.runtime.ipc.RuntimeProcessClient;\n"
        if anchor in s: s = s.replace(anchor, anchor + imp, 1)
        else: s = s.replace("import java.util.UUID;\n", "import java.util.UUID;\n" + imp, 1)

pattern = r"    private void testLoadDex\(ProfileStore\.AppRecord app\) \{.*?\n    \}\n\n    private void analyzeBootstrap"
replacement = """    private void testLoadDex(ProfileStore.AppRecord app) {
        try {
            ProfileStore.AppRecord current = app;
            if (current.profiles.isEmpty()) {
                store.createProfile(app.id);
                for (ProfileStore.AppRecord candidate : store.getAll()) {
                    if (candidate.id.equals(app.id)) { current = candidate; break; }
                }
            }
            if (current.profiles.isEmpty()) throw new IllegalStateException("无法创建实例目录");
            ProfileStore.Profile profile = current.profiles.get(0);
            String key = app.id + ":" + profile.id;
            ImportedApkLoader.Session session = ImportedApkRuntimeRegistry.get(key);
            if (session == null) {
                session = ImportedApkLoader.open(this, new File(app.apkPath), profile.id);
                ImportedApkRuntimeRegistry.retain(key, session);
            }

            ImportedApkDescriptor descriptor = ImportedApkDescriptorReader.read(
                    this, new File(app.apkPath));
            StringBuilder report = new StringBuilder(session.report);
            report.append(" | 实例会话：已保留（").append(key).append("）");
            report.append(" | 当前进程会话数：").append(ImportedApkRuntimeRegistry.size());
            if (descriptor.applicationClass != null
                    && !descriptor.applicationClass.trim().isEmpty()
                    && !"android.app.Application".equals(descriptor.applicationClass)) {
                try {
                    Class<?> applicationType = Class.forName(
                            descriptor.applicationClass, false, session.classLoader);
                    report.append(" | Application 类解析：成功（")
                            .append(applicationType.getName()).append("）");
                    report.append(" | 安全模式：未初始化类、未执行 Application.onCreate()");
                } catch (Throwable classError) {
                    report.append(" | Application 类解析：失败（")
                            .append(classError.getClass().getSimpleName()).append(": ")
                            .append(String.valueOf(classError.getMessage())).append("）");
                }
            } else {
                report.append(" | Application 类：使用 Android 默认 Application");
                report.append(" | 安全模式：未创建 Application 实例");
            }
            report.append(" | 说明：这不是 APK 启动；组件生命周期、Provider、系统服务代理仍未完成。");
            new AlertDialog.Builder(this).setTitle(app.label + " - 运行时探测")
                    .setMessage(report.toString()).setPositiveButton("关闭", null).show();
        } catch (Throwable e) {
            new AlertDialog.Builder(this).setTitle("运行时探测失败")
                    .setMessage(e.getMessage() == null ? e.toString() : e.getMessage())
                    .setPositiveButton("关闭", null).show();
        }
    }

    private void analyzeBootstrap"""
s2, n = re.subn(pattern, lambda match: replacement, s, count=1, flags=re.S)
if n != 1:
    raise SystemExit("Could not replace Phase 11 testLoadDex method; source layout changed")
main.write_text(s2)
print("Phase 12 added retained per-instance runtime sessions and non-initializing Application class resolution probe.")
PY
