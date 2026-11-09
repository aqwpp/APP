#!/usr/bin/env bash
set -euo pipefail
SRC="USBTool/va-lib/src/main/java/com/lody/virtual/server/pm/parser/PackageParserEx.java"
test -s "$SRC" || { echo "Missing PackageParserEx.java" >&2; exit 1; }
python3 - <<'PY'
from pathlib import Path
p = Path("USBTool/va-lib/src/main/java/com/lody/virtual/server/pm/parser/PackageParserEx.java")
s = p.read_text()
if "USBTool API 28+ SigningDetails compatibility" in s:
    print("Phase 33 already applied")
    raise SystemExit(0)
if "import java.lang.reflect.Field;" not in s:
    anchor = "import java.io.IOException;"
    if anchor not in s:
        raise SystemExit("Cannot locate Java imports")
    s = s.replace(anchor, anchor + "\nimport java.lang.reflect.Field;", 1)
old = "p.mSignatures = new Signature[]{new Signature(sig)};"
if old not in s:
    raise SystemExit("Cannot find fake-signature assignment")
s = s.replace(old, """if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
                setPackageSignatures(p, new Signature[]{new Signature(sig)});
            } else {
                // Android 9+ stores parsed signatures in Package.mSigningDetails.
                // Fake-signature mutation is intentionally not attempted on API 28+.
                PackageParserCompat.collectCertificates(parser, p, PackageParser.PARSE_IS_SYSTEM);
            }""", 1)
old = "cache.mSignatures = p.mSignatures;"
if old not in s:
    raise SystemExit("Cannot find PackageParser.Package.mSignatures read")
s = s.replace(old, "cache.mSignatures = getPackageSignatures(p);", 1)
anchor = "    private static VPackage buildPackageCache(PackageParser.Package p) {"
helpers = """    /**
     * USBTool API 28+ SigningDetails compatibility:
     * Android 9/10 removed PackageParser.Package.mSignatures and stores the
     * signer array in PackageParser.Package.mSigningDetails.signatures.
     * Use reflection so old Android releases can continue using mSignatures.
     */
    private static Signature[] getPackageSignatures(PackageParser.Package pkg) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                Field detailsField = pkg.getClass().getDeclaredField("mSigningDetails");
                detailsField.setAccessible(true);
                Object details = detailsField.get(pkg);
                if (details == null) return null;
                Field signaturesField = details.getClass().getDeclaredField("signatures");
                signaturesField.setAccessible(true);
                return (Signature[]) signaturesField.get(details);
            }
            Field signaturesField = pkg.getClass().getDeclaredField("mSignatures");
            signaturesField.setAccessible(true);
            return (Signature[]) signaturesField.get(pkg);
        } catch (Throwable e) {
            throw new IllegalStateException("Unable to read PackageParser signing details on API "
                    + Build.VERSION.SDK_INT, e);
        }
    }

    private static void setPackageSignatures(PackageParser.Package pkg, Signature[] signatures) {
        try {
            Field signaturesField = pkg.getClass().getDeclaredField("mSignatures");
            signaturesField.setAccessible(true);
            signaturesField.set(pkg, signatures);
        } catch (Throwable e) {
            throw new IllegalStateException("Unable to set legacy PackageParser signatures", e);
        }
    }

"""
if anchor not in s:
    raise SystemExit("Cannot locate buildPackageCache insertion point")
s = s.replace(anchor, helpers + anchor, 1)
if "cache.mSignatures = p.mSignatures;" in s or "p.mSignatures =" in s:
    raise SystemExit("Direct PackageParser mSignatures access remains")
if "getPackageSignatures(p)" not in s or "mSigningDetails" not in s:
    raise SystemExit("Phase 33 verification failed")
p.write_text(s)
PY
cat > USBTool/BUILD_AUDIT_PHASE33.txt <<'AUDIT'
USBTool Phase 33 - Android 9/10 PackageParser signing details compatibility
- Android 9/API 28+ no longer exposes PackageParser.Package.mSignatures.
- Reads signer arrays from PackageParser.Package.mSigningDetails.signatures on API 28+.
- Retains reflective mSignatures access on older Android versions.
- Fake-signature metadata mutation is disabled on API 28+; normal certificate verification is used instead.
- Any reflection failure is surfaced as an explicit parser diagnostic rather than a linkage error.
- Guest app execution and framework compatibility remain unverified.
AUDIT
echo "Phase 33 Android signing details compatibility audit passed."
