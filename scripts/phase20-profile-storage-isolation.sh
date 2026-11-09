#!/usr/bin/env bash
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
RUNTIME="$ROOT/USBTool/app/src/main/java/com/ssai/usbtool/runtime"
TESTS="$ROOT/USBTool/app/src/test/java/com/ssai/usbtool/runtime"
mkdir -p "$RUNTIME" "$TESTS"

cat > "$RUNTIME/ProfileStorageKeys.java" <<'JAVA'
package com.ssai.usbtool.runtime;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/**
 * Creates stable, collision-resistant SharedPreferences file names per imported
 * package and virtual profile. The files still live under the host UID; this is
 * logical profile separation, not an OS security boundary.
 */
public final class ProfileStorageKeys {
    private ProfileStorageKeys() {}

    public static String sharedPreferencesName(String packageName,
                                               String profileId,
                                               String preferenceName) {
        if (packageName == null || packageName.trim().isEmpty()
                || profileId == null || profileId.trim().isEmpty()
                || preferenceName == null || preferenceName.trim().isEmpty()) {
            throw new IllegalArgumentException("package、profile 和 preference 名称不能为空");
        }
        try {
            String identity = packageName.length() + ":" + packageName
                    + profileId.length() + ":" + profileId
                    + preferenceName.length() + ":" + preferenceName;
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(identity.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder("usbtool_profile_");
            for (int i = 0; i < 16; i++) {
                hex.append(String.format(java.util.Locale.ROOT, "%02x", digest[i] & 0xff));
            }
            return hex.toString();
        } catch (Exception e) {
            throw new IllegalStateException("无法计算实例存储键", e);
        }
    }
}
JAVA

python3 - "$RUNTIME/PluginApplicationContext.java" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = '''    @Override public android.content.SharedPreferences getSharedPreferences(String name, int mode) {
        return super.getSharedPreferences(pluginPackage + "_" + safe(name), mode);
    }'''
new = '''    @Override public android.content.SharedPreferences getSharedPreferences(String name, int mode) {
        // ContextWrapper delegates to the host Context. Include the profile ID in
        // a stable hashed key so two virtual profiles do not share preferences.
        // This remains host-UID storage, not a separate Android sandbox.
        String key = ProfileStorageKeys.sharedPreferencesName(
                pluginPackage, dataRoot.getName(), name);
        return super.getSharedPreferences(key, mode);
    }'''
if old not in s:
    raise SystemExit("PluginApplicationContext SharedPreferences method not found; refusing unsafe partial patch")
s = s.replace(old, new, 1)
p.write_text(s)
PY

cat > "$TESTS/ProfileStorageKeysTest.java" <<'JAVA'
package com.ssai.usbtool.runtime;

import org.junit.Test;
import static org.junit.Assert.*;

public class ProfileStorageKeysTest {
    @Test public void sameIdentityProducesStableKey() {
        assertEquals(
                ProfileStorageKeys.sharedPreferencesName("sample.app", "profile-a", "settings"),
                ProfileStorageKeys.sharedPreferencesName("sample.app", "profile-a", "settings"));
    }

    @Test public void differentProfilesNeverSharePreferencesKey() {
        String first = ProfileStorageKeys.sharedPreferencesName("sample.app", "profile-a", "settings");
        String second = ProfileStorageKeys.sharedPreferencesName("sample.app", "profile-b", "settings");
        assertNotEquals(first, second);
    }

    @Test public void differentPackagesAndPreferenceNamesAreSeparated() {
        String base = ProfileStorageKeys.sharedPreferencesName("sample.app", "profile-a", "settings");
        assertNotEquals(base,
                ProfileStorageKeys.sharedPreferencesName("other.app", "profile-a", "settings"));
        assertNotEquals(base,
                ProfileStorageKeys.sharedPreferencesName("sample.app", "profile-a", "tokens"));
    }

    @Test public void generatedKeyIsFilesystemSafeAndBounded() {
        String key = ProfileStorageKeys.sharedPreferencesName("sample.app", "profile-a", "settings");
        assertTrue(key.matches("usbtool_profile_[0-9a-f]{32}"));
        assertTrue(key.length() < 64);
    }

