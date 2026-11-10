#!/usr/bin/env bash
set -euo pipefail
FILE="USBTool/va-lib/src/main/java/com/lody/virtual/helper/compat/ContentProviderCompat.java"
test -s "$FILE"
python3 - <<'PY'
from pathlib import Path
p = Path("USBTool/va-lib/src/main/java/com/lody/virtual/helper/compat/ContentProviderCompat.java")
s = p.read_text()
if "usbtool_va_provider_client_stage.txt" in s:
    raise SystemExit("Phase 53 provider-client diagnostics already present")
old_import = "import android.content.ContentProviderClient;\n"
new_import = old_import + "import android.app.Application;\nimport android.os.Process;\nimport java.io.File;\nimport java.io.FileOutputStream;\n"
if old_import not in s:
    raise SystemExit("ContentProviderClient import marker missing")
s = s.replace(old_import, new_import, 1)
start = s.index("    public static Bundle call(Context context, Uri uri, String method, String arg, Bundle extras) {")
end = s.index("\n    private static ContentProviderClient acquireContentProviderClient", start)
new_block = r'''    private static void writeUSBToolProviderClientStage(Context context, Uri uri, String stage) {
        try {
            if (context == null || !"com.ssai.usbtool".equals(context.getPackageName())) return;
            File marker = new File(context.getFilesDir(), "usbtool_va_provider_client_stage.txt");
            String process;
            try {
                process = Application.getProcessName();
            } catch (Throwable ignored) {
                process = "unknown";
            }
            String line = "pid=" + Process.myPid() + " process=" + process
                    + " elapsedRealtime=" + SystemClock.elapsedRealtime()
                    + " authority=" + (uri == null ? "null" : uri.getAuthority())
                    + " stage=" + stage.replace('\n', ' ') + "\n";
            // O_APPEND keeps each short diagnostic record together across processes.
            try (FileOutputStream out = new FileOutputStream(marker, true)) {
                out.write(line.getBytes("UTF-8"));
                out.flush();
            }
        } catch (Throwable ignored) {
            // Diagnostics must never alter ContentProvider behavior.
        }
    }

    public static Bundle call(Context context, Uri uri, String method, String arg, Bundle extras) {
        writeUSBToolProviderClientStage(context, uri, "call begin method=" + method);
        if (VERSION.SDK_INT < Build.VERSION_CODES.JELLY_BEAN_MR1) {
            writeUSBToolProviderClientStage(context, uri, "before legacy ContentResolver.call");
            Bundle result = context.getContentResolver().call(uri, method, arg, extras);
            writeUSBToolProviderClientStage(context, uri, "after legacy ContentResolver.call result=" + (result != null));
            return result;
        }
        writeUSBToolProviderClientStage(context, uri, "before acquire ContentProviderClient");
        ContentProviderClient client = crazyAcquireContentProvider(context, uri);
        writeUSBToolProviderClientStage(context, uri, "after acquire ContentProviderClient acquired=" + (client != null));
        if (client == null) {
            throw new IllegalStateException("Unable to acquire ContentProviderClient for " + uri);
        }
        Bundle res = null;
        try {
            writeUSBToolProviderClientStage(context, uri, "before ContentProviderClient.call method=" + method);
            res = client.call(method, arg, extras);
            writeUSBToolProviderClientStage(context, uri, "after ContentProviderClient.call result=" + (res != null));
        } catch (RemoteException e) {
            writeUSBToolProviderClientStage(context, uri, "ContentProviderClient.call RemoteException="
                    + e.getClass().getName() + ": " + String.valueOf(e.getMessage()));
            e.printStackTrace();
        } catch (RuntimeException e) {
            writeUSBToolProviderClientStage(context, uri, "ContentProviderClient.call RuntimeException="
                    + e.getClass().getName() + ": " + String.valueOf(e.getMessage()));
            throw e;
        } catch (Error e) {
            writeUSBToolProviderClientStage(context, uri, "ContentProviderClient.call Error="
                    + e.getClass().getName() + ": " + String.valueOf(e.getMessage()));
            throw e;
        } finally {
            writeUSBToolProviderClientStage(context, uri, "before ContentProviderClient.close");
            releaseQuietly(client);
            writeUSBToolProviderClientStage(context, uri, "after ContentProviderClient.close");
        }
        return res;
    }
'''
s = s[:start] + new_block + s[end:]
old_acquire = '''    private static ContentProviderClient acquireContentProviderClient(Context context, Uri uri) {
        if (VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
            return context.getContentResolver().acquireUnstableContentProviderClient(uri);
        }
        return context.getContentResolver().acquireContentProviderClient(uri);
    }'''
