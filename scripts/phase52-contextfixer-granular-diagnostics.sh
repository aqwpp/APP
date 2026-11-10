#!/usr/bin/env bash
set -euo pipefail
CORE="USBTool/va-lib/src/main/java/com/lody/virtual/client/fixer/ContextFixer.java"
MAIN="USBTool/app/src/main/java/com/ssai/usbtool/MainActivity.java"
test -s "$CORE"
test -s "$MAIN"

python3 - <<'PY'
from pathlib import Path
p = Path("USBTool/va-lib/src/main/java/com/lody/virtual/client/fixer/ContextFixer.java")
s = p.read_text()

if "writeUSBToolContextFixerStage(" not in s:
    helper = r"""
    // Persist fine-grained ContextFixer progress on vendor Android 10 builds.
    // Diagnostic failures are deliberately isolated and never replace the real error.
    private static void writeUSBToolContextFixerStage(Context context, String stage) {
        try {
            Context target = context;
            if (target == null) target = VirtualCore.get().getContext();
            if (target == null) return;
            java.io.File marker = new java.io.File(target.getFilesDir(),
                    "usbtool_va_context_fixer_stage.txt");
            String line = "pid=" + android.os.Process.myPid()
                    + " process=" + android.app.Application.getProcessName()
                    + " time=" + System.currentTimeMillis()
                    + " stage=" + stage + "\\n";
            android.util.Log.i("USBToolContextFixer", line.trim());
            try (java.io.FileOutputStream out = new java.io.FileOutputStream(marker, true)) {
                out.write(line.getBytes("UTF-8"));
                out.flush();
                out.getFD().sync();
            }
        } catch (Throwable ignored) {
            // Do not mask ContextFixer behavior with a diagnostic I/O failure.
        }
    }

"""
    anchor = "    public static void fixContext(Context context) {"
    if anchor not in s:
        raise SystemExit("ContextFixer.fixContext anchor missing")
    s = s.replace(anchor, helper + anchor, 1)

    replacements = [
      ("        try {\n            context.getPackageName();\n        } catch (Throwable e) {\n            return;\n        }",
       "        writeUSBToolContextFixerStage(context, \"before context.getPackageName\");\n        try {\n            context.getPackageName();\n            writeUSBToolContextFixerStage(context, \"complete context.getPackageName\");\n        } catch (Throwable e) {\n            writeUSBToolContextFixerStage(context, \"failed context.getPackageName: \" + e);\n            return;\n        }"),
      ("        InvocationStubManager.getInstance().checkEnv(GraphicsStatsStub.class);",
       "        writeUSBToolContextFixerStage(context, \"before checkEnv GraphicsStatsStub\");\n        InvocationStubManager.getInstance().checkEnv(GraphicsStatsStub.class);\n        writeUSBToolContextFixerStage(context, \"complete checkEnv GraphicsStatsStub\");"),
      ("        int deep = 0;",
       "        writeUSBToolContextFixerStage(context, \"before unwrap ContextWrapper\");\n        int deep = 0;"),
      ("        ContextImpl.mPackageManager.set(context, null);",
       "        writeUSBToolContextFixerStage(context, \"complete unwrap ContextWrapper depth=\" + deep);\n        writeUSBToolContextFixerStage(context, \"before ContextImpl.mPackageManager.set\");\n        ContextImpl.mPackageManager.set(context, null);\n        writeUSBToolContextFixerStage(context, \"complete ContextImpl.mPackageManager.set\");"),
      ("        try {\n            context.getPackageManager();\n        } catch (Throwable e) {\n            e.printStackTrace();\n        }",
       "        try {\n            writeUSBToolContextFixerStage(context, \"before context.getPackageManager refresh\");\n            context.getPackageManager();\n            writeUSBToolContextFixerStage(context, \"complete context.getPackageManager refresh\");\n        } catch (Throwable e) {\n            writeUSBToolContextFixerStage(context, \"failed context.getPackageManager refresh: \" + e);\n            e.printStackTrace();\n        }"),
      ("        if (!VirtualCore.get().isVAppProcess()) {\n            return;\n        }",
       "        writeUSBToolContextFixerStage(context, \"process type checked isVAppProcess=\" + VirtualCore.get().isVAppProcess());\n        if (!VirtualCore.get().isVAppProcess()) {\n            writeUSBToolContextFixerStage(context, \"complete ContextFixer non-virtual process\");\n            return;\n        }"),
      ("        DropBoxManager dm = (DropBoxManager) context.getSystemService(Context.DROPBOX_SERVICE);",
       "        writeUSBToolContextFixerStage(context, \"before getSystemService DROPBOX\");\n        DropBoxManager dm = (DropBoxManager) context.getSystemService(Context.DROPBOX_SERVICE);\n        writeUSBToolContextFixerStage(context, \"complete getSystemService DROPBOX managerNull=\" + (dm == null));"),
      ("        BinderInvocationStub boxBinder = InvocationStubManager.getInstance().getInvocationStub(DropBoxManagerStub.class);",
       "        writeUSBToolContextFixerStage(context, \"before get DropBoxManagerStub\");\n        BinderInvocationStub boxBinder = InvocationStubManager.getInstance().getInvocationStub(DropBoxManagerStub.class);\n        writeUSBToolContextFixerStage(context, \"complete get DropBoxManagerStub binderNull=\" + (boxBinder == null));"),
      ("                Reflect.on(dm).set(\"mService\", boxBinder.getProxyInterface());",
       "                writeUSBToolContextFixerStage(context, \"before reflect DropBoxManager.mService\");\n                Reflect.on(dm).set(\"mService\", boxBinder.getProxyInterface());\n                writeUSBToolContextFixerStage(context, \"complete reflect DropBoxManager.mService\");"),
      ("            } catch (ReflectException e) {\n                e.printStackTrace();\n            }",
       "            } catch (ReflectException e) {\n                writeUSBToolContextFixerStage(context, \"failed reflect DropBoxManager.mService: \" + e);\n                e.printStackTrace();\n            }"),
      ("        String hostPkg = VirtualCore.get().getHostPkg();",
       "        writeUSBToolContextFixerStage(context, \"before get host package\");\n        String hostPkg = VirtualCore.get().getHostPkg();\n        writeUSBToolContextFixerStage(context, \"complete get host package valueNull=\" + (hostPkg == null));"),
      ("        ContextImpl.mBasePackageName.set(context, hostPkg);",
       "        writeUSBToolContextFixerStage(context, \"before ContextImpl.mBasePackageName.set\");\n        ContextImpl.mBasePackageName.set(context, hostPkg);\n        writeUSBToolContextFixerStage(context, \"complete ContextImpl.mBasePackageName.set\");"),
      ("            ContextImplKitkat.mOpPackageName.set(context, hostPkg);",
       "            writeUSBToolContextFixerStage(context, \"before ContextImplKitkat.mOpPackageName.set\");\n            ContextImplKitkat.mOpPackageName.set(context, hostPkg);\n            writeUSBToolContextFixerStage(context, \"complete ContextImplKitkat.mOpPackageName.set\");"),
      ("            ContentResolverJBMR2.mPackageName.set(context.getContentResolver(), hostPkg);",
       "            writeUSBToolContextFixerStage(context, \"before ContentResolverJBMR2.mPackageName.set\");\n            ContentResolverJBMR2.mPackageName.set(context.getContentResolver(), hostPkg);\n            writeUSBToolContextFixerStage(context, \"complete ContentResolverJBMR2.mPackageName.set\");")
    ]
    for old, new in replacements:
        if old not in s:
            raise SystemExit("Missing ContextFixer instrumentation anchor: " + old[:90])
        s = s.replace(old, new, 1)

    s = s.replace(
        "        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {",
        "        writeUSBToolContextFixerStage(context, \"process ContextFixer virtual app branch\");\n        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {", 1)
    s = s.replace(
        "        }\n    }\n\n}",
        "        }\n        writeUSBToolContextFixerStage(context, \"complete ContextFixer virtual app branch\");\n    }\n\n}", 1)
