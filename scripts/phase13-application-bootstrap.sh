#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
import re
root = Path("USBTool/app/src/main/java/com/ssai/usbtool")
runtime = root / "runtime"
runtime.mkdir(parents=True, exist_ok=True)

(runtime / "PluginApplicationContext.java").write_text("""package com.ssai.usbtool.runtime;

import android.content.Context;
import android.content.ContextWrapper;
import android.content.pm.ApplicationInfo;
import android.content.res.AssetManager;
import android.content.res.Resources;
import java.io.File;

/** Best-effort per-profile Context for an in-process Application bootstrap experiment.
 * PackageManager, Binder services, permissions and UID remain those of USBTool.
 */
public final class PluginApplicationContext extends ContextWrapper {
    private final String pluginPackage;
    private final File dataRoot;
    private final Resources pluginResources;
    private final ClassLoader pluginClassLoader;
    private final ApplicationInfo pluginInfo;

    public PluginApplicationContext(Context base, String packageName, File dataDir,
                                    Resources resources, ClassLoader classLoader,
                                    String apkPath) {
        super(base);
        if (base == null || packageName == null || dataDir == null
                || resources == null || classLoader == null) {
            throw new IllegalArgumentException("插件 Context 参数不完整");
        }
        this.pluginPackage = packageName;
        this.dataRoot = dataDir;
        this.pluginResources = resources;
        this.pluginClassLoader = classLoader;
        if (!dataRoot.exists() && !dataRoot.mkdirs()) {
            throw new IllegalStateException("无法创建实例数据目录：" + dataRoot);
        }
        pluginInfo = new ApplicationInfo();
        pluginInfo.packageName = packageName;
        pluginInfo.sourceDir = apkPath;
        pluginInfo.publicSourceDir = apkPath;
        pluginInfo.dataDir = dataRoot.getAbsolutePath();
        pluginInfo.nativeLibraryDir = new File(dataRoot, "lib").getAbsolutePath();
        pluginInfo.targetSdkVersion = 29;
    }

    @Override public String getPackageName() { return pluginPackage; }
    @Override public ApplicationInfo getApplicationInfo() { return pluginInfo; }
    @Override public Resources getResources() { return pluginResources; }
    @Override public AssetManager getAssets() { return pluginResources.getAssets(); }
    @Override public ClassLoader getClassLoader() { return pluginClassLoader; }
    @Override public Context getApplicationContext() { return this; }
    @Override public File getFilesDir() { return child("files"); }
    @Override public File getCacheDir() { return child("cache"); }
    @Override public File getCodeCacheDir() { return child("code_cache"); }
    @Override public File getNoBackupFilesDir() { return child("no_backup"); }
    @Override public File getDatabasePath(String name) {
        File db = new File(child("databases"), name);
        File parent = db.getParentFile();
        if (parent != null && !parent.exists()) parent.mkdirs();
        return db;
    }
    @Override public File getDir(String name, int mode) { return child("app_" + name); }
    @Override public android.content.SharedPreferences getSharedPreferences(String name, int mode) {
        return super.getSharedPreferences(pluginPackage + "_" + safe(name), mode);
    }

    private File child(String name) {
        File file = new File(dataRoot, name);
        if (!file.exists() && !file.mkdirs()) {
            throw new IllegalStateException("无法创建实例目录：" + file);
        }
        return file;
    }
    private static String safe(String value) {
        return value == null ? "default" : value.replaceAll("[^A-Za-z0-9_.-]", "_");
    }
}
""")

(runtime / "PluginApplicationBootstrapper.java").write_text("""package com.ssai.usbtool.runtime;

import android.app.Application;
import android.app.Instrumentation;
import android.content.Context;
import com.ssai.usbtool.runtime.bootstrap.ImportedApkDescriptor;
import java.io.File;

/** Explicit, opt-in Application-only bootstrap. Not an Android component runtime. */
public final class PluginApplicationBootstrapper {
    private PluginApplicationBootstrapper() {}

    public static Application start(Context host, ImportedApkDescriptor descriptor,
                                    ImportedApkLoader.Session session, File profileDir)
            throws Exception {
        if (host == null || descriptor == null || session == null || profileDir == null) {
            throw new IllegalArgumentException("Application 启动参数不完整");
        }
        if (!descriptor.hasCode) throw new IllegalArgumentException("APK 声明未包含可执行代码");
        String className = descriptor.applicationClass;
        if (className == null || className.trim().isEmpty()) {
            className = "android.app.Application";
        }
        PluginApplicationContext pluginContext = new PluginApplicationContext(
                host, descriptor.packageName, profileDir, session.resources,
                session.classLoader, descriptor.apkPath);
        Instrumentation instrumentation = new Instrumentation();
        Application app = instrumentation.newApplication(
                session.classLoader, className, pluginContext);
        instrumentation.callApplicationOnCreate(app);
        return app;
    }
}
""")

