#!/usr/bin/env bash
set -euo pipefail
RUNNER="USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java"
test -s "$RUNNER"
python3 - <<'PY'
from pathlib import Path
p=Path("USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java")
s=p.read_text()
s=s.replace("import java.util.concurrent.Executors;", "import java.util.concurrent.Executors;\nimport java.util.concurrent.FutureTask;\nimport java.util.concurrent.TimeUnit;\nimport java.util.concurrent.TimeoutException;")
old='''            core.waitForEngine();
        } catch (Throwable error) {'''
new='''            // Engine readiness is awaited by the background install executor.
        } catch (Throwable error) {'''
if old not in s: raise SystemExit("Phase 38 wrapped wait anchor not found")
s=s.replace(old,new,1)
anchor='''    /** Package parsing/install and launch request are performed off the UI thread. */'''
helper='''    private static void awaitEngineOffMain(VirtualCore core) throws Exception {
        FutureTask<Void> task = new FutureTask<>(() -> {
            core.waitForEngine();
            return null;
        });
        Thread waiter = new Thread(task, "USBTool-EngineReadyWait");
        waiter.setDaemon(true);
        waiter.start();
        try {
            task.get(25, TimeUnit.SECONDS);
        } catch (TimeoutException timeout) {
            task.cancel(true);
            throw new IllegalStateException(
                    "等待 VirtualApp 引擎就绪超过 25 秒；已停止本次安装，避免界面无限等待。"
                    + " Engine launched=" + core.isEngineLaunched(), timeout);
        }
    }

    /** Package parsing/install and launch request are performed off the UI thread. */'''
if anchor not in s: raise SystemExit("Phase 38 helper insertion anchor not found")
s=s.replace(anchor,helper,1)
old2='''                VirtualCore core = VirtualCore.get();
                if (!core.isStartup()) {
                    throw new IllegalStateException("VirtualCore 尚未初始化；请先在主线程初始化引擎");
                }
                InstallResult install = core.installPackage('''
new2='''                VirtualCore core = VirtualCore.get();
                if (!core.isStartup()) {
                    throw new IllegalStateException("VirtualCore 尚未初始化；请先在主线程初始化引擎");
                }
                awaitEngineOffMain(core);
                InstallResult install = core.installPackage('''
if old2 not in s: raise SystemExit("Phase 38 background install anchor not found")
s=s.replace(old2,new2,1)
p.write_text(s)
PY
grep -q 'awaitEngineOffMain(core)' "$RUNNER"
grep -q 'task.get(25, TimeUnit.SECONDS)' "$RUNNER"
if grep -A10 'public static void prepareOnMain' "$RUNNER" | grep -q 'core.waitForEngine'; then
  echo "waitForEngine still appears in prepareOnMain"; exit 1
fi
cat > USBTool/BUILD_AUDIT_PHASE38.txt <<'AUDIT'
USBTool Phase 38 - move engine readiness wait off the launcher UI thread
- Confirmed Phase 23 called VirtualCore.waitForEngine() inside prepareOnMain().
- MainActivity invokes prepareOnMain() before showing its progress dialog.
- Removed the blocking engine wait from prepareOnMain(); framework startup/initialize remain on the main thread.
- The install executor now waits for engine readiness on a daemon worker thread.
- Added a 25-second bound and a readable timeout error instead of leaving the user with an unbounded wait.
- Build/source audit only. Physical Android 10 MT8183 validation is still required.
AUDIT
echo "Phase 38 UI-thread engine wait audit passed."
