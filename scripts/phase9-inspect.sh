#!/usr/bin/env bash
set -euo pipefail
echo "=== APP JAVA/KOTLIN SOURCES ==="
find app/src -type f \\( -name '*.java' -o -name '*.kt' -o -name '*.xml' \\) | sort
echo "=== APP GRADLE ==="
sed -n '1,240p' app/build.gradle
echo "=== MANIFEST ==="
sed -n '1,260p' app/src/main/AndroidManifest.xml
echo "=== MAIN SOURCE CONTENTS ==="
while IFS= read -r f; do
  case "$f" in
    *.java|*.kt) echo "===== $f ====="; sed -n '1,260p' "$f";;
  esac
done < <(find app/src/main -type f \\( -name '*.java' -o -name '*.kt' \\) | sort)