registry = runtime / "ImportedApkRuntimeRegistry.java"
s = registry.read_text()
if "APPLICATIONS" not in s:
    s = s.replace("private static final Map<String, ImportedApkLoader.Session> SESSIONS = new HashMap<>();",
                  "private static final Map<String, ImportedApkLoader.Session> SESSIONS = new HashMap<>();\n"
                  "    private static final Map<String, android.app.Application> APPLICATIONS = new HashMap<>();")
    s = s.replace("    public static synchronized int size() { return SESSIONS.size(); }",
                  "    public static synchronized void retainApplication(String key, android.app.Application app) {\n"
                  "        if (key == null || app == null) throw new IllegalArgumentException(\"Application 会话为空\");\n"
                  "        APPLICATIONS.put(key, app);\n"
                  "    }\n"
                  "    public static synchronized android.app.Application getApplication(String key) { return APPLICATIONS.get(key); }\n"
                  "    public static synchronized int applicationCount() { return APPLICATIONS.size(); }\n"
                  "    public static synchronized int size() { return SESSIONS.size(); }")
    registry.write_text(s)

main = root / "MainActivity.java"
s = main.read_text()
for imp in [
    "import com.ssai.usbtool.runtime.PluginApplicationBootstrapper;\n",
]:
    if imp not in s:
        anchor = "import com.ssai.usbtool.runtime.ImportedApkRuntimeRegistry;\n"
        if anchor not in s: raise SystemExit("Phase 12 runtime imports not found")
        s = s.replace(anchor, anchor + imp, 1)

needle = '''            Button analyze = new Button(this);
            analyze.setText("分析 Application / 组件启动条件");'''
insert = '''            Button bootstrap = new Button(this);
            bootstrap.setText("实验：初始化 APK Application");
            bootstrap.setOnClickListener(v -> confirmApplicationBootstrap(app));
            card.addView(bootstrap);

            Button analyze = new Button(this);
            analyze.setText("分析 Application / 组件启动条件");'''
if "confirmApplicationBootstrap(app)" not in s:
    if needle not in s: raise SystemExit("MainActivity Application action insertion point missing")
    s = s.replace(needle, insert, 1)

method = """
    private void confirmApplicationBootstrap(ProfileStore.AppRecord app) {
        new AlertDialog.Builder(this)
                .setTitle("执行导入 APK 代码？")
                .setMessage("这会在 USBTool 的进程和 UID 中执行该 APK 的 Application 构造及 onCreate()。"
                        + "\\n它不是安全沙箱；导入代码可能访问 USBTool 可用的权限和数据。"
                        + "\\n目前仅提供尽力而为的实例目录/资源/类加载上下文，不代理 PackageManager、权限、Provider 或系统服务。"
                        + "\\n只对你信任的 APK 继续。")
                .setNegativeButton("取消", null)
                .setPositiveButton("继续执行", (dialog, which) -> runApplicationBootstrap(app))
                .show();
    }

    private void runApplicationBootstrap(ProfileStore.AppRecord app) {
        try {
            ProfileStore.AppRecord current = app;
            if (current.profiles.isEmpty()) {
                store.createProfile(app.id);
                for (ProfileStore.AppRecord candidate : store.getAll()) {
                    if (candidate.id.equals(app.id)) { current = candidate; break; }
                }
            }
            if (current.profiles.isEmpty()) throw new IllegalStateException("没有可用实例");
            ProfileStore.Profile profile = current.profiles.get(0);
            String key = app.id + ":" + profile.id;
            android.app.Application existing = ImportedApkRuntimeRegistry.getApplication(key);
            if (existing != null) {
                new AlertDialog.Builder(this).setTitle("Application 已初始化")
                        .setMessage("此实例已执行过 Application.onCreate()。当前进程中不会重复执行。")
                        .setPositiveButton("关闭", null).show();
                return;
            }
            ImportedApkLoader.Session session = ImportedApkRuntimeRegistry.get(key);
            if (session == null) {
                session = ImportedApkLoader.open(this, new File(app.apkPath), profile.id);
                ImportedApkRuntimeRegistry.retain(key, session);
            }
            ImportedApkDescriptor descriptor = ImportedApkDescriptorReader.read(
                    this, new File(app.apkPath));
            android.app.Application application = PluginApplicationBootstrapper.start(
                    this, descriptor, session, new File(profile.dataDir));
            ImportedApkRuntimeRegistry.retainApplication(key, application);
            new AlertDialog.Builder(this).setTitle("Application 初始化成功")
                    .setMessage("类：" + application.getClass().getName()
                            + "\\n实例：" + profile.id
                            + "\\n已调用 Application.onCreate()。"
                            + "\\n注意：这不代表 Activity/Service/Provider 可启动，也不构成独立 UID 或安全隔离。")
                    .setPositiveButton("关闭", null).show();
        } catch (Throwable e) {
            new AlertDialog.Builder(this).setTitle("Application 初始化失败")
                    .setMessage(e.getClass().getSimpleName() + ": "
                            + (e.getMessage() == null ? e.toString() : e.getMessage()))
                    .setPositiveButton("关闭", null).show();
        }
    }

"""
marker = "    private void testLoadDex(ProfileStore.AppRecord app) {"
if "private void runApplicationBootstrap(" not in s:
    if marker not in s: raise SystemExit("MainActivity method insertion point missing")
    s = s.replace(marker, method + marker, 1)
main.write_text(s)
print("Phase 13 added opt-in Application bootstrap with per-profile file/preferences paths and explicit code-execution warning.")
PY
