#!/usr/bin/env bash
# cdn-reload.sh — build lại sunnypoint-web-localcdn rồi redeploy /cdn trên mọi Tomcat instance đang chạy
#   ./cdn-reload.sh                 build (mvn -q package -DskipTests) + tc.sh reload all cdn
#   ./cdn-reload.sh --no-build      chỉ redeploy /cdn
#   ./cdn-reload.sh retailer admin  chỉ redeploy trên các instance này
#   CDN_MODULE=/đường/dẫn/module ./cdn-reload.sh   (mặc định suy ra từ ~/tomcat/shared-webapps/cdn)
set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
TC_ROOT="${TC_ROOT:-$(dirname "$SCRIPTS_DIR")}"
BUILD=1; TARGETS=""
for a in "$@"; do case "$a" in --no-build) BUILD=0;; -h|--help) sed -n 2,6p "$0"; exit 0;; *) TARGETS="$TARGETS $a";; esac; done

if [[ -z "${CDN_MODULE:-}" ]]; then
  link="$TC_ROOT/shared-webapps/cdn"
  [[ -L "$link" ]] || { echo "LỖI: không thấy symlink $link — đặt CDN_MODULE=..." >&2; exit 1; }
  CDN_MODULE="$(dirname "$(dirname "$(readlink "$link")")")"     # .../sunnypoint-web-localcdn/target/webapp-current -> module
fi

if (( BUILD )); then
  [[ -f "$CDN_MODULE/pom.xml" ]] || { echo "LỖI: $CDN_MODULE không có pom.xml" >&2; exit 1; }
  echo "== Build $CDN_MODULE"
  start=$(date +%s)
  (cd "$CDN_MODULE" && mvn -q package -DskipTests) || { echo "LỖI: build thất bại — không redeploy" >&2; exit 1; }
  echo "   build xong trong $(( $(date +%s) - start ))s"
fi

echo "== Redeploy /cdn"
if [[ -n "$TARGETS" ]]; then
  rc=0; for t in $TARGETS; do "$SCRIPTS_DIR/tc.sh" reload "$t" cdn || rc=1; done; exit $rc
else
  exec "$SCRIPTS_DIR/tc.sh" reload all cdn
fi
