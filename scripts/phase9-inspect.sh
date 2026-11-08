#!/usr/bin/env bash
set -euo pipefail
echo "=== APP JAVA/KOTLIN/XML SOURCES ==="
find app/src -type f | grep -E '\.(java|kt|xml)$' | sort || true
echo "=== APP GRADLE ==="
sed -n '1,240p' app/build.gradle
echo "=== MANIFEST ==="
sed -n '1,260p' app/src/main/AndroidManifest.xml
echo "=== MAIN JAVA/KOTLIN SOURCE CONTENTS ==="
while IFS= read -r f; do
  echo "===== $f ====="
  sed -n '1,260p' "$f"
done < <(find app/src/main -type f | grep -E '\.(java|kt)$' | sort)
