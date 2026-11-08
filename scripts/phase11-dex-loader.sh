#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
root = Path("USBTool/app/src/main/java/com/ssai/usbtool")
pkg = root / "runtime"
pkg.mkdir(parents=True, exist_ok=True)
loader = pkg / "ImportedApkLoader.java"
loader.write_text("""package com.ssai.usbtool.runtime;

import android.content.Context;
import android.content.res.AssetManager;
import android.content.res.Resources;
import dalvik.system.DexClassLoader;
import java.io.File;
import java.util.zip.ZipFile;

/** Loads an imported APK's DEX and resource table into an isolated host-side loader.
 * This is a loader primitive, not a complete Android application/component runtime.
 */
public final class ImportedApkLoader {
    public static final class Session {
        public final DexClassLoader classLoader;
        public final Resources resources;
        public final String report;
        Session(DexClassLoader cl, Resources res, String report) {
            this.classLoader = cl; this.resources = res; this.report = report;
        }
    }

    private ImportedApkLoader() {}

    public static Session open(Context context, File apk, String instanceId) throws Exception {
        if (apk == null || !apk.isFile() || !apk.canRead()) {
            throw new IllegalArgumentException("APK 文件不存在或不可读");
        }
        try (ZipFile zip = new ZipFile(apk)) {
            if (zip.getEntry("classes.dex") == null) {
                throw new IllegalArgumentException("APK 中没有 classes.dex（可能是资源包或拆分 APK）");
            }
            if (zip.getEntry("AndroidManifest.xml") == null) {
                throw new IllegalArgumentException("缺少 AndroidManifest.xml");
            }
        }
        File base = new File(context.getFilesDir(), "runtime");
        File opt = new File(base, "dex/" + safe(instanceId));
        File nativeDir = new File(base, "native/" + safe(instanceId));
        if (!opt.exists() && !opt.mkdirs()) throw new IllegalStateException("无法创建 DEX 优化目录");
        if (!nativeDir.exists() && !nativeDir.mkdirs()) throw new IllegalStateException("无法创建 native 目录");

        DexClassLoader cl = new DexClassLoader(apk.getAbsolutePath(),
                opt.getAbsolutePath(), nativeDir.getAbsolutePath(), context.getClassLoader());

        AssetManager assets = AssetManager.class.getDeclaredConstructor().newInstance();
        java.lang.reflect.Method add = AssetManager.class.getMethod("addAssetPath", String.class);
        int cookie = (Integer) add.invoke(assets, apk.getAbsolutePath());
        if (cookie == 0) throw new IllegalStateException("AssetManager 无法挂载 APK 资源");
        Resources host = context.getResources();
        Resources res = new Resources(assets, host.getDisplayMetrics(), host.getConfiguration());
        String report = "DEX 加载器：已创建\\n"
                + "APK：" + apk.getName() + "\\n"
                + "classes.dex：存在\\n"
                + "资源表：已挂载\\n"
                + "实例隔离目录：" + opt.getAbsolutePath() + "\\n"
                + "注意：尚未初始化 Application，也未启动 APK Activity/Service。";
        return new Session(cl, res, report);
    }

    private static String safe(String value) {
        if (value == null || value.isEmpty()) return "default";
        return value.replaceAll("[^A-Za-z0-9_-]", "_");
    }
}
""")
main = root / "MainActivity.java"
s = main.read_text()
if "import com.ssai.usbtool.runtime.ImportedApkLoader;" not in s:
    s = s.replace("import com.ssai.usbtool.runtime.ipc.RuntimeProcessClient;\n",
                  "import com.ssai.usbtool.runtime.ipc.RuntimeProcessClient;\nimport com.ssai.usbtool.runtime.ImportedApkLoader;\n")
needle = '''            Button analyze = new Button(this);
            analyze.setText("分析 Application / 组件启动条件");'''
insert = '''            Button loadDex = new Button(this);
            loadDex.setText("测试加载 APK DEX / 资源");
            loadDex.setOnClickListener(v -> testLoadDex(app));
            card.addView(loadDex);

            Button analyze = new Button(this);
            analyze.setText("分析 Application / 组件启动条件");'''
if needle not in s: raise SystemExit("MainActivity insertion point missing")
s = s.replace(needle, insert, 1)
method = '''
    private void testLoadDex(ProfileStore.AppRecord app) {
        try {
            ProfileStore.Profile profile = app.profiles.isEmpty()
                    ? store.createProfile(app.id) : app.profiles.get(0);
            ImportedApkLoader.Session session = ImportedApkLoader.open(
                    this, new File(app.apkPath), profile.id);
            new AlertDialog.Builder(this).setTitle(app.label + " - DEX / 资源加载")
                    .setMessage(session.report).setPositiveButton("关闭", null).show();
        } catch (Exception e) {
            new AlertDialog.Builder(this).setTitle("DEX / 资源加载失败")
                    .setMessage(e.getMessage() == null ? e.toString() : e.getMessage())
                    .setPositiveButton("关闭", null).show();
        }
    }

'''
marker = "    private void analyzeBootstrap(ProfileStore.AppRecord app) {"
if "private void testLoadDex(" not in s:
    if marker not in s: raise SystemExit("MainActivity method insertion point missing")
    s = s.replace(marker, method + marker, 1)
main.write_text(s)
print("Phase 11 loader added: DexClassLoader + per-profile optimized/native directories + AssetManager resource mounting + UI probe.")
PY
