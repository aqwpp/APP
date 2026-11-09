#!/usr/bin/env bash
set -euo pipefail
FILE="USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java"
python3 - <<'PY'
from pathlib import Path
p=Path("USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java")
s=p.read_text()
old='''        if (!core.isStartup()) core.startup(context.getApplicationContext());
        core.initialize(new VirtualCore.VirtualInitializer() {});
        core.waitForEngine();'''
new='''        try {
            if (!core.isStartup()) core.startup(context.getApplicationContext());
            core.initialize(new VirtualCore.VirtualInitializer() {});
            core.waitForEngine();
        } catch (Throwable error) {
            throw new IllegalStateException("VirtualCore 启动失败："
                    + error.getClass().getName() + " / " + String.valueOf(error.getMessage()), error);
        }'''
if old not in s: raise SystemExit("Expected startup block not found")
p.write_text(s.replace(old,new))
PY
echo "Phase 24: converts VirtualCore startup Throwable into a checked-safe runtime exception."
