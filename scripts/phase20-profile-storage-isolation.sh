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
            String identity = packageName.length() + ":" + packageName\n                    + profileId.length() + ":" + profileId\n                    + preferenceName.length() + ":" + preferenceName;
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

echo "Phase 20: per-profile SharedPreferences key isolation added with five unit tests."
