#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path

main = Path("USBTool/app/src/main/java/com/ssai/usbtool/MainActivity.java")
s = main.read_text()
s = s.replace("import java.util.UUID;\n", "import java.util.UUID;\nimport java.util.zip.ZipFile;\n")
s = s.replace(
'''        try {
            String id = UUID.randomUUID().toString();''',
'''        File importedTarget = null;
        try {
            String id = UUID.randomUUID().toString();''',
1)
s = s.replace(
'''            File target = new File(apkDir, id + ".apk");
            try (InputStream in = getContentResolver().openInputStream(uri);
                 FileOutputStream out = new FileOutputStream(target)) {
                if (in == null) throw new Exception("无法读取所选文件");
                byte[] buffer = new byte[8192];
                int n;
                while ((n = in.read(buffer)) != -1) out.write(buffer, 0, n);
            }

            PackageManager pm = getPackageManager();''',
'''            File target = new File(apkDir, id + ".apk");
            importedTarget = target;
            long copied = 0L;
            try (InputStream in = getContentResolver().openInputStream(uri);
                 FileOutputStream out = new FileOutputStream(target)) {
                if (in == null) throw new Exception("无法读取所选文件");
                byte[] buffer = new byte[8192];
                int n;
                while ((n = in.read(buffer)) != -1) {
                    copied += n;
                    if (copied > 512L * 1024L * 1024L) {
                        throw new Exception("APK 超过 512 MB，已停止导入");
                    }
                    out.write(buffer, 0, n);
                }
                out.getFD().sync();
            }
            if (copied == 0L) throw new Exception("所选文件为空");
            try (ZipFile archive = new ZipFile(target)) {
                if (archive.getEntry("AndroidManifest.xml") == null) {
                    throw new Exception("APK 缺少 AndroidManifest.xml");
                }
            }

            PackageManager pm = getPackageManager();''',
1)
s = s.replace(
'''        } catch (Exception e) {
            new AlertDialog.Builder(this).setTitle("导入失败")''',
'''        } catch (Exception e) {
            if (importedTarget != null && importedTarget.exists()) importedTarget.delete();
            new AlertDialog.Builder(this).setTitle("导入失败")''',
1)
main.write_text(s)

store = Path("USBTool/app/src/main/java/com/ssai/usbtool/ProfileStore.java")
s = store.read_text()
s = s.replace("import java.nio.file.Files;\n", "import java.nio.file.Files;\nimport java.nio.file.StandardCopyOption;\nimport java.nio.file.AtomicMoveNotSupportedException;\n")
old = '''            Files.write(db.toPath(), arr.toString(2).getBytes(StandardCharsets.UTF_8));'''
new = '''            File tmp = new File(db.getParentFile(), "apps.json.tmp");
            Files.write(tmp.toPath(), arr.toString(2).getBytes(StandardCharsets.UTF_8));
            try {
                Files.move(tmp.toPath(), db.toPath(),
                        StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
            } catch (AtomicMoveNotSupportedException unsupported) {
                Files.move(tmp.toPath(), db.toPath(), StandardCopyOption.REPLACE_EXISTING);
            }'''
if old not in s:
    raise SystemExit("ProfileStore save target not found; refusing partial patch")
s = s.replace(old, new, 1)
store.write_text(s)
print("Phase 10 patch applied: bounded APK import, archive validation, failed-import cleanup, atomic app database writes.")
PY