new_acquire = '''    private static ContentProviderClient acquireContentProviderClient(Context context, Uri uri) {
        if (VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
            writeUSBToolProviderClientStage(context, uri, "before acquireUnstableContentProviderClient");
            ContentProviderClient client = context.getContentResolver().acquireUnstableContentProviderClient(uri);
            writeUSBToolProviderClientStage(context, uri, "after acquireUnstableContentProviderClient client=" + (client != null));
            return client;
        }
        writeUSBToolProviderClientStage(context, uri, "before acquireContentProviderClient");
        ContentProviderClient client = context.getContentResolver().acquireContentProviderClient(uri);
        writeUSBToolProviderClientStage(context, uri, "after acquireContentProviderClient client=" + (client != null));
        return client;
    }'''
if old_acquire not in s:
    raise SystemExit("URI acquire helper marker missing")
s = s.replace(old_acquire, new_acquire, 1)
old_retry = '''    public static ContentProviderClient crazyAcquireContentProvider(Context context, Uri uri) {
        ContentProviderClient client = acquireContentProviderClient(context, uri);
        if (client == null) {
            int retry = 0;
            while (retry < 5 && client == null) {
                SystemClock.sleep(100);
                retry++;
                client = acquireContentProviderClient(context, uri);
            }
        }
        return client;
    }'''
new_retry = '''    public static ContentProviderClient crazyAcquireContentProvider(Context context, Uri uri) {
        ContentProviderClient client = null;
        for (int retry = 0; retry <= 5; retry++) {
            writeUSBToolProviderClientStage(context, uri, "acquire attempt=" + retry + " begin");
            client = acquireContentProviderClient(context, uri);
            writeUSBToolProviderClientStage(context, uri, "acquire attempt=" + retry
                    + " end client=" + (client != null));
            if (client != null) return client;
            if (retry < 5) {
                writeUSBToolProviderClientStage(context, uri, "acquire retry sleep 100ms");
                SystemClock.sleep(100);
            }
        }
        return null;
    }'''
if old_retry not in s:
    raise SystemExit("URI retry helper marker missing")
s = s.replace(old_retry, new_retry, 1)
p.write_text(s)
PY
cat > USBTool/BUILD_AUDIT_PHASE53.txt <<'AUDIT'
USBTool Phase 53 - ContentProviderClient acquisition/call diagnostics
Target: Android 10 / API 29; arm64-v8a; no root.

Added persistent stage breadcrumbs around:
- ProviderCall entry and target authority/method.
- Each acquireUnstableContentProviderClient attempt.
- ContentProviderClient acquisition completion or null result.
- ContentProviderClient.call begin/completion and RemoteException/runtime/Error.
- ContentProviderClient close begin/completion.

Purpose:
The latest device report reached VActivityManagerService's
"before ProviderCall.call authority=com.ssai.usbtool.virtual_stub_0" marker,
but had no StubContentProvider.onCreate/call marker and no return marker.
The new client-stage file distinguishes a stall while acquiring/starting the
stub provider from a stall inside the provider's Binder call.

Diagnostic file:
files/usbtool_va_provider_client_stage.txt (copied by the in-app diagnostics action).

This phase changes diagnostics only. It does not claim that provider startup,
guest process attachment, guest Activity display, independent UID, permission
isolation, or data/security isolation works. A fresh Android 10 ARM64 device
reproduction is still required.
AUDIT
echo "Phase 53 ContentProviderClient stage diagnostics added."
