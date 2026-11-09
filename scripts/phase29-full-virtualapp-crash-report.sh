#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
p=Path("USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java")
s=p.read_text()
if "StringWriter" not in s:
    s=s.replace("import java.io.File;", "import java.io.File;\nimport java.io.PrintWriter;\nimport java.io.StringWriter;")
old='''            } catch (Throwable error) {
                result = "VirtualApp 安装/启动异常：" + error.getClass().getName()
                        + "\\n" + String.valueOf(error.getMessage());
            }'''
new='''            } catch (Throwable error) {
                StringWriter trace = new StringWriter();
                error.printStackTrace(new PrintWriter(trace));
                VirtualCore core = VirtualCore.get();
                result = "VirtualApp 安装/启动异常：" + error.getClass().getName()
                        + "\\nMessage: " + String.valueOf(error.getMessage())
                        + "\\nProcess: " + android.app.Application.getProcessName()
                        + "\\nVirtualCore startup: " + core.isStartup()
                        + "\\nEngine launched: " + core.isEngineLaunched()
                        + "\\nNative ABI: " + android.os.Build.SUPPORTED_ABIS[0]
                        + "\\n\\n完整堆栈：\\n" + trace;
            }'''
if old not in s: raise SystemExit("runner catch block did not match")
p.write_text(s.replace(old,new))
p=Path("USBTool/app/src/main/java/com/ssai/usbtool/USBToolApplication.java")
s=p.read_text()
if "StringWriter" not in s:
    s=s.replace("import android.util.Log;", "import android.util.Log;\nimport java.io.PrintWriter;\nimport java.io.StringWriter;")
old='''            startupFailure = error.getClass().getName() + ": " + String.valueOf(error.getMessage());
            Log.e(TAG, "VirtualCore startup failed before provider initialization", error);'''
new='''            StringWriter trace = new StringWriter();
            error.printStackTrace(new PrintWriter(trace));
            startupFailure = trace.toString();
            Log.e(TAG, "VirtualCore startup failed before provider initialization", error);'''
if old not in s: raise SystemExit("application startup catch block did not match")
p.write_text(s.replace(old,new))
PY
grep -q '完整堆栈' USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java
grep -q 'StringWriter' USBTool/app/src/main/java/com/ssai/usbtool/USBToolApplication.java
cat > USBTool/BUILD_AUDIT_PHASE29.txt <<'AUDIT'
USBTool Phase 29 - full VirtualApp crash diagnostics
- Preserve complete Java stack traces for guest install/launch failures.
- Report process name, VirtualCore startup state, engine visibility, and primary ABI.
- Preserve early Application startup stack trace in the diagnostics report.
- This is diagnostic instrumentation; it does not claim the Binder server crash is fixed.
AUDIT
echo "Phase 29 full VirtualApp crash diagnostics source audit passed."