p.write_text(s)

p = Path("USBTool/app/src/main/java/com/ssai/usbtool/MainActivity.java")
s = p.read_text()
old = '''                .append("Hook 注入逐项记录:\\n")
                .append(readDiagnosticTail("usbtool_va_injector_stage.txt", 16384)).append("\\n\\n")
                .append("Provider 调用阶段:\\n")'''
new = '''                .append("Hook 注入逐项记录:\\n")
                .append(readDiagnosticTail("usbtool_va_injector_stage.txt", 16384)).append("\\n\\n")
                .append("ContextFixer 逐项记录:\\n")
                .append(readDiagnosticTail("usbtool_va_context_fixer_stage.txt", 16384)).append("\\n\\n")
                .append("Provider 调用阶段:\\n")'''
if "ContextFixer 逐项记录:" not in s:
    if old not in s:
        raise SystemExit("MainActivity diagnostic report insertion anchor missing")
    s = s.replace(old, new, 1)
p.write_text(s)
PY

grep -q 'writeUSBToolContextFixerStage(context, "before ContextImpl.mPackageManager.set")' "$CORE"
grep -q 'ContextFixer 逐项记录:' "$MAIN"
cat > USBTool/BUILD_AUDIT_PHASE52.txt <<'AUDIT'
USBTool Phase 52 - granular ContextFixer diagnostics
- Phase 40 recorded only the broad ContextFixer.fixContext entry, leaving the exact failing operation unknown.
- Persist before/complete/failure breadcrumbs around context unwrapping, GraphicsStatsStub environment check, ContextImpl mirror writes, PackageManager refresh, DropBox service lookup/injection, and ContentResolver package-name update.
- Diagnostic I/O is best-effort and must not replace runtime exceptions.
- Add the ContextFixer trace to the in-app Copy Diagnostic Logs output.
- No framework hook is skipped and no exception is suppressed by this phase.
- Validation required: cloud Android build and fresh device logs; last ContextFixer BEFORE record identifies the next exact operation to investigate.
AUDIT
echo 'Phase 52 ContextFixer diagnostics patch applied.'
