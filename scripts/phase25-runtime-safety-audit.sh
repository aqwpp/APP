#!/usr/bin/env bash
set -euo pipefail
RUNNER="USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java"
ACTIVITY="USBTool/app/src/main/java/com/ssai/usbtool/MainActivity.java"
test -s "$RUNNER"
test -s "$ACTIVITY"
grep -q 'prepareOnMain' "$RUNNER"
grep -q 'Looper.myLooper() != Looper.getMainLooper()' "$RUNNER"
grep -q 'catch (Throwable error)' "$RUNNER"
grep -q 'Executors.newSingleThreadExecutor' "$RUNNER"
grep -q 'installAndLaunchAsync' "$RUNNER"
grep -q 'EXECUTOR.execute' "$RUNNER"
grep -q 'MAIN.post' "$RUNNER"
grep -q 'apk.isFile()' "$RUNNER"
grep -q 'prepareOnMain(this)' "$ACTIVITY"
grep -q 'installAndLaunchAsync(' "$ACTIVITY"
grep -q 'ProgressDialog' "$ACTIVITY"
! grep -q 'installAndLaunch(' "$RUNNER"
cat > USBTool/BUILD_AUDIT_PHASE25.txt <<'AUDIT'
USBTool Phase 25 - runtime call-path safety audit
Package: com.ssai.usbtool
Target: Android 10 / API 29; ARM64 native runtime

Verified source-level safeguards:
- VirtualCore preparation enforces the Android main thread.
- VirtualCore startup failures are converted into visible diagnostics.
- APK readability is checked before installation.
- Package install and launch request run on a single background executor.
- Completion is posted back to the main thread.
- UI displays a progress indicator during the operation.
- MainActivity uses the asynchronous runner API.

Not verified:
- VirtualCore startup or framework hooks on a physical Android 10 device.
- Successful guest package installation or Activity display.
- Separate guest UID, permission isolation, or a security sandbox.
- Behavior of arbitrary third-party APKs, native ABIs, services, receivers, and providers.
AUDIT
echo "Phase 25 runtime call-path source audit passed."
