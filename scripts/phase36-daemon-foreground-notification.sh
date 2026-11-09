#!/usr/bin/env bash
set -euo pipefail
TARGET="USBTool/va-lib/src/main/java/com/lody/virtual/client/stub/DaemonService.java"
test -s "$TARGET"
python3 - <<'PY'
from pathlib import Path
p=Path("USBTool/va-lib/src/main/java/com/lody/virtual/client/stub/DaemonService.java")
s=p.read_text()
if "USBTool valid foreground notification" not in s:
    s=s.replace("import android.app.Notification;\n", "import android.app.Notification;\nimport android.app.NotificationChannel;\nimport android.app.NotificationManager;\nimport android.content.pm.ApplicationInfo;\nimport android.os.Build;\n")
    s=s.replace('''\tpublic static void startup(Context context) {
\t\tcontext.startService(new Intent(context, DaemonService.class));
\t}''','''\tpublic static void startup(Context context) {
        try {
            context.startService(new Intent(context, DaemonService.class));
        } catch (Throwable error) {
            android.util.Log.e("USBTool-VADaemon", "Unable to start optional daemon service", error);
        }
    }

    /**
     * USBTool valid foreground notification: Android 8+ requires a channel and
     * Android's foreground-service notification must have a valid small icon.
     */
    private static Notification buildForegroundNotification(Context context) {
        final String channelId = "usbtool_virtual_runtime";
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationManager manager = (NotificationManager)
                    context.getSystemService(Context.NOTIFICATION_SERVICE);
            if (manager != null && manager.getNotificationChannel(channelId) == null) {
                manager.createNotificationChannel(new NotificationChannel(
                        channelId, "Virtual runtime", NotificationManager.IMPORTANCE_MIN));
            }
        }
        ApplicationInfo info = context.getApplicationInfo();
        int icon = info != null ? info.icon : 0;
        if (icon == 0) icon = android.R.drawable.stat_notify_sync;
        Notification.Builder builder = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? new Notification.Builder(context, channelId)
                : new Notification.Builder(context);
        return builder.setSmallIcon(icon)
                .setContentTitle("USBTool")
                .setContentText("Virtual runtime service")
                .setOngoing(true)
                .setCategory(Notification.CATEGORY_SERVICE)
                .setPriority(Notification.PRIORITY_MIN)
                .build();
    }

    private static void startForegroundSafely(Service service) {
        try {
            service.startForeground(NOTIFY_ID, buildForegroundNotification(service));
        } catch (Throwable error) {
            // A notification failure must not crash the BinderProvider's process.
            android.util.Log.e("USBTool-VADaemon",
                    "Foreground notification unavailable; keeping Binder process alive without daemon promotion",
                    error);
        }
    }''')
    s=s.replace('''\t@Override
\tpublic void onDestroy() {
\t\tsuper.onDestroy();
\t\tstartup(this);
\t}''','''    @Override
    public void onDestroy() {
        super.onDestroy();
        startup(this);
    }''')
    s=s.replace('''\t@Override
\tpublic void onCreate() {
\t\tsuper.onCreate();
        startService(new Intent(this, InnerService.class));
        startForeground(NOTIFY_ID, new Notification());

\t}''','''    @Override
    public void onCreate() {
        super.onCreate();
        try {
            startService(new Intent(this, InnerService.class));
        } catch (Throwable error) {
            android.util.Log.w("USBTool-VADaemon", "Unable to start transient inner service", error);
        }
        startForegroundSafely(this);
    }''')
    s=s.replace('''        public int onStartCommand(Intent intent, int flags, int startId) {
            startForeground(NOTIFY_ID, new Notification());
            stopForeground(true);
            stopSelf();
            return super.onStartCommand(intent, flags, startId);
        }''','''        public int onStartCommand(Intent intent, int flags, int startId) {
            startForegroundSafely(this);
            stopForeground(true);
            stopSelf();
            return START_NOT_STICKY;
        }''')
    p.write_text(s)
if "new Notification()" in p.read_text():
    raise SystemExit("Unsafe empty Notification() call remains")
if "buildForegroundNotification" not in p.read_text() or "startForegroundSafely" not in p.read_text():
    raise SystemExit("Safe foreground notification implementation missing")
PY
cat > USBTool/BUILD_AUDIT_PHASE36.txt <<'AUDIT'
USBTool Phase 36 - Android 10 foreground daemon notification hardening

- Replace empty Notification() passed to startForeground() with a valid notification.
- Create a low-importance notification channel on Android 8+.
- Use the application icon, with a platform small-icon fallback.
- Guard optional daemon and inner-service startup against runtime exceptions.
- Guard startForeground() so notification failures do not directly crash the BinderProvider process.
- This reduces a concrete engine-process crash risk; it does not prove Binder stability or guest APK compatibility.
AUDIT
echo "Phase 36 foreground daemon notification audit passed."