    @Test(expected = IllegalArgumentException.class)
    public void emptyProfileIsRejected() {
        ProfileStorageKeys.sharedPreferencesName("sample.app", " ", "settings");
    }
}
JAVA

cat > "$ROOT/USBTool/PROFILE_STORAGE_PHASE20.txt" <<'EOF'
Phase 20: per-profile SharedPreferences namespace hardening.
PluginApplicationContext now derives a stable SHA-256-based preference key from
(package name, profile ID, preference name), so two logical profiles no longer
share the same SharedPreferences file name under the host app's storage.
Files, cache, code cache, databases, no-backup files and app-specific directories
remain rooted in each profile data directory.

Security boundary: all of this still runs under USBTool's Android UID and host
permissions. The namespaced SharedPreferences files are not an OS-level sandbox;
host code or another component running as the host UID can access them.
The change does not virtualize PackageManager, Binder services, external storage,
ContentProviders, or Android permission enforcement.
EOF


cat >> "$ROOT/USBTool/README.md" <<'EOF'

## Phases 9–20: Android 10 compatibility and VirtualApp integration research

The cloud build applies the versioned scripts in the repository's `scripts/`
directory to the Phase 8 source archive. These steps are reproducible build-time
patches; the generated project is included in the Phase 20 source artifact.

Implemented and build-checked:
- APK import size bound (512 MiB), archive manifest validation, failed-import
  cleanup, and atomic JSON registry replacement.
- Experimental `DexClassLoader` / `AssetManager.addAssetPath` resource loader,
  retained in-process sessions, and non-initializing Application class probe.
- Opt-in Application bootstrap experiment. It executes imported Application
  code under USBTool's UID and permissions and must only be used with trusted
  APKs. It is not an Android package runtime.
- VirtualApp Java/AIDL core and ARM64 native source integration from pinned
  upstream/fork revisions; see the included provenance and license files.
- Static readiness and manifest topology diagnostics, plus a merged-APK audit
  that checks all 50 Activity stub slots, all 50 ContentProvider stub slots,
  BinderProvider, required helper components, unique provider authorities,
  Android API 29 metadata, and ELF64 AArch64 `libva++.so`.
- Phase 20 names SharedPreferences keys by package + profile + preference,
  with five pure-Java unit tests. Profile files, cache, databases and app
  directories are rooted under each logical profile directory.

Still not implemented or device-verified:
- `VirtualCore.startup()`, system-service/framework hooks and complete process
  bootstrap for arbitrary imported APKs.
- Actual imported Activity/Service/Receiver/Provider lifecycle dispatch.
- Full PackageManager, permission, URI grant, Binder service and external
  storage virtualization.
- Separate Linux UID or an OS-enforced security sandbox. Logical profile
  directories and namespaced preferences are not security isolation.
- Physical Android 10 ARM64 device acceptance tests. CI build/audit success is
  not proof that arbitrary third-party APKs can run.

The Debug APK targets minSdk 29 / targetSdk 29, includes only arm64-v8a native
code, is V1 JAR-signed with V2 disabled, and is zipaligned. It is a test build,
not a production release.
EOF

cat > "$ROOT/USBTool/MOBILE-CLOUD-BUILD.md" <<'EOF'
# USBTool 手机云端构建

仓库：`aqwpp/APP`
工作流：`.github/workflows/usbtool-build.yml`
分支：`main`

## 自动构建

将 Phase 8 源码 ZIP 放在仓库根目录后，更新 `scripts/**` 或
`.github/workflows/usbtool-build.yml` 会触发 GitHub Actions。工作流会：

1. 解压基础工程并依次应用 Phase 9–20 增量脚本。
2. 使用 JDK 17、Gradle 8.7、Android SDK 35、NDK 27.2。
3. 执行 `:app:testDebugUnitTest`、`:app:assembleDebug`、
   `:fixture:assembleDebug`。
4. 检查合并后的 APK Manifest 中 VirtualApp Activity/Provider stub 槽位、
   BinderProvider、服务和 Provider authority。
5. 检查 APK 为 Android 10 / API 29，且 native 库为 ELF64 AArch64。
6. 使用 Debug 测试证书生成 V1-only APK，关闭 V2，并验证 ZIP 对齐。
7. 上传 APK、fixture、构建审计报告和可重建源码 ZIP。

## 手机下载与安装

在 GitHub 仓库打开 **Actions**，选择最新的
**USBTool Android 10 ARM64 Debug Build** 成功记录，在页面底部下载
`USBTool-Android10-ARM64-debug-apks`。解压后：

- `app-debug.apk`：USBTool 主程序，安装此文件。
- `fixture-debug.apk`：自编译测试 APK，可导入 USBTool 检查清单、DEX 和资源。
- `BUILD_AUDIT_PHASE19.txt`：合并 Manifest / ABI 审计。
- `USBTool-Android10-ARM64-phase20-source.zip`：包含增量源码、构建脚本和第三方源码/许可文件。

Android 10 首次安装时，如系统询问“允许此来源安装应用”，请在系统设置中允许
当前浏览器或文件管理器安装 APK。该 Debug APK 仅适用于测试。

## 签名与升级

工作流使用自动生成的 Debug keystore，不需要用户提供 JKS。密钥保存在
GitHub Actions cache 中以尽量保持后续测试版签名一致；若仓库缓存被清除，
新密钥会导致更新签名不匹配，需要先卸载旧测试版再安装新版本。不要把 Debug
密钥当作正式发布密钥。

## 能力边界

构建成功、Manifest 审计通过和 V1 签名验证，只证明 APK 构建与静态打包检查通过。
当前尚未在真实 Android 10 ARM64 手机验证 VirtualCore 启动、系统 Hook 或导入 APK
的 Activity/Service/Provider 实际执行；也没有独立 Android UID 或安全沙箱。
请只对自己信任的 APK 使用 Application 初始化实验。
EOF

echo "Phase 20: per-profile SharedPreferences key isolation and updated project documentation added."
